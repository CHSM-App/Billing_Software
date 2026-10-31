import 'dart:ui' as ui;
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Renders a product barcode label — item name, price, an actual scannable
/// Code128 barcode, and its human-readable value — to a [ui.Image] for thermal
/// printing (raster). Used on Bluetooth printers which can't draw a barcode
/// from a text command the way TSPL (Windows) can.
class BarcodeImage {
  /// [pixelWidth] is the raster width in device pixels. Defaults to 406 —
  /// a 2-inch label at 203 dpi (the standard thermal density). Height is derived
  /// from the content. [subtitle] is an optional extra line under the name (e.g.
  /// a variant/size label like "Large"). Every text line is optional — a null
  /// [itemName] / [subtitle] / [price], or [showValue] false, leaves it off
  /// (the "Download all barcodes" field picker); the bars are always drawn.
  static Future<ui.Image> render({
    required String barcodeValue,
    String? itemName,
    double? price,
    String? subtitle,
    bool showValue = true,
    int pixelWidth = 406, // 2 inch @ 203 dpi
  }) async {
    final width = pixelWidth.toDouble();
    final margin = width * 0.06;
    final contentWidth = width - margin * 2;

    // Layout metrics (device pixels).
    const nameSize = 26.0;
    const subtitleSize = 22.0;
    const priceSize = 26.0;
    const valueSize = 22.0;
    const barcodeHeight = 90.0;
    const gap = 10.0;

    TextPainter? line(String? text, double size, FontWeight weight) =>
        (text == null || text.isEmpty)
            ? null
            : _textPainter(text, size, weight,
                maxWidth: contentWidth, center: true);

    // Lines above the bars, top to bottom: name, size, price.
    final above = [
      line(itemName, nameSize, FontWeight.w700),
      line(subtitle, subtitleSize, FontWeight.w500),
      line(price == null ? null : 'Rs. ${price.toStringAsFixed(2)}', priceSize,
          FontWeight.w600),
    ].whereType<TextPainter>().toList();
    final valuePainter =
        showValue ? line(barcodeValue, valueSize, FontWeight.w400) : null;

    final totalHeight = margin +
        above.fold(0.0, (h, p) => h + p.height + gap) +
        barcodeHeight +
        (valuePainter != null ? 6 + valuePainter.height : 0) +
        margin;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, totalHeight), Paint()..color = Colors.white);

    var y = margin;
    // Name / size / price, each centred.
    for (final p in above) {
      p.paint(canvas, Offset(margin + (contentWidth - p.width) / 2, y));
      y += p.height + gap;
    }

    // Actual Code128 barcode.
    final bc = Barcode.code128();
    final barPaint = Paint()..color = Colors.black;
    for (final el in bc.make(barcodeValue,
        width: contentWidth, height: barcodeHeight)) {
      if (el is BarcodeBar && el.black) {
        canvas.drawRect(
          Rect.fromLTWH(margin + el.left, y + el.top, el.width, el.height),
          barPaint,
        );
      }
    }
    y += barcodeHeight + 6;

    // Human-readable value under the bars.
    valuePainter?.paint(
        canvas, Offset(margin + (contentWidth - valuePainter.width) / 2, y));

    final picture = recorder.endRecording();
    return picture.toImage(pixelWidth, totalHeight.ceil());
  }

  static TextPainter _textPainter(
    String text,
    double fontSize,
    FontWeight weight, {
    required double maxWidth,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: Colors.black, fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }
}
