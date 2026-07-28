import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../services/devanagari_raster.dart';
import '../services/iscii_encoder.dart';
import '../services/printer_service.dart';

/// Diagnostic demo page for Marathi / Devanagari thermal printing.
///
/// Goal: PROVE on real hardware which strategy renders Marathi correctly on the
/// Shreyans 80B before we change the real receipt path.
///
/// CONFIRMED by the printer's own self-test: fonts = ASCII + GBK(Chinese) +
/// BIG5 + SHIFT-JIS only. There is NO Devanagari font ROM. Therefore native
/// text (UTF-8 or ISCII) can NEVER render Marathi on this printer — raster is
/// the only way, exactly like the working Play Store app.
///
/// The working app's "English speed" was NOT native text — it was FAST raster:
/// one tall image at 1:1 dots, sent in big Bluetooth chunks with no delay.
/// Strategy F reproduces that. A/B are kept as controls that prove native fails.
///
///  - Strategy F (FAST single raster ★): the fix. All lines → one image → fast send.
///  - Strategy A (UTF-8 text): control → garbage.
///  - Strategy B (ISCII): control → garbage (ROM is GBK, not Indian).
///  - Strategy D (per-line raster): the old slow way, for speed comparison.
///  - Strategy E (whole widget → PNG raster): alternate raster capture.
///
/// Every one of your required test cases is included below.
class MarathiPrintTestScreen extends StatefulWidget {
  const MarathiPrintTestScreen({super.key});

  @override
  State<MarathiPrintTestScreen> createState() => _MarathiPrintTestScreenState();
}

class _MarathiPrintTestScreenState extends State<MarathiPrintTestScreen> {
  // Your exact required test cases.
  static const List<String> _cases = [
    'कॉफी',
    'चहा',
    'सँडविच',
    'बिस्किट',
    'वडा पाव',
    'पाणी',
    'एकूण रक्कम',
    'धन्यवाद! पुन्हा भेटू.',
    'मोबाईल क्रमांक',
    'कर रक्कम',
    'सवलत',
    'रोख',
    'ऑनलाइन',
    // Conjuncts / ligatures that stress the shaper.
    'क्ष त्र ज्ञ श्र',
    // Mixed Marathi + English + numbers.
    'एकूण: Rs.120.00',
  ];

  int _widthDots = DevanagariRaster.dots80mm; // 80mm default
  bool _dither = false;
  double _fontSize = 24;
  double _scale = 1.0;
  bool _busy = false;
  String _log = 'Select paper width, then run a strategy.';

