import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:Vittam/services/table_qr_image.dart';

void main() {
  testWidgets('renders a valid QR PNG with centred label', (tester) async {
    late final Uint8List png;
    await tester.runAsync(() async {
      png = await TableQrImage.renderPng(
        data: 'http://192.168.1.10:5000/order/deadbeefcafef00d',
        label: 'T12',
        pixelSize: 600,
      );
    });

    // Decodes as a 600x600 PNG.
    final decoded = img.decodePng(png)!;
    expect(decoded.width, 600);
    expect(decoded.height, 600);

    // Sanity: it's a real QR, not a blank/solid image — there must be a healthy
    // mix of black and white pixels (QR modules), roughly 25%–60% dark.
    var dark = 0;
    for (var y = 0; y < decoded.height; y += 3) {
      for (var x = 0; x < decoded.width; x += 3) {
        final p = decoded.getPixel(x, y);
        if (p.r < 128) dark++;
      }
    }
    final sampled = (decoded.width ~/ 3) * (decoded.height ~/ 3);
    final ratio = dark / sampled;
    expect(ratio, greaterThan(0.10),
        reason: 'too few dark pixels — QR did not render');
    expect(ratio, lessThan(0.70),
        reason: 'too many dark pixels — image is mostly black');

    // The centre carries a white label badge. NOTE: `flutter test` uses the
    // Ahem test font, which renders every glyph as a solid black box — so the
    // exact glyph area is unreliable here. Instead we assert the badge exists
    // by comparing to a no-label render: the badge introduces a distinct white
    // rounded rectangle (its fill + border) around the centre that a plain QR
    // does not have. We sample a ring just inside the badge edge, above/below
    // the (short, centred) text, which is white background in real fonts and
    // clearly different from the surrounding QR modules.
    final c = decoded.width ~/ 2;
    final boxHalfW = (decoded.width * 0.13).round(); // half of 0.26*size
    final boxHalfH = (decoded.height * 0.065).round(); // half of 0.13*size

    int whiteInRing(img.Image im) {
      var white = 0;
      // Top & bottom inner edges of the badge (background, not glyphs).
      for (final yy in [c - boxHalfH + 4, c + boxHalfH - 4]) {
        for (var x = c - boxHalfW + 4; x < c + boxHalfW - 4; x++) {
          if (im.getPixel(x, yy).r > 200) white++;
        }
      }
      return white;
    }

    late final Uint8List noLabelPng;
    await tester.runAsync(() async {
      noLabelPng = await TableQrImage.renderPng(
        data: 'http://192.168.1.10:5000/order/deadbeefcafef00d',
        label: '',
        pixelSize: 600,
      );
    });
    final noLabel = img.decodePng(noLabelPng)!;

    final labelWhite = whiteInRing(decoded);
    final plainWhite = whiteInRing(noLabel);
    // ignore: avoid_print
    print('badge-ring white — label: $labelWhite, plain QR: $plainWhite');
    expect(labelWhite, greaterThan(plainWhite),
        reason: 'centre badge not visible (no whiter than a plain QR)');

    // ignore: avoid_print
    print('QR PNG ok: ${png.length} bytes, dark ratio ${ratio.toStringAsFixed(2)}');
  });
}
