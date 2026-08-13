import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Staged, independently-testable ESC/POS raster pipeline for the Shreyans
/// PSF-80B (576-dot 80mm clone, no Indic ROM). Each stage is isolated so a
/// failure localizes to one place rather than the whole pipeline.
///
/// Coordinate/packing rules (shared by all stages):
///  - Width is ALWAYS padded to a multiple of 8 before packing. ESC/POS packs
///    8 horizontal dots per byte; a non-multiple-of-8 width makes the row stride
///    and the GS v 0 xL/xH disagree → diagonal shear. This is the #1 clone bug.
///  - GS v 0 header: 1D 76 30 m xL xH yL yH, m=0 (normal),
///    xL/xH = bytesPerRow little-endian, yL/yH = height little-endian.
///  - Dark pixel (luminance < threshold) => printed dot (bit=1).
/// Demo languages — each script uses its OWN bundled Noto font to prove the
/// raster pipeline is script-agnostic (not just Devanagari).
enum DemoLang {
  marathi('Marathi', 'NotoSansDevanagari'),
  tamil('Tamil', 'NotoSansTamil'),
  gujarati('Gujarati', 'NotoSansGujarati');

  const DemoLang(this.label, this.font);
  final String label;
  final String font;
}

class RasterLab {
  static const int dots80mm = 576; // 80mm @ 203dpi
  static const int dots58mm = 384;

  /// Bundled Devanagari font (see pubspec fonts:). NOT the system font.
  static const String devanagariFont = 'NotoSansDevanagari';

  // ───────────────────────────────────────────────────────────────────────
  // Core packing — the one place width/byte math lives. Every stage uses this.
  // ───────────────────────────────────────────────────────────────────────

  /// Pack a [ui.Image] into 1-bit rows. Returns (packed, bytesPerRow, height).
  /// The image width MUST already be a multiple of 8 (callers guarantee this).
  static Future<_Packed> _pack(ui.Image image, {int threshold = 128}) async {
    final w = image.width;
    final h = image.height;
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) throw StateError('image.toByteData returned null');
    final rgba = bd.buffer.asUint8List();

    final bytesPerRow = (w + 7) >> 3;
    // If width isn't a multiple of 8 the pack is still correct (pad bits are 0),
    // but callers should pad the CANVAS so xL/xH matches the visible content.
    final packed = Uint8List(bytesPerRow * h);

