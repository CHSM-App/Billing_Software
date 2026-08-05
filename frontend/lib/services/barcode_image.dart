import 'dart:ui' as ui;
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Renders a product barcode label — item name, price, an actual scannable
/// Code128 barcode, and its human-readable value — to a [ui.Image] for thermal
/// printing (raster). Used on Bluetooth printers which can't draw a barcode
/// from a text command the way TSPL (Windows) can.
class BarcodeImage {
  /// [pixelWidth] is the raster width in device pixels (match the printer's
  /// dot width, e.g. 576 for 80mm). Height is derived from the content.
  static Future<ui.Image> render({
    required String barcodeValue,
    required String itemName,
    required double price,
    int pixelWidth = 576,
  }) async {
    final width = pixelWidth.toDouble();
    final margin = width * 0.06;
    final contentWidth = width - margin * 2;

    // Layout metrics (device pixels).
    const nameSize = 30.0;
    const priceSize = 30.0;
    const valueSize = 24.0;
    const barcodeHeight = 90.0;
    const gap = 12.0;

    final namePainter = _textPainter(itemName, nameSize, FontWeight.w700,
        maxWidth: contentWidth, center: true);
    final pricePainter = _textPainter('Rs. ${price.toStringAsFixed(2)}',
        priceSize, FontWeight.w600,
        maxWidth: contentWidth, center: true);
    final valuePainter = _textPainter(barcodeValue, valueSize, FontWeight.w400,
        maxWidth: contentWidth, center: true);

    final totalHeight = margin +
        namePainter.height +
        gap +
        pricePainter.height +
        gap +
        barcodeHeight +
        6 +
        valuePainter.height +
        margin;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background.
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, totalHeight), Paint()..color = Colors.white);

    var y = margin;
    // Item name (centred).
    namePainter.paint(canvas, Offset(margin + (contentWidth - namePainter.width) / 2, y));
    y += namePainter.height + gap;
    // Price (centred).
    pricePainter.paint(canvas, Offset(margin + (contentWidth - pricePainter.width) / 2, y));
    y += pricePainter.height + gap;

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
    valuePainter.paint(canvas, Offset(margin + (contentWidth - valuePainter.width) / 2, y));

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
