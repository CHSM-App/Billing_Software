import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/models.dart';
import 'receipt_labels.dart';

/// Renders a receipt to ESC/POS raster bytes.
///
/// Thermal printers have no Devanagari code page, so Marathi text can't be sent
/// as characters — it comes out as `?`. Instead we paint the whole receipt with
/// Flutter's own text engine (which already has the Noto Sans Devanagari font
/// loaded via google_fonts), rasterise it to a 1-bit bitmap, and print that
/// image with the ESC/POS `GS v 0` raster command.
///
/// The output is a plain black-on-white monospace-style layout that mirrors the
/// plain-text receipt, so English and Marathi bills look consistent.
class ReceiptImageBuilder {
  // Dot width of the print head. 58mm heads are 384 dots; 80mm are 576.
  // Sending a 576-wide raster to a 384-dot head squishes/warps the output, so
  // this MUST match the actual paper. These handheld BT printers are 58mm.
  //
  // NOTE: the diagnostics width test measured 576 as the bar that spans the
  // paper with no wrap/margin, but bumping this constant to 576 changed
  // approach 9's output for the worse (it was already tuned/proven-good at
  // 384). Reverted — 384 stays the working value until the mismatch between
  // the width-test result and 9's actual behavior is understood.
  static const int _paperDots = 384;

  static const double _hPad = 6; // left/right margin in dots
  // Sizing tuned to mirror the printer's NATIVE text bill (English path): every
  // row occupies one uniform line of [_linePitch] dots — no per-row gaps, no
  // separate divider band — so Marathi prints as tight as the ASCII receipt.
  static const double _fontSize = 20; // header
  static const double _smallFont = 17; // body / items
  static const double _linePitch = 34; // fixed dots per row (≈ native line)
  // Strut line-height multiplier: generous by design so Devanagari matras and
  // shirorekha aren't clipped top/bottom, at the cost of extra vertical space
  // per row.
  static const double _lineHeight = 1.45;

  // Public aliases so callers (e.g. the test harness) can build overrides
  // relative to the current defaults without duplicating the numbers.
  static const double defaultFontSize = _fontSize;
  static const double defaultSmallFont = _smallFont;
  static const double defaultLinePitch = _linePitch;
  static const int defaultPaperDots = _paperDots;
  static const double defaultHPad = _hPad;
  static const double defaultLineHeight = _lineHeight;

