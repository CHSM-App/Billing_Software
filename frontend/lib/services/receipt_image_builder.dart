import 'dart:async';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
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
  static const int _paperDots = 384;

  static const double _hPad = 6; // left/right margin in dots
  static const double _fontSize = 22;
  static const double _smallFont = 19;
  static const double _lineGap = 10; // vertical gap between rows
  static const double _dividerHeight = 14; // reserved band for a rule

  /// Builds the full ESC/POS byte stream (raster image + feed) for [bill].
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
    );

    final profile = await CapabilityProfile.load();
    // 58mm paper → 384-dot head. Must match [_paperDots].
    final generator = Generator(PaperSize.mm58, profile);

    final bytes = <int>[];
    // GS v 0 raster at the true 384-dot width (verified: widthBytes=48).
    // This is the clean path: one raster block, honest width, no 24-dot band
    // mechanics. The earlier squish was only because the image was 576px wide
    // being sent to a 384-dot head — fixed by matching _paperDots to 58mm.
    bytes.addAll(generator.imageRaster(image));
    bytes.addAll(generator.feed(3));
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
  }) async {
    // First pass: lay out every paragraph to measure total height.
    final rows = _buildRows(bill, labels,
        businessName: businessName,
        businessPhone: businessPhone,
        businessAddress: businessAddress);

    final contentWidth = _paperDots - _hPad * 2;
    final laid = <_LaidOut>[];
    // Extra top leading so the print head doesn't clip the first line.
    double y = _hPad + 12;
    for (final row in rows) {
      if (row.kind == _RowKind.divider) {
        // Dividers are drawn as a solid rule, not a paragraph.
        laid.add(_LaidOut(null, y, row));
        y += _dividerHeight;
        continue;
      }
      final p = row.layout(contentWidth, labels.languageCode);
      laid.add(_LaidOut(p, y, row));
      // Advance by a GUARANTEED fixed pitch (not the measured paragraph
      // height, which under-reports for Devanagari and let lines overprint).
      // Two-line rows (wrapped) get a second slot.
      final measured = p.height;
      final oneLine = row.fontSize * 1.55 + _lineGap;
      y += measured > oneLine ? measured + _lineGap : oneLine;
    }
    final totalHeight = (y + _hPad).ceil();

    // Second pass: paint onto a white canvas.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _paperDots.toDouble(), totalHeight.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final rulePaint = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2;
    for (final lo in laid) {
      if (lo.paragraph == null) {
        // Solid divider line centred in its reserved band.
        final ry = lo.y + _dividerHeight / 2;
        canvas.drawLine(
          Offset(_hPad, ry),
          Offset(_paperDots - _hPad, ry),
          rulePaint,
        );
      } else {
        canvas.drawParagraph(lo.paragraph!, Offset(_hPad, lo.y));
      }
    }
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(_paperDots, totalHeight);
    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    uiImage.dispose();

    // Convert RGBA → grayscale → the image package's Image, then threshold to
    // pure black/white so the thermal head prints crisp text.
    final rgba = byteData!.buffer.asUint8List();
    final out = img.Image(width: _paperDots, height: totalHeight);
    for (int py = 0; py < totalHeight; py++) {
      for (int px = 0; px < _paperDots; px++) {
        final i = (py * _paperDots + px) * 4;
        final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
        // Luminance; anything darker than mid-gray becomes black.
        final lum = (0.299 * r + 0.587 * g + 0.114 * b);
        final v = lum < 160 ? 0 : 255;
        out.setPixelRgb(px, py, v, v, v);
      }
    }
    return out;
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
  }) {
    final rows = <_Row>[];

    // Header
    rows.add(_Row.centered(
        businessName ?? labels.defaultBusiness, _fontSize, FontWeight.w700));
    if (businessAddress != null && businessAddress.isNotEmpty) {
      rows.add(_Row.centered(businessAddress, _smallFont, FontWeight.w400));
    }
    if (businessPhone != null && businessPhone.isNotEmpty) {
      rows.add(_Row.centered(
          '${labels.phonePrefix} $businessPhone', _smallFont, FontWeight.w400));
    }
    rows.add(_Row.divider());

    // Bill info
    rows.add(_Row.left('${labels.billNo} ${bill.billNumber}', _smallFont));
    rows.add(_Row.left(
        '${labels.date} ${_formatDate(bill.createdAt.toLocal())}', _smallFont));
    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      rows.add(_Row.left('${labels.customer} ${bill.customerName}', _smallFont));
    }
    if (bill.customerPhone != null && bill.customerPhone!.isNotEmpty) {
      rows.add(_Row.left(
          '${labels.customerPhone} ${bill.customerPhone}', _smallFont));
    }
    rows.add(_Row.divider());

    // Items header + rows (4 columns)
    rows.add(_Row.itemRow(
        labels.colItem, labels.colQty, labels.colPrice, labels.colTotal,
        bold: true));
    rows.add(_Row.divider());
    for (final item in bill.items) {
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      rows.add(_Row.itemRow(
        item.itemName,
        qty,
        item.unitPrice.toStringAsFixed(2),
        item.lineTotal.toStringAsFixed(2),
      ));
    }
    rows.add(_Row.divider());

    // Totals
    if (bill.taxAmount > 0) {
      rows.add(_Row.twoCol(
          labels.subtotal, 'Rs.${bill.subtotal.toStringAsFixed(2)}'));
      rows.add(
          _Row.twoCol(labels.tax, 'Rs.${bill.taxAmount.toStringAsFixed(2)}'));
    }
    if (bill.discountAmount > 0) {
      rows.add(_Row.twoCol(
          labels.discount, 'Rs.${bill.discountAmount.toStringAsFixed(2)}'));
    }
    rows.add(_Row.twoCol(
        labels.total, 'Rs.${bill.total.toStringAsFixed(2)}',
        bold: true));
    rows.add(_Row.twoCol(labels.payment, bill.paymentMode.toUpperCase()));
    rows.add(_Row.divider());
    rows.add(_Row.centered(labels.thankYou, _smallFont, FontWeight.w400));

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