  final GlobalKey _receiptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Guarantee the bundled Devanagari font (Mangal) is registered before the
    // first raster render, so shaping never silently falls back to a wrong font.
    DevanagariRaster.ensureFontLoaded();
  }

  bool get _has80 => _widthDots == DevanagariRaster.dots80mm;

  // ─────────────────────────────────────────────────────────────────────────
  // Strategy A — Native ESC/POS text (the failing control)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _printNativeText() async {
    await _guard('Strategy A: Native UTF-8 text', () async {
      final b = <int>[];
      b.addAll([0x1B, 0x40]); // ESC @ reset
      void line(String s) {
        // Send raw UTF-8 — NOT filtered to '?'. This is the honest test of
        // whether the printer can render Devanagari itself.
        b.addAll(utf8.encode(s));
        b.add(0x0A);
      }

      line('--- STRATEGY A: NATIVE ---');
      for (final c in _cases) {
        line(c);
      }
      b.addAll([0x0A, 0x0A, 0x0A]);
      await PrinterService.instance.printRawBytes(Uint8List.fromList(b));
      _appendLog('Sent ${b.length} bytes (UTF-8, no filtering).');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Strategy B — NATIVE ISCII text  (the likely real winner)
  //
  // The working Play Store app prints crisp Marathi at English speed → the
  // printer has a Devanagari font ROM driven by ISCII single-byte codes.
  // We don't know the exact code-page selector, so we try several. Whichever
  // prints correct Marathi at full speed is THE answer for the real receipt.
  // ─────────────────────────────────────────────────────────────────────────

  /// Build the ISCII test body (header + all cases), no page selector.
  List<int> _isciiBody(String header) {
    final b = <int>[];
    void line(String s) {
      b.addAll(IsciiEncoder.encode(s));
      b.add(0x0A);
    }

    line(header);
    for (final c in _cases) {
      line(c);
    }
    b.addAll([0x0A, 0x0A, 0x0A]);
    return b;
  }

  /// B1: raw ISCII bytes, NO code-page command (printer may default to ISCII).
  Future<void> _printIsciiRaw() async {
    await _guard('Strategy B1: ISCII raw (no page cmd)', () async {
      final b = <int>[0x1B, 0x40, ..._isciiBody('--- B1: ISCII RAW ---')];
      await PrinterService.instance.printRawBytes(Uint8List.fromList(b));
      _appendLog('Sent ${b.length} bytes. If this is correct → use ISCII raw.');
    });
  }

  /// B2..B4: ISCII bytes preceded by `ESC t n` for candidate page numbers.
  /// Many Indian-font printers expose Devanagari on a specific page; we sweep
  /// the ones vendors commonly use. Runs each with a labelled header so you can
  /// see on paper which page value produced correct output.
  Future<void> _printIsciiPageSweep() async {
    await _guard('Strategy B2: ESC t page sweep', () async {
      // Candidate code-page selector values seen across Indian ESC/POS clones.
      const candidates = <int>[21, 22, 23, 24, 25, 26, 27, 28, 29, 30];
      final b = <int>[0x1B, 0x40];
      for (final n in candidates) {
        b.addAll([0x1B, 0x74, n]); // ESC t n → select code page n
        b.addAll(IsciiEncoder.encode('== ESC t $n =='));
        b.add(0x0A);
        b.addAll(IsciiEncoder.encode('कॉफी चहा एकूण रक्कम'));
        b.add(0x0A);
        b.addAll(IsciiEncoder.encode('क्ष त्र ज्ञ श्र १२३४५'));
        b.addAll([0x0A, 0x0A]);
      }
      b.addAll([0x0A, 0x0A]);
      await PrinterService.instance.printRawBytes(Uint8List.fromList(b));
      _appendLog('Swept ESC t ${candidates.first}..${candidates.last}. '
          'Note which page# printed correct Marathi.');
    });
  }

  /// B3: `FS &` (select 2-byte / Kanji-style multibyte mode) then ISCII.
  /// Some firmwares gate the Indian font behind FS & like CJK printers do.
  Future<void> _printIsciiFsAmp() async {
    await _guard('Strategy B3: FS & + ISCII', () async {
      final b = <int>[
        0x1B, 0x40, // reset
        0x1C, 0x26, // FS &  (select multibyte mode)
        ..._isciiBody('--- B3: FS & ISCII ---'),
        0x1C, 0x2E, // FS .  (cancel multibyte mode)
      ];
      await PrinterService.instance.printRawBytes(Uint8List.fromList(b));
      _appendLog('Sent ${b.length} bytes with FS & wrapper.');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Strategy F — FAST single raster  (THE fix for this GBK printer)
  //
  // The printer's self-test shows fonts: ASCII + GBK + BIG5 + SHIFT-JIS only —
  // NO Devanagari ROM. So ISCII is impossible; raster is the only way, exactly
  // like the working app. Crisp + smooth comes from: (1) 2x supersample →
  // high-quality downscale → thin-stroke threshold, (2) band-sliced GS v 0 for
  // continuous feed, (3) big BT chunks with no delay.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _printFastSingleRaster(RasterMode mode) async {
    final label = mode == RasterMode.escStar
        ? 'Strategy F: ESC * (smooth)'
        : 'Strategy F: GS v 0 (block)';
    await _guard(label, () async {
      final sw = Stopwatch()..start();
      final header =
          mode == RasterMode.escStar ? '--- ESC * SMOOTH ---' : '--- GS v 0 ---';
      final raster = await DevanagariRaster.linesToEscPosRaster(
        [header, ..._cases],
        widthDots: _widthDots,
        fontSize: _fontSize,
        // scale/threshold/weight use the crisp defaults (2x supersample →
        // downscale → thin-stroke threshold).
        dither: _dither,
        mode: mode,
      );
      final renderMs = sw.elapsedMilliseconds;
      _appendLog('Rendered (${raster.length} bytes) in ${renderMs}ms');
      final out = <int>[...raster, 0x0A, 0x0A, 0x0A];
      await PrinterService.instance.printRawBytes(Uint8List.fromList(out));
      _appendLog('Sent in ${sw.elapsedMilliseconds}ms total.');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Strategy D — Per-line bitmap (slower; for comparison)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _printBitmapPerLine() async {
    await _guard('Strategy D: Per-line bitmap', () async {
      final all = <int>[];
      // Header as bitmap too, so alignment matches.
      all.addAll(await DevanagariRaster.textToEscPosRaster(
        '--- STRATEGY D: BITMAP ---',
        widthDots: _widthDots,
        fontSize: _fontSize,
        scale: _scale,
        dither: _dither,
      ));
      var totalImgBytes = all.length;
      for (final c in _cases) {
        final raster = await DevanagariRaster.textToEscPosRaster(
          c,
          widthDots: _widthDots,
          fontSize: _fontSize,
          scale: _scale,
          dither: _dither,
        );
        totalImgBytes += raster.length;
        all.addAll(raster);
      }
      all.addAll([0x0A, 0x0A, 0x0A]);
      _appendLog('Raster payload: $totalImgBytes bytes, ${_cases.length + 1} '
          'strips @ ${_widthDots}dots, scale $_scale, '
          'dither=${_dither ? "on" : "off"}');
      // slow=true → smaller BT chunks so raster rows aren't dropped.
      await PrinterService.instance
          .printRawBytes(Uint8List.fromList(all), slow: true);
      _appendLog('Sent ${all.length} bytes.');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Strategy E — Whole receipt as one image
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _printWholeImage() async {
    await _guard('Strategy E: Whole-receipt image', () async {
      final ro = _receiptKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        throw StateError('Receipt preview not ready — scroll it into view');
      }
      final img = await ro.toImage(pixelRatio: 3.0);
      _appendLog('Captured receipt image ${img.width}x${img.height}px');
      final raster = await DevanagariRaster.imageToEscPosRaster(
        img,
        dither: _dither,
      );
      img.dispose();
      final out = <int>[...raster, 0x0A, 0x0A, 0x0A];
      _appendLog('Raster payload: ${raster.length} bytes');
      await PrinterService.instance
          .printRawBytes(Uint8List.fromList(out), slow: true);
      _appendLog('Sent ${out.length} bytes.');
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _guard(String name, Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _log = 'Running $name…';
    });
    try {
      await body();
      _appendLog('✅ $name done. Inspect printer output.');
    } catch (e) {
      _appendLog('❌ $name failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendLog(String s) {
    if (mounted) setState(() => _log = '$_log\n$s');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marathi Print Test'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _controls(theme),
                const SizedBox(height: 12),
                _strategyButtons(),
                const SizedBox(height: 12),
                _logPanel(theme),
                const SizedBox(height: 12),
                _preview(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('Paper: '),
                ChoiceChip(
                  label: const Text('58mm'),
                  selected: !_has80,
                  onSelected: (_) =>
                      setState(() => _widthDots = DevanagariRaster.dots58mm),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('80mm'),
                  selected: _has80,
                  onSelected: (_) =>
                      setState(() => _widthDots = DevanagariRaster.dots80mm),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Floyd–Steinberg dither'),
              subtitle: const Text('Off = crisp threshold (better for text)'),
              value: _dither,
              onChanged: (v) => setState(() => _dither = v),
            ),
            Text('Font size: ${_fontSize.toStringAsFixed(0)}'),
            Slider(
              min: 18,
              max: 48,
              divisions: 30,
              value: _fontSize,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (v) => setState(() => _fontSize = v),
            ),
            Text('Supersample scale: ${_scale.toStringAsFixed(1)}x'),
            Slider(
              min: 1,
              max: 4,
              divisions: 6,
              value: _scale,
              label: '${_scale.toStringAsFixed(1)}x',
              onChanged: (v) => setState(() => _scale = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strategyButtons() {
    return Column(
      children: [
        _btn('Strategy F — GS v 0 banded ★ (best)', Colors.green,
            _busy ? null : () => _printFastSingleRaster(RasterMode.gsV0),
            sub: 'Correct crisp glyphs, sliced into bands for smooth feed'),
        _btn('Strategy F2 — ESC * strip (broken here)', Colors.grey,
            _busy ? null : () => _printFastSingleRaster(RasterMode.escStar),
            sub: 'Misaligns on this printer — kept for reference only'),
        _btn('Strategy A — Native UTF-8 text (control)', Colors.orange,
            _busy ? null : _printNativeText,
            sub: 'Sends UTF-8 as-is — garbage (proves no Devanagari ROM)'),
        _btn('Strategy B1 — ISCII raw (control)', Colors.grey,
            _busy ? null : _printIsciiRaw,
            sub: 'Will also fail — printer ROM is GBK, not ISCII'),
        _btn('Strategy B2 — ISCII ESC t page sweep (control)', Colors.grey,
            _busy ? null : _printIsciiPageSweep,
            sub: 'Sweep for completeness — expected to fail on GBK ROM'),
        _btn('Strategy B3 — FS & + ISCII (control)', Colors.grey,
            _busy ? null : _printIsciiFsAmp,
            sub: 'Multibyte wrapper — expected to fail'),
        _btn('Strategy D — Per-line bitmap (slow comparison)', Colors.blueGrey,
            _busy ? null : _printBitmapPerLine,
            sub: 'Old slow approach — to feel the speed difference'),
        _btn('Strategy E — Whole receipt as one image', Colors.blue,
            _busy ? null : _printWholeImage,
            sub: 'RepaintBoundary → PNG → raster'),
      ],
    );
  }

  Widget _btn(String label, Color color, VoidCallback? onTap, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: onTap == null ? Colors.grey.shade300 : color.withValues(alpha: 0.12),
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
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sub != null)
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

  Widget _logPanel(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _log,
        style: const TextStyle(
            color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  /// On-screen preview of what the bitmap will look like, PLUS the offscreen
  /// RepaintBoundary used for Strategy E.
  Widget _preview(ThemeData theme) {
    // Scale physical dots → logical preview width.
    final previewW = _has80 ? 320.0 : 220.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Screen preview (shaping check)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Center(
          child: RepaintBoundary(
            key: _receiptKey,
            child: Container(
              width: previewW,
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  const Text('--- RECEIPT PREVIEW ---',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (final c in _cases)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        c,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontFamily: DevanagariRaster.primaryFontFamily,
                          fontSize: _fontSize * 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