  /// Builds the full ESC/POS byte stream for [bill].
  ///
  /// Verified on real 58mm handheld BT hardware: the single-block `GS v 0`
  /// raster comes out faint/squished, and 24-dot `ESC *` bands leave white
  /// stripes. **8-dot single-density `ESC *` bands with a bolded font** print
  /// clean, fully-legible Devanagari — so that is the production path. Callers
  /// should send these bytes with `slow: true` (small BT chunks) so the
  /// printer's buffer keeps up.
  ///
  /// Must run on the UI isolate — it uses `dart:ui` canvas APIs.
  static Future<List<int>> build(
    Bill bill,
    ReceiptLabels labels, {
    String? businessName,
    String? businessPhone,
    String? businessAddress,
  }) async {
    final image = await _paintReceipt(
      bill,
      labels,
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
      threshold: 170,
      scale: 3,
      boldBoost: true,
      fontScale: 1.15,
      // Slim edge margin to match the native English bill, which prints
      // essentially edge-to-edge. Was the default 6 dots.
      hPad: 2,
    );

    final bytes = <int>[
      0x1B, 0x40, // ESC @  reset
      0x1B, 0x61, 0x01, // ESC a 1  centre
    ];
    // 8-dot single-density bands — the format that prints cleanly here.
    bytes.addAll(escStarBitImage(image, doubleDensity: false));
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]); // feed to tear
    return bytes;
  }

  /// Renders just the receipt bitmap (no ESC/POS wrapping) with tunable knobs so
  /// a test harness can compare Marathi rendering strategies. Returns a 1-bit
  /// black/white [img.Image] at [_paperDots] wide.
  ///
  /// - [threshold]     luminance cut for black (lower = keeps thin strokes).
  /// - [scale]         supersample factor; painted at scale× then downsized.
  /// - [boldBoost]     add weight to every glyph (thin Devanagari matras survive).
  /// - [fontScale]     multiply all font sizes (bigger = more dots per glyph).
  /// - [dither]        Floyd–Steinberg instead of a hard threshold.
  static Future<img.Image> renderBitmap(
    Bill bill,
    ReceiptLabels labels, {
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    int threshold = 160,
    int scale = 1,
    bool boldBoost = false,
    double fontScale = 1.0,
    bool dither = false,
    String? fontFamilyOverride,
    double fontSizeOverride = _fontSize,
    double smallFontOverride = _smallFont,
    double linePitchOverride = _linePitch,
    FontWeight? boldTarget,
    double unsharpAmount = 0.0,
    bool adaptive = false,
    int paperDotsOverride = _paperDots,
    FontWeight boldWeight = FontWeight.w700,
    double hPadOverride = _hPad,
    double lineHeight = _lineHeight,
  }) {
    return _paintReceipt(
      bill,
      labels,
      businessName: businessName,
      businessPhone: businessPhone,
      businessAddress: businessAddress,
      threshold: threshold,
      scale: scale,
      boldBoost: boldBoost,
      fontScale: fontScale,
      dither: dither,
      fontFamilyOverride: fontFamilyOverride,
      fontSize: fontSizeOverride,
      smallFont: smallFontOverride,
      linePitch: linePitchOverride,
      boldTarget: boldTarget,
      unsharpAmount: unsharpAmount,
      adaptive: adaptive,
      paperDots: paperDotsOverride,
      hPad: hPadOverride,
      boldWeight: boldWeight,
      lineHeight: lineHeight,
    );
  }

  /// Encode a 1-bit [image] as **ESC \* 33** (24-dot double-density) bit-image
  /// bands — the most compatible raster method for cheap 58mm handheld BT
  /// printers, which often mis-handle the single-block GS v 0 raster.
  ///
  /// Each 24-pixel-tall band is emitted as `ESC * 33 nL nH <3 bytes/col>` then a
  /// line feed. Set the line spacing to 24 dots first (`ESC 3 24`) so bands butt
  /// together with no gaps, and restore default spacing at the end.
  /// [doubleDensity] true → mode 33 (24-dot, densest, default). false → mode 1
  /// (8-dot single density) for printers that don't support 24-dot mode.
  static List<int> escStarBitImage(img.Image image,
      {bool doubleDensity = true}) {
    final width = image.width;
    final height = image.height;
    final bytes = <int>[];

    final bandH = doubleDensity ? 24 : 8;
    final m = doubleDensity ? 33 : 1;
    final bytesPerCol = doubleDensity ? 3 : 1;

    // ESC 3 n — set line spacing to the band height so bands butt together.
    bytes.addAll([0x1B, 0x33, bandH]);

    final nL = width & 0xFF;
    final nH = (width >> 8) & 0xFF;

    for (int y = 0; y < height; y += bandH) {
      bytes.addAll([0x1B, 0x2A, m, nL, nH]);
      for (int x = 0; x < width; x++) {
        for (int k = 0; k < bytesPerCol; k++) {
          int b = 0;
          for (int bit = 0; bit < 8; bit++) {
            final py = y + k * 8 + bit;
            if (py < height) {
              final lum = image.getPixel(x, py).r;
              if (lum < 128) b |= (0x80 >> bit); // dark pixel → dot on
            }
          }
          bytes.add(b);
        }
      }
      bytes.add(0x0A); // advance to next band
    }

    // ESC 2 — restore default line spacing.
    bytes.addAll([0x1B, 0x32]);
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Painting
  // ---------------------------------------------------------------------------

  static Future<img.Image> _paintReceipt(
    Bill bill,
    ReceiptLabels labels, {
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    int threshold = 160,
    int scale = 1,
    bool boldBoost = false,
    double fontScale = 1.0,
    bool dither = false,
    String? fontFamilyOverride,
    double fontSize = _fontSize,
    double smallFont = _smallFont,
    double linePitch = _linePitch,
    FontWeight? boldTarget,
    double unsharpAmount = 0.0,
    bool adaptive = false,
    int paperDots = _paperDots,
    FontWeight boldWeight = FontWeight.w700,
    double hPad = _hPad,
    double lineHeight = _lineHeight,
  }) async {
    // First pass: lay out every paragraph to measure total height.
    final rows = _buildRows(bill, labels,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress,
        fontSize: fontSize,
        smallFont: smallFont,
        boldWeight: boldWeight);

    final s = scale.clamp(1, 4);
    final dotW = paperDots * s; // painting width (downsized to paperDots later)
    final contentWidth = dotW - hPad * s * 2;
    // Devanagari font family: caller override (e.g. Mangal) or the default.
    final family = fontFamilyOverride ?? _Row._family(labels.languageCode);

    final laid = <_LaidOut>[];
    final pitch = linePitch * s; // uniform dots per row
    // Small top leading so the head doesn't clip the first line.
    double y = (hPad + 2) * s;
    for (final row in rows) {
      if (row.kind == _RowKind.divider) {
        // Divider occupies exactly one line; the rule is centred in it.
        laid.add(_LaidOut(null, y, row));
        y += pitch;
        continue;
      }
      // Item rows are painted as aligned column paragraphs; everything else as
      // a single paragraph. Both advance by the SAME uniform line pitch, so the
      // receipt has the tight, even rhythm of the native ASCII bill.
      if (row.kind == _RowKind.itemRow) {
        final effSize = row.fontSize * fontScale * s;
        final effW = boldBoost && row.weight.index < FontWeight.w700.index
            ? (boldTarget ?? FontWeight.w700)
            : row.weight;
        final cols = row.buildItemColumns(
            contentWidth, family, effSize, effW, hPad * s,
            lineHeight: lineHeight);
        laid.add(_LaidOut(null, y, row, columns: cols));
        final colH = cols.fold<double>(
            0, (max, col) => math.max(max, col.paragraph.height));
        y += math.max(pitch, colH + 2 * s);
        continue;
      }
      final p = row.layout(contentWidth, labels.languageCode,
          boldBoost: boldBoost,
          fontScale: fontScale * s,
          familyOverride: fontFamilyOverride,
          boldTarget: boldTarget,
          lineHeight: lineHeight);
      laid.add(_LaidOut(p, y, row));
      // Advance by the measured paragraph height (never less than the pitch)
      // so tall Devanagari glyphs (matras, shirorekha) aren't clipped by the
      // next row.
      y += math.max(pitch, p.height + 2 * s);
    }
    final paintedHeight = (y + hPad * s).ceil();

    // Second pass: paint onto a white canvas.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, dotW.toDouble(), paintedHeight.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final rulePaint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = (2 * s).toDouble();
    // Small top inset so glyphs sit centred within the fixed line pitch.
    final textDy = 2.0 * s;
    for (final lo in laid) {
      if (lo.columns != null) {
        // Item row: each column paragraph is pre-positioned at its absolute x.
        for (final col in lo.columns!) {
          canvas.drawParagraph(col.paragraph, Offset(col.x, lo.y + textDy));
        }
      } else if (lo.paragraph == null) {
        // Centre the rule within the row's line height.
        final ry = lo.y + linePitch * s / 2;
        canvas.drawLine(
          Offset(hPad * s, ry),
          Offset(dotW - hPad * s, ry),
          rulePaint,
        );
      } else {
        canvas.drawParagraph(lo.paragraph!, Offset(hPad * s, lo.y + textDy));
      }
    }
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(dotW, paintedHeight);
    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    uiImage.dispose();

    // Build a grayscale image at painted size, downscale to head width if we
    // supersampled, then convert to 1-bit via threshold or dithering.
    final rgba = byteData!.buffer.asUint8List();
    var gray = img.Image(width: dotW, height: paintedHeight);
    for (int py = 0; py < paintedHeight; py++) {
      for (int px = 0; px < dotW; px++) {
        final i = (py * dotW + px) * 4;
        final lum =
            (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2])
                .round();
        gray.setPixelRgb(px, py, lum, lum, lum);
      }
    }
    if (s > 1) {
      gray = img.copyResize(gray,
          width: paperDots,
          interpolation: img.Interpolation.average);
    }
    if (unsharpAmount > 0) {
      // Simple unsharp mask: a 3x3 sharpen kernel mixed in by `amount`, which
      // pulls back thin strokes (matras) that supersample-downscaling blurs
      // away, without the heavier ringing of a full gaussian-based mask.
      gray = img.convolution(
        gray,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: unsharpAmount,
      );
    }

    final w = gray.width, h = gray.height;
    final out = img.Image(width: w, height: h);
    if (dither) {
      // Floyd–Steinberg error diffusion for smoother glyph edges.
      final err = List<double>.filled(w * h, 0);
      for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
          final p = gray.getPixel(px, py);
          final old = p.r.toDouble() + err[py * w + px];
          final nv = old < 128 ? 0 : 255;
          out.setPixelRgb(px, py, nv, nv, nv);
          final e = old - nv;
          if (px + 1 < w) err[py * w + px + 1] += e * 7 / 16;
          if (py + 1 < h) {
            if (px > 0) err[(py + 1) * w + px - 1] += e * 3 / 16;
            err[(py + 1) * w + px] += e * 5 / 16;
            if (px + 1 < w) err[(py + 1) * w + px + 1] += e * 1 / 16;
          }
        }
      }
    } else if (adaptive) {
      _sauvolaThreshold(gray, out);
    } else {
      for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
          final lum = gray.getPixel(px, py).r;
          final v = lum < threshold ? 0 : 255;
          out.setPixelRgb(px, py, v, v, v);
        }
      }
    }
    return out;
  }

  /// Sauvola local threshold (window ~15px, k≈0.3): the black cut at each
  /// pixel adapts to the local mean/stddev instead of one flat cut, so a
  /// heavy conjunct next to a thin matra doesn't force one or the other to
  /// blob out / drop out. Uses integral images so it stays O(w*h).
  static void _sauvolaThreshold(img.Image gray, img.Image out,
      {int window = 15, double k = 0.3}) {
    final w = gray.width, h = gray.height;
    final sum = List<double>.filled((w + 1) * (h + 1), 0);
    final sumSq = List<double>.filled((w + 1) * (h + 1), 0);
    for (int y = 0; y < h; y++) {
      double rowSum = 0, rowSumSq = 0;
      final rowBase = (y + 1) * (w + 1);
      final prevRowBase = y * (w + 1);
      for (int x = 0; x < w; x++) {
        final lum = gray.getPixel(x, y).r.toDouble();
        rowSum += lum;
        rowSumSq += lum * lum;
        sum[rowBase + x + 1] = sum[prevRowBase + x + 1] + rowSum;
        sumSq[rowBase + x + 1] = sumSq[prevRowBase + x + 1] + rowSumSq;
      }
    }
    double rectSum(List<double> integral, int x0, int y0, int x1, int y1) {
      final a = integral[y0 * (w + 1) + x0];
      final b = integral[y0 * (w + 1) + (x1 + 1)];
      final c = integral[(y1 + 1) * (w + 1) + x0];
      final d = integral[(y1 + 1) * (w + 1) + (x1 + 1)];
      return d - b - c + a;
    }

    final r = window ~/ 2;
    const dynamicRange = 128.0;
    for (int y = 0; y < h; y++) {
      final y0 = math.max(0, y - r);
      final y1 = math.min(h - 1, y + r);
      for (int x = 0; x < w; x++) {
        final x0 = math.max(0, x - r);
        final x1 = math.min(w - 1, x + r);
        final count = (x1 - x0 + 1) * (y1 - y0 + 1);
        final s = rectSum(sum, x0, y0, x1, y1);
        final sq = rectSum(sumSq, x0, y0, x1, y1);
        final mean = s / count;
        final variance = (sq / count) - (mean * mean);
        final stddev = variance > 0 ? math.sqrt(variance) : 0.0;
        final t = mean * (1 + k * (stddev / dynamicRange - 1));
        final lum = gray.getPixel(x, y).r;
        final v = lum < t ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Row model
  // ---------------------------------------------------------------------------

  static List<_Row> _buildRows(
    Bill bill,
    ReceiptLabels labels, {
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    double fontSize = _fontSize,
    double smallFont = _smallFont,
    FontWeight boldWeight = FontWeight.w700,
  }) {
    final rows = <_Row>[];

    // Header
    rows.add(_Row.centered(
        businessName ?? labels.defaultBusiness, fontSize, boldWeight));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      rows.add(_Row.centered(businessAddress, smallFont, FontWeight.w400));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      rows.add(_Row.centered(
          '${labels.phonePrefix} $businessPhone', smallFont, FontWeight.w400));
    }
    rows.add(_Row.divider(size: smallFont));

    // Bill info
    rows.add(_Row.leftKV(labels.billNo, bill.billNumber, smallFont));
    rows.add(_Row.leftKV(
        labels.date, _formatDate(bill.createdAt.toLocal()), smallFont));
    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      rows.add(_Row.left('${labels.customer} ${bill.customerName}', smallFont));
    }
    if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) {
      rows.add(_Row.leftKV(
          labels.customerPhone, bill.customerPhone!, smallFont));
    }
    rows.add(_Row.divider(size: smallFont));

    // Items header + rows (4 columns)
    rows.add(_Row.itemRow(
        labels.colItem, labels.colQty, labels.colPrice, labels.colTotal,
        bold: true, size: smallFont, weight: boldWeight));
    rows.add(_Row.divider(size: smallFont));
    for (final item in bill.items) {
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      rows.add(_Row.itemRow(
        item.itemName,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
        size: smallFont,
      ));
    }
    rows.add(_Row.divider(size: smallFont));

    // Totals
    if (bill.taxAmount > 0) {
      rows.add(_Row.twoCol(
          labels.subtotal, 'Rs.${bill.subtotal.toStringAsFixed(2)}',
          size: smallFont));
      rows.add(_Row.twoCol(
          labels.tax, 'Rs.${bill.taxAmount.toStringAsFixed(2)}',
          size: smallFont));
    }
    if (bill.discountAmount > 0) {
      rows.add(_Row.twoCol(
          labels.discount, 'Rs.${bill.discountAmount.toStringAsFixed(2)}',
          size: smallFont));
    }
    rows.add(_Row.twoCol(
        labels.total, 'Rs.${bill.total.toStringAsFixed(2)}',
        bold: true, size: smallFont, weight: boldWeight));
    rows.add(_Row.twoCol(labels.payment, bill.paymentMode.toUpperCase(),
        size: smallFont));
    rows.add(_Row.divider(size: smallFont));
    rows.add(_Row.centered(labels.thankYou, smallFont, FontWeight.w400));

    return rows;
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$d-${months[dt.month]}-${dt.year} $h:$mi $ampm';
  }
}

