import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/models.dart';
import '../services/printer_service.dart';
import '../services/receipt_image_builder.dart';
import '../services/receipt_labels.dart';
import '../theme/app_theme.dart';
import '../widgets/shell_app_bar.dart';

/// Developer page: prints the SAME dummy Marathi bill using several different
/// rendering / ESC-POS strategies so you can see on the real printer which one
/// produces readable Devanagari. Each card shows an on-screen preview and a
/// "Print" button. The winning approach can then replace the default in
/// [ReceiptImageBuilder.build].
class MarathiPrintTestScreen extends StatefulWidget {
  const MarathiPrintTestScreen({super.key});

  @override
  State<MarathiPrintTestScreen> createState() => _MarathiPrintTestScreenState();
}

class _MarathiPrintTestScreenState extends State<MarathiPrintTestScreen> {
  String? _status;
  bool _busy = false;

  // A dummy Marathi bill built in-page so the test needs no real data.
  late final Bill _bill = _dummyBill();
  late final ReceiptLabels _labels = _marathiLabels();

  // Each approach: label, description, rendering knobs, and the ESC/POS send
  // mode. Ordered simplest → most aggressive. The same knobs drive both the
  // on-screen preview and the printed bytes, so what you see is what prints.
  // Your diagnosis: previews render perfectly + English prints fine, but the
  // raster comes out faint/squished. That's a TRANSMISSION problem, not a
  // rendering one. So the top approaches use ESC * band mode (the reliable path
  // for cheap 58mm BT printers) and slow chunking. The old GS v 0 variants are
  // kept lower down for comparison.
  late final List<_Approach> _approaches = [
    _Approach('1. ESC * bands (RECOMMENDED)',
        'ESC * 33 24-dot bands, sent slowly. Best path for 58mm BT printers.',
        threshold: 150, mode: _SendMode.escStar, slowSend: true),
    _Approach('2. ESC * bands + bold',
        'Same band method, heavier strokes.',
        threshold: 140, bold: true, mode: _SendMode.escStar, slowSend: true),
    _Approach('3. ESC * bands + 2x supersample',
        'Crisper glyphs, band transmission, slow send.',
        threshold: 150, scale: 2, mode: _SendMode.escStar, slowSend: true),
    _Approach('4. ESC * bands + bold + larger',
        'Boldest/biggest via band mode — for very faint heads.',
        threshold: 130, bold: true, fontScale: 1.2, mode: _SendMode.escStar,
        slowSend: true),
    _Approach('5. ESC * SINGLE density (8-dot)',
        'For printers that don\'t support 24-dot mode. Try if 1–4 squish.',
        threshold: 150, bold: true, mode: _SendMode.escStarSingle,
        slowSend: true),
    _Approach('6. GS v 0 raster + slow send',
        'Original raster but chunked slowly (rules out buffer overrun).',
        threshold: 150, slowSend: true),
    _Approach('7. GS v 0 (current default)',
        'Today\'s default — for comparison.',
        threshold: 160),
    _Approach('8. GS ( L graphics fn',
        'Bitmap via the graphics command.',
        threshold: 140, bold: true, mode: _SendMode.graphics),
    _Approach('9. GS * image() single density',
        'Non-double-density bit-image (old firmware).',
        threshold: 140, mode: _SendMode.bitImage),
    _Approach('10. Floyd–Steinberg dither (ESC *)',
        'Error-diffusion + band mode.',
        dither: true, mode: _SendMode.escStar, slowSend: true),
  ];

  // Cache of rendered previews for on-screen display.
  final Map<int, Uint8List> _previews = {};

  @override
  void initState() {
    super.initState();
    _renderPreviews();
  }

  Future<void> _renderPreviews() async {
    for (int i = 0; i < _approaches.length; i++) {
      try {
        final png = await _previewPng(_approaches[i]);
        if (!mounted) return;
        setState(() => _previews[i] = png);
      } catch (_) {}
    }
  }

