import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/printer_service.dart';
import '../services/raster_lab.dart';

/// Staged Devanagari-print diagnostic lab for the Shreyans PSF-80B.
/// Each stage prints its OWN labeled slip so failures localize.
class RasterLabScreen extends StatefulWidget {
  const RasterLabScreen({super.key});

  @override
  State<RasterLabScreen> createState() => _RasterLabScreenState();
}

class _RasterLabScreenState extends State<RasterLabScreen> {
  static const List<String> cases = [
    'क्ष त्र ज्ञ श्र',
    'कॉफी',
    'चहा',
    'सँडविच',
    'वडा पाव',
    'एकूण रक्कम',
    'धन्यवाद! पुन्हा भेटू.',
    'मोबाईल क्रमांक',
    'एकूण: Rs.120.00',
  ];

  int _width = RasterLab.dots80mm;
  bool _busy = false;
  String _log = 'Run stages top to bottom. Each prints a labeled slip.';
  Uint8List? _stage3Png;
  Uint8List? _stage4Png;
  Uint8List? _demoBillPng;

  // Stage 5 tuning
  int _chunkSize = 1024;
  int _delayMs = 0;

  void _append(String s) {
    if (mounted) setState(() => _log = '$_log\n$s');
  }

  Future<void> _guard(String name, Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _log = '▶ $name…';
    });
    try {
      await body();
      _append('✅ $name done — inspect the slip.');
    } catch (e) {
      _append('❌ $name failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Stage 1 ──────────────────────────────────────────────────────────────
  Future<void> _stage1() => _guard('Stage 1: raster + packing', () async {
        final bytes = await RasterLab.stage1Checkerboard(width: _width);
        _append('Payload ${bytes.length} bytes. Checkerboard must be square & '
            'aligned (no diagonal shear).');
        await PrinterService.instance.printRawBytes(bytes);
      });

  // ── Stage 3 ──────────────────────────────────────────────────────────────
  Future<void> _stage3() => _guard('Stage 3: single word कॉफी', () async {
        final r = await RasterLab.stage3SingleWord('कॉफी', width: _width);
        setState(() => _stage3Png = r.previewPng);
        _append('Bitmap ${r.width}×${r.height} dots, bytesPerRow=${r.bytesPerRow}'
            '. PNG preview below = EXACT bits sent. Compare to the print.');
        await PrinterService.instance.printRawBytes(r.bytes);
      });

  // ── Stage 4 ──────────────────────────────────────────────────────────────
  Future<void> _stage4() => _guard('Stage 4: all lines, one bitmap', () async {
        final r = await RasterLab.stage4AllLines(cases, width: _width);
        setState(() => _stage4Png = r.previewPng);
        _append('One image ${r.width}×${r.height}, banded @256. PNG below.');
        await PrinterService.instance.printRawBytes(r.bytes);
      });

  // ── Stage 5 ──────────────────────────────────────────────────────────────
  Future<void> _stage5() =>
      _guard('Stage 5: chunk=$_chunkSize delay=${_delayMs}ms', () async {
        final r = await RasterLab.stage4AllLines(cases, width: _width);
        final sw = Stopwatch()..start();
        await PrinterService.instance.printRawBytesTuned(
          r.bytes,
          chunkSize: _chunkSize,
          delayMs: _delayMs,
        );
        _append('Sent ${r.bytes.length} bytes in ${sw.elapsedMilliseconds}ms '
            '(chunk=$_chunkSize, delay=${_delayMs}ms). Check for blank bands.');
      });

  // ── Demo bill ────────────────────────────────────────────────────────────
  // Uses the winning transport: single write, 0ms delay.
  Future<void> _demoBill(DemoLang lang) =>
      _guard('Demo Bill — ${lang.label} (single-write, 0ms)', () async {
        final r = await RasterLab.demoBill(lang: lang, width: _width);
        setState(() => _demoBillPng = r.previewPng);
        final sw = Stopwatch()..start();
        await PrinterService.instance
            .printRawBytesTuned(r.bytes, chunkSize: 0, delayMs: 0);
        _append('${lang.label} bill ${r.width}×${r.height}, ${r.bytes.length} '
            'bytes sent in ${sw.elapsedMilliseconds}ms. PNG below.');
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raster Lab'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _paperToggle(),
                const SizedBox(height: 12),

                _stageBtn('Stage 1 — Raster + packing (checkerboard)',
                    'Skewed = packing/width bug, not fonts', Colors.brown,
                    _busy ? null : _stage1),

                // Stage 2 is on-screen only.
                _stage2Card(),

                _stageBtn('Stage 3 — Single word कॉफी + PNG dump',
                    'PNG below = exact bits sent to printer', Colors.teal,
                    _busy ? null : _stage3),
                if (_stage3Png != null) _pngPreview('Stage 3 bitmap', _stage3Png!),

                _stageBtn('Stage 4 — All lines, one continuous bitmap',
                    'Single capture, banded @256', Colors.green,
                    _busy ? null : _stage4),
                if (_stage4Png != null) _pngPreview('Stage 4 bitmap', _stage4Png!),

                _stage5Card(),

                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Demo bills ★ (single-write, 0ms) — each script '
                      'uses its own bundled Noto font',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ),
                _stageBtn('Print Demo Bill — Marathi (Devanagari)',
                    'देवनागरी', Colors.indigo,
                    _busy ? null : () => _demoBill(DemoLang.marathi)),
                _stageBtn('Print Demo Bill — Tamil', 'தமிழ்', Colors.indigo,
                    _busy ? null : () => _demoBill(DemoLang.tamil)),
                _stageBtn('Print Demo Bill — Gujarati', 'ગુજરાતી',
                    Colors.indigo,
                    _busy ? null : () => _demoBill(DemoLang.gujarati)),
                if (_demoBillPng != null)
                  _pngPreview('Demo bill bitmap', _demoBillPng!),

                const SizedBox(height: 12),
                _logPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paperToggle() => Row(
        children: [
          const Text('Paper: '),
          ChoiceChip(
            label: const Text('58mm'),
            selected: _width == RasterLab.dots58mm,
            onSelected: (_) => setState(() => _width = RasterLab.dots58mm),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('80mm'),
            selected: _width == RasterLab.dots80mm,
            onSelected: (_) => setState(() => _width = RasterLab.dots80mm),
          ),
        ],
      );

  Widget _stageBtn(
      String title, String sub, Color color, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: onTap == null ? Colors.grey.shade200 : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stage 2 — on-screen shaping proof using the bundled Noto Devanagari font.
  Widget _stage2Card() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stage 2 — On-screen shaping (does NOT print)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text(
              'By design this only renders in-app (no print) to confirm '
              'conjuncts shape correctly before trusting the raster.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                for (final c in cases)
                  Text(c,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontFamily: RasterLab.devanagariFont,
                        fontSize: 18,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage5Card() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stage 5 — Timing / chunking',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Text('Chunk size: $_chunkSize bytes',
              style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 6,
            children: [
              for (final c in [512, 1024, 4096, 0])
                ChoiceChip(
                  label: Text(c == 0 ? 'single' : '$c'),
                  selected: _chunkSize == c,
                  onSelected: (_) => setState(() => _chunkSize = c),
                ),
            ],
          ),
          Text('Inter-chunk delay: ${_delayMs}ms',
              style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 6,
            children: [
              for (final d in [0, 20, 40])
                ChoiceChip(
                  label: Text('${d}ms'),
                  selected: _delayMs == d,
                  onSelected: (_) => setState(() => _delayMs = d),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _busy ? null : _stage5,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white),
            child: const Text('Run Stage 5 (timed print)'),
          ),
        ],
      ),
    );
  }

  Widget _pngPreview(String label, Uint8List png) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label — exact 1-bit bitmap',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            color: Colors.white,
            child: Image.memory(png, fit: BoxFit.fitWidth),
          ),
        ],
      ),
    );
  }

  Widget _logPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_log,
          style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 12)),
    );
  }
}