// ---------------------------------------------------------------------------
// Internal row types — each knows how to lay itself out into a ui.Paragraph.
// ---------------------------------------------------------------------------

enum _RowKind { centered, left, leftKV, twoCol, itemRow, divider }

class _Row {
  final _RowKind kind;
  final double fontSize;
  final FontWeight weight;
  final String a;
  final String b;
  final String c;
  final String d;

  _Row._(this.kind, this.fontSize, this.weight,
      {this.a = '', this.b = '', this.c = '', this.d = ''});

  factory _Row.centered(String text, double size, FontWeight w) =>
      _Row._(_RowKind.centered, size, w, a: text);
  factory _Row.left(String text, double size) =>
      _Row._(_RowKind.left, size, FontWeight.w400, a: text);
  /// Label in the Devanagari family, value (digits/ASCII) in the default font.
  factory _Row.leftKV(String label, String value, double size) =>
      _Row._(_RowKind.leftKV, size, FontWeight.w400, a: label, b: value);
  factory _Row.twoCol(String label, String value,
          {bool bold = false,
          double size = ReceiptImageBuilder._smallFont,
          FontWeight? weight}) =>
      _Row._(_RowKind.twoCol, size,
          weight ?? (bold ? FontWeight.w700 : FontWeight.w400),
          a: label, b: value);
  factory _Row.itemRow(String name, String qty, String price, String total,
          {bool bold = false,
          double size = ReceiptImageBuilder._smallFont,
          FontWeight? weight}) =>
      _Row._(_RowKind.itemRow, size,
          weight ?? (bold ? FontWeight.w700 : FontWeight.w400),
          a: name, b: qty, c: price, d: total);
  factory _Row.divider({double size = ReceiptImageBuilder._smallFont}) =>
      _Row._(_RowKind.divider, size, FontWeight.w400);

