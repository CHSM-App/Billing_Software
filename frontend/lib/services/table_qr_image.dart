import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Renders a table's ordering QR code — with the table name drawn in a white
/// badge at the centre — to a [ui.Image]. The same image feeds both sharing
/// (PNG) and thermal printing (ESC/POS raster).
///
/// The centre label is safe for QR codes: `qrCode()` here uses a high error
/// correction level, so covering the middle ~18% still scans reliably.
class TableQrImage {
  /// Build the QR image. [pixelSize] is the final square size in device pixels
  /// (larger = crisper print). [label] is drawn centred (e.g. the table number).
  static Future<ui.Image> render({
    required String data,
    required String label,
    int pixelSize = 600,
    Color foreground = Colors.black,
    Color background = Colors.white,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = pixelSize.toDouble();

    // Background.
    final bgPaint = Paint()..color = background;
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), bgPaint);

    // Quiet zone (margin) around the QR — required for reliable scanning.
    final margin = size * 0.06;
    final qrSize = size - margin * 2;

    final barcode = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.high,
    );
    final fgPaint = Paint()..color = foreground;
    for (final element in barcode.make(data, width: qrSize, height: qrSize)) {
      if (element is BarcodeBar && element.black) {
        canvas.drawRect(
          Rect.fromLTWH(
            margin + element.left,
            margin + element.top,
            element.width,
            element.height,
          ),
          fgPaint,
        );
      }
    }

    // Centre badge with the table name.
    _drawCentreLabel(canvas, size, label, foreground, background);

    final picture = recorder.endRecording();
    return picture.toImage(pixelSize, pixelSize);
  }

  /// PNG bytes for sharing/saving.
  static Future<Uint8List> renderPng({
    required String data,
    required String label,
    int pixelSize = 600,
  }) async {
    final image = await render(data: data, label: label, pixelSize: pixelSize);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Could not encode QR image');
    return bytes.buffer.asUint8List();
  }

  static void _drawCentreLabel(
    Canvas canvas,
    double size,
    String label,
    Color fg,
    Color bg,
  ) {
    if (label.trim().isEmpty) return;

    // Fixed-proportion white badge so it never covers more than ~18% of the QR
    // (safe with high error correction) regardless of text metrics.
    final boxW = size * 0.26;
    final boxH = size * 0.13;
    final boxRect = Rect.fromCenter(
      center: Offset(size / 2, size / 2),
      width: boxW,
      height: boxH,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, Radius.circular(size * 0.015)),
      Paint()..color = bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, Radius.circular(size * 0.015)),
      Paint()
        ..color = fg
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.006,
    );

    // Draw the text with a ui.ParagraphBuilder (independent of widget-layer
    // TextPainter), clamped to the badge width.
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: size * 0.072,
      fontWeight: FontWeight.w800,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: fg))
      ..addText(label);
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: boxW - size * 0.02));
    canvas.drawParagraph(
      paragraph,
      Offset(size / 2 - (boxW - size * 0.02) / 2,
          size / 2 - paragraph.height / 2),
    );
  }
}
