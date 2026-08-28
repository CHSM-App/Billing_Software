import 'package:flutter/material.dart';

/// WhatsApp's brand colour, used wherever the mark is tinted.
const Color whatsAppGreen = Color(0xFF25D366);

/// The WhatsApp mark — a speech bubble with a handset inside — drawn from path
/// data rather than an icon font.
///
/// Material Icons omits it (and every other brand mark) because it is a
/// trademark, and the app has no SVG package. Drawing it here keeps the real,
/// recognisable glyph without adding a ~200KB icon font for one symbol.
///
/// The path is the official mark's outline, authored on a 24×24 grid so it
/// lines up with the Material icons beside it. Tinting it a single flat colour
/// is the permitted monochrome treatment; it is never re-proportioned.
class WhatsAppMark extends StatelessWidget {
  final double size;
  final Color color;

  const WhatsAppMark({super.key, this.size = 20, this.color = whatsAppGreen});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WhatsAppPainter(color)),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  final Color color;
  const _WhatsAppPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Authored on 24×24, then scaled to whatever the caller asked for.
    final s = size.width / 24.0;
    canvas.scale(s, s);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Outer bubble: a ring with the tail at the lower left, matching the mark's
    // silhouette. Drawn as an even-odd path so the ring is hollow.
    final bubble = Path()
      ..fillType = PathFillType.evenOdd
      // Outer edge.
      ..moveTo(12.04, 2.0)
      ..cubicTo(6.58, 2.0, 2.13, 6.45, 2.13, 11.91)
      ..cubicTo(2.13, 13.66, 2.59, 15.36, 3.45, 16.86)
      ..lineTo(2.05, 22.0)
      ..lineTo(7.30, 20.62)
      ..cubicTo(8.75, 21.41, 10.38, 21.83, 12.04, 21.83)
      ..cubicTo(17.50, 21.83, 21.95, 17.38, 21.95, 11.92)
      ..cubicTo(21.95, 6.46, 17.50, 2.0, 12.04, 2.0)
      ..close()
      // Inner edge — subtracted, leaving a ring of even weight.
      ..moveTo(12.04, 20.15)
      ..cubicTo(10.56, 20.15, 9.11, 19.75, 7.85, 19.00)
      ..lineTo(7.55, 18.82)
      ..lineTo(4.43, 19.64)
      ..lineTo(5.26, 16.60)
      ..lineTo(5.07, 16.29)
      ..cubicTo(4.24, 14.98, 3.81, 13.466, 3.81, 11.91)
      ..cubicTo(3.81, 7.38, 7.50, 3.68, 12.05, 3.68)
      ..cubicTo(16.57, 3.68, 20.27, 7.38, 20.27, 11.92)
      ..cubicTo(20.27, 16.45, 16.57, 20.15, 12.04, 20.15)
      ..close();
    canvas.drawPath(bubble, paint);

    // The handset: the mark's interior stroke, a stylised receiver sweeping
    // from the earpiece down to the mouthpiece.
    final handset = Path()
      ..moveTo(16.56, 13.99)
      ..cubicTo(16.31, 13.87, 15.10, 13.27, 14.87, 13.19)
      ..cubicTo(14.65, 13.11, 14.48, 13.07, 14.32, 13.32)
      ..cubicTo(14.16, 13.57, 13.68, 14.12, 13.54, 14.29)
      ..cubicTo(13.39, 14.45, 13.25, 14.47, 13.00, 14.35)
      ..cubicTo(12.75, 14.22, 11.96, 13.96, 11.02, 13.12)
      ..cubicTo(10.29, 12.47, 9.79, 11.66, 9.65, 11.41)
      ..cubicTo(9.51, 11.16, 9.64, 11.03, 9.76, 10.90)
      ..cubicTo(9.88, 10.79, 10.02, 10.61, 10.14, 10.46)
      ..cubicTo(10.26, 10.31, 10.30, 10.20, 10.38, 10.04)
      ..cubicTo(10.47, 9.87, 10.42, 9.73, 10.36, 9.60)
      ..cubicTo(10.30, 9.48, 9.80, 8.26, 9.59, 7.77)
      ..cubicTo(9.39, 7.29, 9.18, 7.35, 9.03, 7.35)
      ..cubicTo(8.89, 7.34, 8.72, 7.34, 8.55, 7.34)
      ..cubicTo(8.39, 7.34, 8.12, 7.40, 7.89, 7.65)
      ..cubicTo(7.67, 7.90, 7.03, 8.50, 7.03, 9.71)
      ..cubicTo(7.03, 10.93, 7.91, 12.10, 8.03, 12.27)
      ..cubicTo(8.16, 12.43, 9.79, 14.94, 12.28, 16.01)
      ..cubicTo(12.87, 16.27, 13.33, 16.42, 13.70, 16.53)
      ..cubicTo(14.29, 16.72, 14.83, 16.69, 15.26, 16.63)
      ..cubicTo(15.73, 16.56, 16.72, 16.03, 16.93, 15.45)
      ..cubicTo(17.13, 14.87, 17.13, 14.38, 17.07, 14.28)
      ..cubicTo(17.01, 14.17, 16.85, 14.11, 16.60, 13.99)
      ..close();
    canvas.drawPath(handset, paint);
  }

  @override
  bool shouldRepaint(_WhatsAppPainter old) => old.color != color;
}