  /// Font family per locale — Devanagari for Marathi, monospace-ish for Latin.
  static String? _family(String lang) =>
      lang == 'mr' ? 'Noto Sans Devanagari' : null;

  static FontWeight _bump(FontWeight w, {FontWeight? target}) {
    if (target != null) return target;
    return w.index >= FontWeight.w700.index ? FontWeight.w900 : FontWeight.w700;
  }

  ui.Paragraph layout(double width, String lang,
      {bool boldBoost = false,
      double fontScale = 1.0,
      String? familyOverride,
      FontWeight? boldTarget,
      double lineHeight = 1.45}) {
    final family = familyOverride ?? _family(lang);
    final size = fontSize * fontScale;
    final w = boldBoost ? _bump(weight, target: boldTarget) : weight;
    switch (kind) {
      case _RowKind.divider:
        // Dividers are painted as a drawn line by the builder; this branch
        // isn't reached, but the switch must be exhaustive.
        return _simple('', size, FontWeight.w400, ui.TextAlign.left, width,
            family, lineHeight);
      case _RowKind.centered:
        return _simple(a, size, w, ui.TextAlign.center, width, family,
            lineHeight);
      case _RowKind.left:
        return _simple(a, size, w, ui.TextAlign.left, width, family,
            lineHeight);
      case _RowKind.leftKV:
        return _leftKV(a, b, width, family, size, w, lineHeight);
      case _RowKind.twoCol:
        return _twoColumns(a, b, width, family, size, w, lineHeight);
      case _RowKind.itemRow:
        return _fourColumns(a, b, c, d, width, family, size, w);
    }
  }