enum _RowKind { centered, left, twoCol, itemRow, divider }

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
  factory _Row.twoCol(String label, String value, {bool bold = false}) =>
      _Row._(_RowKind.twoCol, ReceiptImageBuilder._smallFont,
          bold ? FontWeight.w700 : FontWeight.w400,
          a: label, b: value);
  factory _Row.itemRow(String name, String qty, String price, String total,
          {bool bold = false}) =>
      _Row._(_RowKind.itemRow, ReceiptImageBuilder._smallFont,
          bold ? FontWeight.w700 : FontWeight.w400,
          a: name, b: qty, c: price, d: total);
  factory _Row.divider() =>
      _Row._(_RowKind.divider, ReceiptImageBuilder._smallFont, FontWeight.w400);

  /// Font family per locale — Devanagari for Marathi, monospace-ish for Latin.
  static String? _family(String lang) =>
      lang == 'mr' ? 'Noto Sans Devanagari' : null;

  ui.Paragraph layout(double width, String lang) {
    final family = _family(lang);
    switch (kind) {
      case _RowKind.divider:
        // Dividers are painted as a drawn line by the builder; this branch
        // isn't reached, but the switch must be exhaustive.
        return _simple('', ReceiptImageBuilder._smallFont, FontWeight.w400,
            ui.TextAlign.left, width, family);
      case _RowKind.centered:
        return _simple(a, fontSize, weight, ui.TextAlign.center, width, family);
      case _RowKind.left:
        return _simple(a, fontSize, weight, ui.TextAlign.left, width, family);
      case _RowKind.twoCol:
        return _twoColumns(a, b, width, family);
      case _RowKind.itemRow:
        return _fourColumns(a, b, c, d, width, family);
    }
  }

  ui.Paragraph _simple(String text, double size, FontWeight w,
      ui.TextAlign align, double width, String? family) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      fontSize: size,
      fontWeight: w,
      fontFamily: family,
      maxLines: 2,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)))
      ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// Label left, value right-aligned, on one line.
  ui.Paragraph _twoColumns(String label, String value, double width,
      String? family) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: fontSize,
      fontWeight: weight,
      fontFamily: family,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)));
    // Use a tab-like layout via placeholder-free spacing: two runs separated by
    // an expanding gap isn't supported directly, so right-align the value with
    // a full-width paragraph and let alignment place each piece.
    builder.addText(label);
    // Pad with spaces to push value right — measured cheaply below.
    final gap = _computeGap(label, value, width, fontSize, weight, family);
    builder.addText(gap);
    builder.addText(value);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  /// Item(60%) Qty(10%) Price(15%) Total(15%) using space padding.
  ui.Paragraph _fourColumns(
      String name, String qty, String price, String total,
      double width, String? family) {
    // Columns are measured in dots; build one string with computed gaps so the
    // numeric columns line up regardless of script width.
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: fontSize,
      fontWeight: weight,
      fontFamily: family,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF000000)));

    final nameW = width * 0.52;
    final qtyW = width * 0.12;
    final priceW = width * 0.18;
    // Name left-truncated to its column, then right-aligned numeric columns via
    // padded runs. We approximate with a single line and tab stops emulated by
    // padding spaces computed from measured widths.
    final line = _composeColumns(
      [name, qty, price, total],
      [nameW, qtyW, priceW, width - nameW - qtyW - priceW],
      fontSize,
      weight,
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

  /// Right-align each numeric column inside its box by left-padding with spaces.
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
  /// Null for divider rows, which are drawn as a line rather than text.
  final ui.Paragraph? paragraph;
  final double y;
  final _Row row;
  _LaidOut(this.paragraph, this.y, this.row);
}