    for (var y = 0; y < h; y++) {
      final rowBit = y * bytesPerRow;
      final rowPix = y * w * 4;
      for (var x = 0; x < w; x++) {
        final o = rowPix + x * 4;
        final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2], a = rgba[o + 3];
        // composite over white, then luminance
        final inv = 255 - a;
        final rr = (r * a + 255 * inv) ~/ 255;
        final gg = (g * a + 255 * inv) ~/ 255;
        final bb = (b * a + 255 * inv) ~/ 255;
        final lum = (0.299 * rr + 0.587 * gg + 0.114 * bb).round();
        if (lum < threshold) {
          packed[rowBit + (x >> 3)] |= (0x80 >> (x & 7));
        }
      }
    }
    return _Packed(packed, bytesPerRow, h, w);
  }

  /// Emit banded GS v 0 commands from a packed buffer. [bandHeight] <= 0 => one
  /// block. Bands keep clone printers with small buffers from overrunning.
  static Uint8List _gsv0(_Packed p, {int bandHeight = 256}) {
    final xL = p.bytesPerRow & 0xFF;
    final xH = (p.bytesPerRow >> 8) & 0xFF;
    final out = BytesBuilder();
    final band = bandHeight <= 0 ? p.height : bandHeight;
    for (var y0 = 0; y0 < p.height; y0 += band) {
      final bh = (y0 + band > p.height) ? (p.height - y0) : band;
      out.add([0x1D, 0x76, 0x30, 0x00, xL, xH, bh & 0xFF, (bh >> 8) & 0xFF]);
      out.add(Uint8List.sublistView(
          p.bytes, y0 * p.bytesPerRow, (y0 + bh) * p.bytesPerRow));
    }
    return out.toBytes();
  }

  /// Render a widget-less paragraph OR a custom painter into an image whose
  /// width is padded to a multiple of 8. [paint] draws content in black on the
  /// already-white [canvas] of size (paddedWidth x height).
  static Future<ui.Image> _renderPadded({
    required int targetWidth,
    required int height,
    required void Function(Canvas canvas, int paddedWidth) paint,
  }) async {
    final paddedWidth = (targetWidth + 7) & ~7;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, paddedWidth.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    paint(canvas, paddedWidth);
    final pic = rec.endRecording();
    final img = await pic.toImage(paddedWidth, height);
    pic.dispose();
    return img;
  }

  // ───────────────────────────────────────────────────────────────────────
  // STAGE 1 — Prove raw raster + packing math. English text + checkerboard.
  // No fonts-with-scripts, no Devanagari. If the checkerboard is skewed, the
  // bug is 100% in packing/width math.
  // ───────────────────────────────────────────────────────────────────────

  static Future<Uint8List> stage1Checkerboard({int width = dots80mm}) async {
    const cell = 8; // 8x8 dot blocks
    const rows = 16; // checkerboard height = 128 dots
    final labelImg = await _textImage(
      'STAGE 1: RASTER + PACKING',
      width: width,
      fontSize: 22,
      fontFamily: null, // default/ASCII font is fine here
    );
    final checkerImg = await _renderPadded(
      targetWidth: width,
      height: cell * rows,
      paint: (canvas, paddedWidth) {
        final black = Paint()..color = const Color(0xFF000000);
        final cols = (paddedWidth / cell).ceil();
        for (var gy = 0; gy < rows; gy++) {
          for (var gx = 0; gx < cols; gx++) {
            if ((gx + gy).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(
                    (gx * cell).toDouble(), (gy * cell).toDouble(), cell.toDouble(), cell.toDouble()),
                black,
              );
            }
          }
        }
      },
    );

    final out = BytesBuilder();
    out.add(await _imageToGsv0(labelImg));
    out.add([0x0A]);
    out.add(await _imageToGsv0(checkerImg));
    out.add(_feed(4));
    labelImg.dispose();
    checkerImg.dispose();
    return out.toBytes();
  }

  // ───────────────────────────────────────────────────────────────────────
  // STAGE 3 — Single word (कॉफी) → raster. Returns BOTH the print bytes and the
  // exact 1-bit bitmap re-encoded as a PNG for visual inspection.
  // (Stage 2 is on-screen only — handled in the screen, no service needed.)
  // ───────────────────────────────────────────────────────────────────────

  static Future<RasterResult> stage3SingleWord(
    String word, {
    int width = dots80mm,
    double fontSize = 40,
    int threshold = 128,
  }) async {
    final img = await _textImage(word,
        width: width, fontSize: fontSize, fontFamily: devanagariFont);
    final packed = await _pack(img, threshold: threshold);

    final label = await _textImage('STAGE 3: $word',
        width: width, fontSize: 20, fontFamily: devanagariFont);

    final out = BytesBuilder();
    out.add(await _imageToGsv0(label, threshold: threshold));
    out.add([0x0A]);
    out.add(_gsv0(packed));
    out.add(_feed(4));

    // Re-encode the EXACT packed bits as a PNG so we inspect what goes to the
    // printer (not the pre-threshold anti-aliased image).
    final png = await _packedToPng(packed);

    img.dispose();
    label.dispose();
    return RasterResult(
      bytes: out.toBytes(),
      previewPng: png,
      width: packed.width,
      bytesPerRow: packed.bytesPerRow,
      height: packed.height,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // STAGE 4 — Full case list, ONE continuous bitmap (single paragraph capture),
  // packed once, banded.
  // ───────────────────────────────────────────────────────────────────────

  static Future<RasterResult> stage4AllLines(
    List<String> lines, {
    int width = dots80mm,
    double fontSize = 30,
    int threshold = 128,
    int bandHeight = 256,
  }) async {
    // One paragraph, one image — never per-word.
    final img = await _textImage(
      lines.join('\n'),
      width: width,
      fontSize: fontSize,
      fontFamily: devanagariFont,
    );
    final packed = await _pack(img, threshold: threshold);
    final out = BytesBuilder();
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    final png = await _packedToPng(packed);
    img.dispose();
    return RasterResult(
      bytes: out.toBytes(),
      previewPng: png,
      width: packed.width,
      bytesPerRow: packed.bytesPerRow,
      height: packed.height,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // DEMO BILL — a realistic receipt rendered as ONE raster (header centered,
  // item rows with name left + amount right, totals, footer). Proves the real
  // printBill layout before wiring it in.
  // ───────────────────────────────────────────────────────────────────────

  /// Demo bill in one of several Indian scripts, to prove the raster pipeline
  /// is script-agnostic. Each script uses its OWN bundled Noto font.
  static Future<RasterResult> demoBill({
    DemoLang lang = DemoLang.marathi,
    int width = dots80mm,
    int threshold = 128,
    int bandHeight = 256,
  }) async {
    final rows = _demoRows(lang);
    final img = await _renderReceipt(rows, width: width, font: lang.font);
    final packed = await _pack(img, threshold: threshold);
    final out = BytesBuilder();
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    final png = await _packedToPng(packed);
    img.dispose();
    return RasterResult(
      bytes: out.toBytes(),
      previewPng: png,
      width: packed.width,
      bytesPerRow: packed.bytesPerRow,
      height: packed.height,
    );
  }

  /// Render structured receipt [rows] (center / rule / multi-column) into ONE
  /// raster with TRUE table alignment — each column occupies a fixed fraction of
  /// the width, so proportional Devanagari/Tamil/Gujarati glyphs stay aligned
  /// (unlike space-padded monospace lines, which overflow and wrap). This is the
  /// path the real printBill uses for non-English receipts.
  static Future<Uint8List> rowsToReceiptRaster(
    List<ReceiptRow> rows, {
    int width = dots80mm,
    double fontSize = 24,
    int threshold = 128,
    int bandHeight = 256,
    List<String> fonts = const [
      'monospace',
      'NotoSansDevanagari',
      'NotoSansTamil',
      'NotoSansGujarati',
    ],
  }) async {
    final img = await _renderRows(rows, width: width, baseSize: fontSize, fonts: fonts);
    final packed = await _pack(img, threshold: threshold);
    final out = BytesBuilder();
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    img.dispose();
    return out.toBytes();
  }

  /// Render the SAME structured [rows] as [rowsToReceiptRaster] but return a
  /// crisp, anti-aliased PNG for on-screen preview instead of an ESC/POS payload.
  ///
  /// Unlike the print path we deliberately DO NOT run the 1-bit [_pack] threshold
  /// here — that hard black/white quantization is what the physical printer head
  /// needs, but on a phone screen it looks jagged/rough. The layout is identical
  /// (same [_renderRows], which already supersamples 2×); only the final image
  /// stays smooth. [scale] can render even larger for extra sharpness when the
  /// user zooms in.
  static Future<Uint8List> receiptPreviewPng(
    List<ReceiptRow> rows, {
    int width = dots80mm,
    double fontSize = 24,
    double scale = 1.0,
    List<String> fonts = const [
      'monospace',
      'NotoSansDevanagari',
      'NotoSansTamil',
      'NotoSansGujarati',
    ],
  }) async {
    final img = await _renderRows(rows,
        width: (width * scale).round(), baseSize: fontSize * scale, fonts: fonts);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return png!.buffer.asUint8List();
  }

  /// Render pre-formatted, monospace-aligned receipt [lines] (already padded
  /// with spaces for column alignment) into ONE raster. Used by the real
  /// printBill when any line contains non-ASCII (e.g. Marathi) so the printer
  /// can't render it as text. A monospaced fallback keeps the space-padding
  /// aligned; the script glyphs come from [fontFamilies] (tried in order).
  ///
  /// Returns the ESC/POS payload (banded GS v 0 + feed).
  static Future<Uint8List> linesToReceiptRaster(
    List<String> lines, {
    int width = dots80mm,
    double fontSize = 24,
    int threshold = 128,
    int bandHeight = 256,
    List<String> fontFamilies = const [
      'monospace',
      'NotoSansDevanagari',
      'NotoSansTamil',
      'NotoSansGujarati',
    ],
  }) async {
    final img = await _monoLinesImage(lines,
        width: width, fontSize: fontSize, fontFamilies: fontFamilies);
    final packed = await _pack(img, threshold: threshold);
    final out = BytesBuilder();
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    img.dispose();
    return out.toBytes();
  }

  /// Render left-aligned monospace lines (one paragraph) to a padded-width image.
  static Future<ui.Image> _monoLinesImage(
    List<String> lines, {
    required int width,
    required double fontSize,
    required List<String> fontFamilies,
  }) async {
    const ss = 2.0;
    final renderW = (width * ss).round();
    const padX = 8.0 * ss;

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      // A monospace primary keeps the space-padded columns aligned; the script
      // fonts are fallbacks that supply Devanagari/Tamil/Gujarati glyphs.
      fontFamily: fontFamilies.first,
      fontSize: fontSize * ss,
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFF000000),
        fontFamily: fontFamilies.first,
        fontFamilyFallback: fontFamilies.skip(1).toList(),
        fontSize: fontSize * ss,
        height: 1.25,
      ))
      ..addText(lines.join('\n'));
    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: renderW - padX * 2));
    final bigH = para.height.ceil().clamp(1, 60000);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, renderW.toDouble(), bigH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawParagraph(para, Offset(padX, 0));
    final bigImg = await rec.endRecording().toImage(renderW, bigH);

    final finalH = (bigH * width / renderW).round().clamp(1, 60000);
    final img = await _renderPadded(
      targetWidth: width,
      height: finalH,
      paint: (c, pw) {
        c.drawImageRect(
          bigImg,
          Rect.fromLTWH(0, 0, bigImg.width.toDouble(), bigImg.height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), finalH.toDouble()),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      },
    );
    bigImg.dispose();
    return img;
  }

  /// Render structured [rows] with true fractional-column alignment.
  static Future<ui.Image> _renderRows(
    List<ReceiptRow> rows, {
    required int width,
    required double baseSize,
    required List<String> fonts,
  }) async {
    const ss = 2.0;
    final renderW = (width * ss).round();
    const padX = 10.0 * ss;
    const gapY = 7.0 * ss;
    final contentW = renderW - padX * 2;

    ui.Paragraph mk(String text, double size, TextAlign align, bool bold,
        double maxW, {bool italic = false}) {
      final fontStyle = italic ? FontStyle.italic : FontStyle.normal;
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: align,
        fontFamily: fonts.first,
        fontSize: size * ss,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontStyle: fontStyle,
        // Allow long item names to wrap across several lines (instead of being
        // ellipsized) while staying inside their column. Short cells (qty,
        // price, total, headers) never reach this many lines anyway.
        maxLines: 6,
        ellipsis: '…',
      ))
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF000000),
          fontFamily: fonts.first,
          fontFamilyFallback: fonts.skip(1).toList(),
          fontSize: size * ss,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontStyle: fontStyle,
          height: 1.15,
        ))
        ..addText(text);
      return b.build()..layout(ui.ParagraphConstraints(width: maxW));
    }

    // Measure.
    final measured = <_MRow>[];
    double totalH = gapY;
    for (final r in rows) {
      if (r.isRule) {
        final hh = (r.bold ? 3.0 : 2.0) * ss;
        measured.add(_MRow.rule(hh));
        totalH += hh + gapY;
      } else if (r.isCenter) {
        final p = mk(r.cells.first.text, r.size, TextAlign.center, r.bold,
            contentW, italic: r.italic);
        measured.add(_MRow.center(p, p.height));
        totalH += p.height + gapY;
      } else {
        // Multi-column: each cell gets widthFraction*contentW.
        final ps = <ui.Paragraph>[];
        double maxH = 0;
        for (final c in r.cells) {
          final w = contentW * c.widthFraction;
          final p = mk(c.text, r.size, c.align, r.bold, w);
          ps.add(p);
          if (p.height > maxH) maxH = p.height;
        }
        measured.add(_MRow.cols(ps, r.cells, maxH));
        totalH += maxH + gapY;
      }
    }
    final bigH = totalH.ceil().clamp(1, 60000);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, renderW.toDouble(), bigH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF));
    double y = gapY;
    for (final m in measured) {
      if (m.isRule) {
        // Solid bold horizontal line (full width) — bolder than before.
        canvas.drawRect(
          Rect.fromLTWH(padX, y, contentW, m.height),
          Paint()..color = const Color(0xFF000000),
        );
        y += m.height + gapY;
      } else if (m.isCenter) {
        canvas.drawParagraph(m.paras.first, Offset(padX, y));
        y += m.height + gapY;
      } else {
        double x = padX;
        for (var i = 0; i < m.paras.length; i++) {
          final cell = m.cells![i];
          final w = contentW * cell.widthFraction;
          canvas.drawParagraph(m.paras[i], Offset(x, y));
          x += w;
        }
        y += m.height + gapY;
      }
    }
    final bigImg = await rec.endRecording().toImage(renderW, bigH);

    final finalH = (bigH * width / renderW).round().clamp(1, 60000);
    final img = await _renderPadded(
      targetWidth: width,
      height: finalH,
      paint: (c, pw) {
        c.drawImageRect(
          bigImg,
          Rect.fromLTWH(0, 0, bigImg.width.toDouble(), bigImg.height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), finalH.toDouble()),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      },
    );
    bigImg.dispose();
    return img;
  }

  /// Localized demo-receipt rows per script. English digits/Rs. are kept as-is
  /// (the fonts render Latin too), so only the labels change per language.
  static List<_Row> _demoRows(DemoLang lang) {
    switch (lang) {
      case DemoLang.marathi:
        return <_Row>[
          _Row.center('कॅफे रसीद', size: 40, bold: true),
          _Row.center('Vittam Demo Cafe', size: 24),
          _Row.rule(),
          _Row.lr('बिल#: INV-0021', 'रोख', size: 24),
          _Row.lr('वस्तू', 'रक्कम', size: 24, bold: true),
          _Row.rule(),
          _Row.lr('कॉफी x2', 'Rs.100.00', size: 24),
          _Row.lr('वडा पाव x3', 'Rs.90.00', size: 24),
          _Row.lr('सँडविच x1', 'Rs.60.00', size: 24),
          _Row.rule(),
          _Row.lr('एकूण', 'Rs.250.00', size: 30, bold: true),
          _Row.rule(),
          _Row.center('धन्यवाद! पुन्हा भेटू.', size: 26),
        ];
      case DemoLang.tamil:
        return <_Row>[
          _Row.center('ரசீது', size: 40, bold: true),
          _Row.center('Vittam Demo Cafe', size: 24),
          _Row.rule(),
          _Row.lr('பில்#: INV-0021', 'ரொக்கம்', size: 24),
          _Row.lr('பொருள்', 'தொகை', size: 24, bold: true),
          _Row.rule(),
          _Row.lr('காபி x2', 'Rs.100.00', size: 24),
          _Row.lr('தேநீர் x1', 'Rs.20.00', size: 24),
          _Row.lr('சாண்ட்விச் x1', 'Rs.60.00', size: 24),
          _Row.rule(),
          _Row.lr('மொத்தம்', 'Rs.180.00', size: 30, bold: true),
          _Row.rule(),
          _Row.center('நன்றி! மீண்டும் வாருங்கள்.', size: 24),
        ];
      case DemoLang.gujarati:
        return <_Row>[
          _Row.center('રસીદ', size: 40, bold: true),
          _Row.center('Vittam Demo Cafe', size: 24),
          _Row.rule(),
          _Row.lr('બિલ#: INV-0021', 'રોકડ', size: 24),
          _Row.lr('વસ્તુ', 'રકમ', size: 24, bold: true),
          _Row.rule(),
          _Row.lr('કોફી x2', 'Rs.100.00', size: 24),
          _Row.lr('ચા x1', 'Rs.20.00', size: 24),
          _Row.lr('સેન્ડવિચ x1', 'Rs.60.00', size: 24),
          _Row.rule(),
          _Row.lr('કુલ', 'Rs.180.00', size: 30, bold: true),
          _Row.rule(),
          _Row.center('આભાર! ફરી મળીશું.', size: 26),
        ];
    }
  }

  /// Render a list of receipt rows into one padded-width image, supersampled
  /// then downscaled. Each row is measured for height and laid out top-to-bottom.
  static Future<ui.Image> _renderReceipt(List<_Row> rows,
      {required int width, required String font}) async {
    const ss = 2.0; // supersample
    final renderW = (width * ss).round();
    const padX = 12.0 * ss;
    const gapY = 6.0 * ss;

    // Build a paragraph per row segment to measure heights.
    ui.Paragraph para(String text, double size, TextAlign align, bool bold,
        double maxW) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: align,
        fontFamily: font,
        fontSize: size * ss,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ))
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF000000),
          fontFamily: font,
          fontSize: size * ss,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1.2,
        ))
        ..addText(text);
      return b.build()..layout(ui.ParagraphConstraints(width: maxW));
    }

    // First pass: measure total height.
    final contentW = renderW - padX * 2;
    double totalH = gapY;
    final measured = <_MeasuredRow>[];
    for (final r in rows) {
      if (r.isRule) {
        measured.add(_MeasuredRow.rule(2 * ss));
        totalH += 2 * ss + gapY;
        continue;
      }
      if (r.isCenter) {
        final p = para(r.left, r.size, TextAlign.center, r.bold, contentW);
        measured.add(_MeasuredRow.center(p, p.height));
        totalH += p.height + gapY;
      } else {
        // left + right: give each half the width, right-aligned on the right.
        final lp = para(r.left, r.size, TextAlign.left, r.bold, contentW * 0.62);
        final rp =
            para(r.right, r.size, TextAlign.right, r.bold, contentW * 0.38);
        final h = lp.height > rp.height ? lp.height : rp.height;
        measured.add(_MeasuredRow.lr(lp, rp, h));
        totalH += h + gapY;
      }
    }

    final bigH = totalH.ceil().clamp(1, 60000);

    // Draw supersampled.
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, renderW.toDouble(), bigH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF));
    double y = gapY;
    for (final m in measured) {
      if (m.isRule) {
        final dash = Paint()
          ..color = const Color(0xFF000000)
          ..strokeWidth = m.height;
        // dashed rule
        double x = padX;
        while (x < renderW - padX) {
          canvas.drawLine(Offset(x, y + m.height / 2),
              Offset(x + 8 * ss, y + m.height / 2), dash);
          x += 14 * ss;
        }
        y += m.height + gapY;
        continue;
      }
      if (m.isCenter) {
        canvas.drawParagraph(m.left!, Offset(padX, y));
      } else {
        canvas.drawParagraph(m.left!, Offset(padX, y));
        // right paragraph is right-aligned within its box on the right side.
        canvas.drawParagraph(m.right!, Offset(renderW - padX - contentW * 0.38, y));
      }
      y += m.height + gapY;
    }
    final bigImg = await rec.endRecording().toImage(renderW, bigH);

    // Downscale to padded printer width.
    final finalH = (bigH * width / renderW).round().clamp(1, 60000);
    final img = await _renderPadded(
      targetWidth: width,
      height: finalH,
      paint: (c, pw) {
        c.drawImageRect(
          bigImg,
          Rect.fromLTWH(0, 0, bigImg.width.toDouble(), bigImg.height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), finalH.toDouble()),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      },
    );
    bigImg.dispose();
    return img;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Shared rendering helpers
  // ───────────────────────────────────────────────────────────────────────

  /// Render [text] centered, supersampled 2x then downscaled to a padded
  /// (multiple-of-8) width. Downscale-before-threshold keeps thin strokes.
  static Future<ui.Image> _textImage(
    String text, {
    required int width,
    required double fontSize,
    required String? fontFamily,
  }) async {
    const supersample = 2.0;
    final renderW = (width * supersample).round();

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontFamily: fontFamily,
      fontSize: fontSize * supersample,
      fontWeight: FontWeight.w500,
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFF000000),
        fontFamily: fontFamily,
        fontSize: fontSize * supersample,
        height: 1.25,
      ))
      ..addText(text);
    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: renderW.toDouble()));
    final bigH = para.height.ceil().clamp(1, 40000);

    // Draw supersampled.
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, renderW.toDouble(), bigH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawParagraph(para, Offset.zero);
    final bigImg = await rec.endRecording().toImage(renderW, bigH);

    // Downscale to the target width; _renderPadded pads the canvas to ×8.
    final finalH = (bigH * width / renderW).round().clamp(1, 40000);
    final img = await _renderPadded(
      targetWidth: width,
      height: finalH,
      paint: (c, pw) {
        c.drawImageRect(
          bigImg,
          Rect.fromLTWH(0, 0, bigImg.width.toDouble(), bigImg.height.toDouble()),
          // Center content within padded width.
          Rect.fromLTWH(0, 0, width.toDouble(), finalH.toDouble()),
          Paint()
            ..filterQuality = FilterQuality.high
            ..isAntiAlias = true,
        );
      },
    );
    bigImg.dispose();
    return img;
  }

  static Future<Uint8List> _imageToGsv0(ui.Image img,
      {int threshold = 128, int bandHeight = 256}) async {
    final p = await _pack(img, threshold: threshold);
    return _gsv0(p, bandHeight: bandHeight);
  }

  /// Convert a packed 1-bit buffer back to a PNG (black dots on white) so we can
  /// inspect the EXACT bits headed to the printer.
  static Future<Uint8List> _packedToPng(_Packed p) async {
    final rgba = Uint8List(p.width * p.height * 4);
    for (var y = 0; y < p.height; y++) {
      for (var x = 0; x < p.width; x++) {
        final on =
            (p.bytes[y * p.bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) != 0;
        final o = (y * p.width + x) * 4;
        final v = on ? 0 : 255;
        rgba[o] = v;
        rgba[o + 1] = v;
        rgba[o + 2] = v;
        rgba[o + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      p.width,
      p.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final img = await completer.future;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return png!.buffer.asUint8List();
  }

  static List<int> _feed(int lines) => List<int>.filled(lines, 0x0A);

  /// Convert an arbitrary square [image] (e.g. a QR code) into a centred
  /// ESC/POS raster payload ready for the thermal printer. The image is scaled
  /// to [targetWidth] dots and centre-padded to the full [paperWidth] so it
  /// prints in the middle of the roll. Returns banded GS v 0 bytes + a feed.
  static Future<Uint8List> imageToReceiptRaster(
    ui.Image image, {
    int paperWidth = dots80mm,
    int targetWidth = 384,
    int threshold = 128,
    int bandHeight = 256,
  }) async {
    // Draw the (scaled) image centred on a white, full-paper-width canvas.
    final w = paperWidth;
    final scaled = targetWidth.clamp(64, paperWidth);
    final h = scaled; // square source assumed
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
    final dx = ((w - scaled) / 2).toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dx, 0, scaled.toDouble(), scaled.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final padded = await recorder.endRecording().toImage(w, h);

    final packed = await _pack(padded, threshold: threshold);
    final out = BytesBuilder();
    out.add([0x1B, 0x40]); // ESC @ — init
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    padded.dispose();
    return out.toBytes();
  }

  /// Convert a NON-square label [image] (e.g. a barcode label — wider than tall)
  /// into a centred ESC/POS raster payload. Unlike [imageToReceiptRaster] this
  /// preserves the image's aspect ratio, so a barcode's bars keep their true
  /// proportions instead of being squashed into a square. The image is scaled to
  /// [targetWidth] dots (e.g. 406 for a 2-inch label @ 203 dpi) and centre-padded
  /// to the full [paperWidth] so it prints in the middle of the roll.
  static Future<Uint8List> labelImageToRaster(
    ui.Image image, {
    int paperWidth = dots80mm,
    int targetWidth = 406, // 2 inch @ 203 dpi
    int threshold = 128,
    int bandHeight = 256,
  }) async {
    final w = paperWidth;
    final scaled = targetWidth.clamp(64, paperWidth);
    // Preserve aspect ratio: derive height from the source's proportions.
    final h = (scaled * image.height / image.width).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = Colors.white);
    final dx = ((w - scaled) / 2).toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dx, 0, scaled.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final padded = await recorder.endRecording().toImage(w, h);

    final packed = await _pack(padded, threshold: threshold);
    final out = BytesBuilder();
    out.add([0x1B, 0x40]); // ESC @ — init
    out.add(_gsv0(packed, bandHeight: bandHeight));
    out.add(_feed(4));
    padded.dispose();
    return out.toBytes();
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _Packed {
  final Uint8List bytes;
  final int bytesPerRow;
  final int height;
  final int width; // padded, multiple of 8
  _Packed(this.bytes, this.bytesPerRow, this.height, this.width);
}

class RasterResult {
  final Uint8List bytes; // ESC/POS payload to print
  final Uint8List previewPng; // exact 1-bit bitmap as PNG
  final int width;
  final int bytesPerRow;
  final int height;
  RasterResult({
    required this.bytes,
    required this.previewPng,
    required this.width,
    required this.bytesPerRow,
    required this.height,
  });
}

/// A logical receipt row: centered text, left/right columns, or a dashed rule.
class _Row {
  final String left;
  final String right;
  final double size;
  final bool bold;
  final bool isCenter;
  final bool isRule;
  const _Row._(
      {this.left = '',
      this.right = '',
      this.size = 24,
      this.bold = false,
      this.isCenter = false,
      this.isRule = false});
  factory _Row.center(String t, {double size = 24, bool bold = false}) =>
      _Row._(left: t, size: size, bold: bold, isCenter: true);
  factory _Row.lr(String l, String r, {double size = 24, bool bold = false}) =>
      _Row._(left: l, right: r, size: size, bold: bold);
  factory _Row.rule() => const _Row._(isRule: true);
}

class _MeasuredRow {
  final ui.Paragraph? left;
  final ui.Paragraph? right;
  final double height;
  final bool isCenter;
  final bool isRule;
  const _MeasuredRow._(
      {this.left,
      this.right,
      required this.height,
      this.isCenter = false,
      this.isRule = false});
  factory _MeasuredRow.center(ui.Paragraph p, double h) =>
      _MeasuredRow._(left: p, height: h, isCenter: true);
  factory _MeasuredRow.lr(ui.Paragraph l, ui.Paragraph r, double h) =>
      _MeasuredRow._(left: l, right: r, height: h);
  factory _MeasuredRow.rule(double h) =>
      _MeasuredRow._(height: h, isRule: true);
}

// ───────────────────────────────────────────────────────────────────────────
// Public structured-row model for rowsToReceiptRaster (real printBill).
// ───────────────────────────────────────────────────────────────────────────

/// One cell in a multi-column receipt row.
class ReceiptCell {
  final String text;
  final TextAlign align;
  final double widthFraction; // share of content width (cells should sum to 1)
  const ReceiptCell(this.text,
      {this.align = TextAlign.left, this.widthFraction = 1.0});
}

/// A receipt row: centered text, a dashed/solid rule, or fractional columns.
class ReceiptRow {
  final List<ReceiptCell> cells;
  final double size;
  final bool bold;
  final bool italic;
  final bool isCenter;
  final bool isRule;
  const ReceiptRow._(this.cells,
      {this.size = 24,
      this.bold = false,
      this.italic = false,
      this.isCenter = false,
      this.isRule = false});

  factory ReceiptRow.center(String t,
          {double size = 24, bool bold = false, bool italic = false}) =>
      ReceiptRow._([ReceiptCell(t, align: TextAlign.center)],
          size: size, bold: bold, italic: italic, isCenter: true);

  /// Bold rule = thicker line.
  factory ReceiptRow.rule({bool bold = false}) =>
      ReceiptRow._(const [], isRule: true, bold: bold);

  factory ReceiptRow.cols(List<ReceiptCell> cells,
          {double size = 24, bool bold = false}) =>
      ReceiptRow._(cells, size: size, bold: bold);
}

/// Measured multi-column row (internal to _renderRows).
class _MRow {
  final List<ui.Paragraph> paras;
  final List<ReceiptCell>? cells;
  final double height;
  final bool isCenter;
  final bool isRule;
  const _MRow._(this.paras, this.cells, this.height,
      {this.isCenter = false, this.isRule = false});
  factory _MRow.center(ui.Paragraph p, double h) =>
      _MRow._([p], null, h, isCenter: true);
  factory _MRow.cols(List<ui.Paragraph> ps, List<ReceiptCell> cells, double h) =>
      _MRow._(ps, cells, h);
  factory _MRow.rule(double h) => _MRow._(const [], null, h, isRule: true);
}