  ui.Paragraph _simple(String text, double size, FontWeight w,
      ui.TextAlign align, double width, String? family, double lineHeight) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      fontSize: size,
      fontWeight: w,
      fontFamily: family,
      maxLines: 2,
      ellipsis: '…',
      strutStyle: ui.StrutStyle(
        fontFamily: family,
        fontSize: size,
        height: lineHeight,
        forceStrutHeight: true,
      ),
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)))
      ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// Label left, value right-aligned, on one line. The value is almost always
  /// digits/currency/ASCII (amounts, "CASH"), so it's kept in the default font
  /// rather than the Devanagari family — Mangal/Noto render Latin digits with
  /// thinner, less legible strokes than the system default at this resolution.
  ui.Paragraph _twoColumns(String label, String value, double width,
      String? family, double size, FontWeight w, double lineHeight) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontWeight: w,
      maxLines: 1,
      ellipsis: '…',
      strutStyle: ui.StrutStyle(
        fontSize: size,
        height: lineHeight,
        forceStrutHeight: true,
      ),
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)));
    builder.pushStyle(ui.TextStyle(fontFamily: family));
    builder.addText(label);
    builder.pop();
    final gap = _computeGap(label, value, width, size, w, family);
    builder.addText(gap);
    builder.addText(value);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// Label + value on one line, left-aligned, no right-hand gap (e.g. "Bill
  /// No: INV-0001"). Value stays in the default font for the same reason as
  /// [_twoColumns].
  ui.Paragraph _leftKV(String label, String value, double width,
      String? family, double size, FontWeight w, double lineHeight) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontWeight: w,
      maxLines: 1,
      ellipsis: '…',
      strutStyle: ui.StrutStyle(
        fontSize: size,
        height: lineHeight,
        forceStrutHeight: true,
      ),
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)));
    builder.pushStyle(ui.TextStyle(fontFamily: family));
    builder.addText('$label ');
    builder.pop();
    builder.addText(value);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// Item(60%) Qty(10%) Price(15%) Total(15%) using space padding.
  ui.Paragraph _fourColumns(
      String name, String qty, String price, String total,
      double width, String? family, double size, FontWeight w) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontWeight: w,
      fontFamily: family,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)));

    final nameW = width * 0.52;
    final qtyW = width * 0.12;
    final priceW = width * 0.18;
    final line = _composeColumns(
      [name, qty, price, total],
      [nameW, qtyW, priceW, width - nameW - qtyW - priceW],
      size,
      w,
      family,
    );
    builder.addText(line);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  // --- spacing helpers (measure with a throwaway paragraph) ---

  static double _measure(
      String text, double size, FontWeight w, String? family) {
    final p = (ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontWeight: w,
      fontFamily: family,
    ))..addText(text))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 10000));
    return p.maxIntrinsicWidth;
  }

  static double _spaceWidth(double size, FontWeight w, String? family) =>
      _measure(' ', size, w, family).clamp(1.0, 100.0);

  String _computeGap(String label, String value, double width, double size,
      FontWeight w, String? family) {
    final used = _measure(label, size, w, family) +
        _measure(value, size, w, family);
    final sw = _spaceWidth(size, w, family);
    final gapDots = (width - used).clamp(sw, width);
    final count = (gapDots / sw).floor().clamp(1, 400);
    return ' ' * count;
  }

  /// Build the item row as 4 separately-positioned paragraphs so columns align
  /// exactly regardless of the (proportional, Devanagari) font — the reliable
  /// alternative to space-padding, which drifts and looks garbled on thermal.
  /// [contentWidth] is the drawable width; [dx] is the left margin already
  /// applied by the caller (so returned x offsets are absolute on the canvas).
  List<_Col> buildItemColumns(double contentWidth, String? family, double size,
      FontWeight w, double dx, {double lineHeight = 1.45}) {
    final nameW = contentWidth * 0.50;
    final qtyW = contentWidth * 0.14;
    final priceW = contentWidth * 0.18;
    final totalW = contentWidth - nameW - qtyW - priceW;
    final xs = [
      dx, // name
      dx + nameW, // qty box
      dx + nameW + qtyW, // price box
      dx + nameW + qtyW + priceW, // total box
    ];
    final ws = [nameW, qtyW, priceW, totalW];
    final aligns = [
      ui.TextAlign.left,
      ui.TextAlign.right,
      ui.TextAlign.right,
      ui.TextAlign.right,
    ];
    final cells = [a, b, c, d];
    final cols = <_Col>[];
    for (int i = 0; i < 4; i++) {
      final p = (ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: size,
        fontWeight: w,
        fontFamily: i == 0 ? family : null, // numbers are ASCII → default font
        maxLines: 1,
        ellipsis: i == 0 ? '…' : null,
        textAlign: aligns[i],
        strutStyle: ui.StrutStyle(
          fontFamily: i == 0 ? family : null,
          fontSize: size,
          height: lineHeight,
          forceStrutHeight: true,
        ),
      ))
            ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)))
            ..addText(cells[i]))
          .build()
        ..layout(ui.ParagraphConstraints(width: ws[i]));
      cols.add(_Col(p, xs[i]));
    }
    return cols;
  }

  /// Right-align each numeric column inside its box by left-padding with spaces.
  // ignore: unused_element
  String _composeColumns(List<String> cells, List<double> widths, double size,
      FontWeight w, String? family) {
    final sw = _spaceWidth(size, w, family);
    final buf = StringBuffer();
    for (int i = 0; i < cells.length; i++) {
      var cell = cells[i];
      final boxW = widths[i];
      var cellW = _measure(cell, size, w, family);
      // Truncate the name column if it overflows its box.
      if (i == 0 && cellW > boxW) {
        while (cell.isNotEmpty && cellW > boxW) {
          cell = cell.substring(0, cell.length - 1);
          cellW = _measure('$cell…', size, w, family);
        }
        cell = '$cell…';
        cellW = _measure(cell, size, w, family);
      }
      if (i == 0) {
        // Left-aligned: text then pad to box width.
        final padDots = (boxW - cellW).clamp(0, boxW);
        buf.write(cell);
        buf.write(' ' * (padDots / sw).floor().clamp(0, 200));
      } else {
        // Right-aligned: pad first, then text.
        final padDots = (boxW - cellW).clamp(0, boxW);
        buf.write(' ' * (padDots / sw).floor().clamp(0, 200));
        buf.write(cell);
      }
    }
    return buf.toString();
  }
}

class _LaidOut {
  /// Null for divider rows (drawn as a line) and for column rows (which use
  /// [columns] instead — each a paragraph pre-positioned at an absolute x).
  final ui.Paragraph? paragraph;
  final double y;
  final _Row row;
  final List<_Col>? columns;
  _LaidOut(this.paragraph, this.y, this.row, {this.columns});
}

/// A single positioned column paragraph within an item row.
class _Col {
  final ui.Paragraph paragraph;
  final double x; // absolute left offset in dots
  _Col(this.paragraph, this.x);
}