  // --- rendering ------------------------------------------------------------

  // Render the receipt bitmap using an approach's knobs. Shared by preview and
  // print so what you see on screen is exactly what gets sent.
  Future<img.Image> _renderFor(_Approach a) => ReceiptImageBuilder.renderBitmap(
        _bill,
        _labels,
        businessName: 'माझे दुकान',
        threshold: a.threshold,
        scale: a.scale,
        boldBoost: a.bold,
        fontScale: a.fontScale,
        dither: a.dither,
      );

  // Build the ESC/POS byte stream for an approach using its chosen send mode.
  Future<List<int>> _bytesFor(_Approach a) async {
    final bitmap = await _renderFor(a);

    // ESC * band mode bypasses the esc_pos Generator entirely — it's the most
    // compatible path for cheap 58mm BT printers that squish GS v 0 rasters.
    if (a.mode == _SendMode.escStar || a.mode == _SendMode.escStarSingle) {
      final bytes = <int>[
        0x1B, 0x40, // ESC @  reset
        0x1B, 0x61, 0x01, // ESC a 1  centre
      ];
      bytes.addAll(ReceiptImageBuilder.escStarBitImage(bitmap,
          doubleDensity: a.mode == _SendMode.escStar));
      bytes.addAll([0x0A, 0x0A]); // feed to tear
      return bytes;
    }

    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    switch (a.mode) {
      case _SendMode.raster:
        bytes.addAll(gen.imageRaster(bitmap));
        break;
      case _SendMode.graphics:
        bytes.addAll(gen.imageRaster(bitmap, imageFn: PosImageFn.graphics));
        break;
      case _SendMode.bitImage:
        bytes.addAll(gen.image(bitmap, isDoubleDensity: false));
        break;
      case _SendMode.escStar:
      case _SendMode.escStarSingle:
        break; // handled above
    }
    bytes.addAll(gen.feed(3));
    return bytes;
  }

  Future<Uint8List> _previewPng(_Approach a) async {
    final bitmap = await _renderFor(a);
    return Uint8List.fromList(img.encodePng(bitmap));
  }

  // --- printing -------------------------------------------------------------

  Future<void> _print(_Approach a) async {
    setState(() {
      _busy = true;
      _status = 'Building "${a.title}"…';
    });
    try {
      final bytes = await _bytesFor(a);
      setState(() => _status = 'Sending ${bytes.length} bytes…');
      await PrinterService.instance.printRawBytes(bytes, slow: a.slowSend);
      if (mounted) setState(() => _status = '✓ Printed "${a.title}"');
    } on PrinterException catch (e) {
      if (mounted) setState(() => _status = '✗ ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _status = '✗ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ShellAppBar(title: Text('Marathi Print Test')),
          if (_status != null)
            Container(
              width: double.infinity,
              color: AppColors.surfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(_status!,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _approaches.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  i == 0 ? _diagnosticsCard() : _card(i - 1),
            ),
          ),
        ],
      ),
    );
  }

  // Two probes to isolate the failure before comparing Marathi strategies:
  //  • Solid box (ESC *): does the printer render ANY raster solidly?
  //  • Plain text: baseline that we KNOW works, for reference.
  Widget _diagnosticsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.warning),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Diagnostics — run these first',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Solid box tests if the printer renders raster at all. If the box is '
            'also faint/broken, the head is too weak for images and we should '
            'switch Marathi to transliteration instead.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _printSolidBox,
                  icon: const Icon(Icons.crop_square, size: 18),
                  label: const Text('Solid box'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _printPlainText,
                  icon: const Icon(Icons.text_fields, size: 18),
                  label: const Text('Plain text'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _printSolidBox() async {
    setState(() {
      _busy = true;
      _status = 'Printing solid box…';
    });
    try {
      // A short 40-dot solid black block, full 384-dot width, via ESC * bands.
      final box = img.Image(width: 384, height: 40);
      img.fill(box, color: img.ColorRgb8(0, 0, 0));
      final bytes = <int>[0x1B, 0x40, 0x1B, 0x61, 0x01];
      bytes.addAll(ReceiptImageBuilder.escStarBitImage(box));
      bytes.addAll([0x0A, 0x0A]);
      await PrinterService.instance.printRawBytes(bytes, slow: true);
      if (mounted) setState(() => _status = '✓ Solid box sent');
    } catch (e) {
      if (mounted) setState(() => _status = '✗ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printPlainText() async {
    setState(() {
      _busy = true;
      _status = 'Printing plain text…';
    });
    try {
      final lines = [
        '     PLAIN TEXT TEST',
        '--------------------------------',
        'If you can read this, text',
        'printing works. (ASCII only)',
        '--------------------------------',
      ];
      final bytes = <int>[0x1B, 0x40];
      for (final l in lines) {
        for (final c in l.codeUnits) {
          bytes.add(c > 127 ? 63 : c);
        }
        bytes.add(0x0A);
      }
      bytes.addAll([0x0A, 0x0A]);
      await PrinterService.instance.printRawBytes(bytes);
      if (mounted) setState(() => _status = '✓ Plain text sent');
    } catch (e) {
      if (mounted) setState(() => _status = '✗ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(int i) {
    final a = _approaches[i];
    final preview = _previews[i];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview thumbnail (white bill on light bg).
          Container(
            width: 96,
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.hardEdge,
            child: preview == null
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Image.memory(preview, fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(a.description,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _print(a),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print this'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- dummy data -----------------------------------------------------------

  static Bill _dummyBill() {
    // Kept intentionally minimal to save paper: header + one Devanagari item +
    // total is enough to judge legibility. No customer / tax / discount rows.
    final now = DateTime.now();
    return Bill(
      id: 'test',
      businessId: 'test',
      billNumber: 'INV-0001',
      subtotal: 175,
      taxAmount: 0,
      discountAmount: 0,
      total: 175,
      paymentMode: 'cash',
      status: 'finalized',
      createdByUserId: 'test',
      createdAt: now,
      items: [
        BillItem(
          id: '1',
          billId: 'test',
          itemName: 'साखर',
          quantity: 3.5,
          unitPrice: 50,
          lineTotal: 175,
        ),
      ],
    );
  }

  static ReceiptLabels _marathiLabels() => const ReceiptLabels(
        languageCode: 'mr',
        defaultBusiness: 'माझे दुकान',
        phonePrefix: 'फोन:',
        billNo: 'बिल क्र.:',
        date: 'दिनांक:',
        customer: 'ग्राहक:',
        customerPhone: 'फोन:',
        colItem: 'वस्तू',
        colQty: 'नग',
        colPrice: 'दर',
        colTotal: 'एकूण',
        subtotal: 'उपएकूण:',
        tax: 'कर:',
        discount: 'सूट:',
        total: 'एकूण:',
        payment: 'पेमेंट:',
        thankYou: 'धन्यवाद, पुन्हा भेट द्या!',
      );
}

/// How the rendered bitmap is wrapped into ESC/POS bytes.
enum _SendMode { raster, graphics, bitImage, escStar, escStarSingle }

/// One test strategy: rendering knobs + ESC/POS send mode. The same knobs drive
/// both the on-screen preview and the printed bytes.
class _Approach {
  final String title;
  final String description;
  final int threshold;
  final int scale;
  final bool bold;
  final double fontScale;
  final bool dither;
  final _SendMode mode;
  final bool slowSend;

  _Approach(
    this.title,
    this.description, {
    this.threshold = 160,
    this.scale = 1,
    this.bold = false,
    this.fontScale = 1.0,
    this.dither = false,
    this.mode = _SendMode.raster,
    this.slowSend = false,
  });
}
