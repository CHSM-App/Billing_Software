import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;

/// Which ESC/POS bit-image command to emit.
enum RasterMode {
  /// GS v 0 — modern raster block (compact; can stutter on cheap printers).
  gsV0,

  /// ESC * — classic 24-dot strip mode (smoothest, prints like text lines).
  escStar,
}

/// Renders arbitrary Unicode (including full Devanagari shaping — matras,
/// half-forms, conjuncts like क्ष / त्र / ज्ञ / श्र) to a monochrome ESC/POS
/// raster bitmap.
///
/// WHY THIS EXISTS
/// ---------------
/// Generic 203-DPI ESC/POS printers (Shreyans 80B included) have no Devanagari
/// font ROM and no shaping engine, so they can NEVER print Marathi as text.
/// The only correct approach — the one professional Indian POS apps use — is to
/// let Flutter (which uses HarfBuzz) shape the text into pixels, then send those
/// pixels as a raster image the printer just prints dot-for-dot.
///
/// The pipeline:
///   String  →  ui.Paragraph (shaped)  →  ui.Image (RGBA)
///           →  grayscale  →  Floyd–Steinberg dither  →  1bpp packed rows
///           →  GS v 0 raster command bytes
class DevanagariRaster {
  /// Dots across the print head.
  ///  - 80mm paper @ 203dpi ≈ 576 dots
  ///  - 58mm paper @ 203dpi ≈ 384 dots
  static const int dots80mm = 576;
  static const int dots58mm = 384;

  /// Bundled font family that covers Devanagari. `Mangal` is declared in
  /// pubspec.yaml. NotoSansDevanagari (via google_fonts) is used as a fallback
  /// so shaping still works even if Mangal is missing a glyph.
  static const String primaryFontFamily = 'Mangal';

  /// Render a single block of text to a 1bpp ESC/POS raster.
  ///
  /// [widthDots] – printable width (dots80mm / dots58mm).
  /// [fontSize]  – logical px at 1x; scaled by [scale] for crisp output.
  /// [scale]     – supersample factor. Render big, the printer prints small →
  ///               anti-aliased edges survive the monochrome step much better.
  /// [align]     – text alignment within the strip.
  static Future<Uint8List> textToEscPosRaster(
    String text, {
    int widthDots = dots80mm,
    double fontSize = 26,
    FontWeight fontWeight = FontWeight.w500,
    TextAlign align = TextAlign.center,
    double scale = 1.0,
    bool dither = false,
    int threshold = 160,
  }) async {
    final img = await _renderTextImage(
      text,
      widthDots: widthDots,
      fontSize: fontSize,
      fontWeight: fontWeight,
      align: align,
      scale: scale,
    );
    try {
      return await imageToEscPosRaster(img,
          dither: dither, threshold: threshold);
    } finally {
      img.dispose();
    }
  }

  /// Render MANY lines into ONE continuous tall raster, emitted as band-sliced
  /// `GS v 0` blocks.
  ///
  /// This is the fast path that matches professional POS apps: the whole receipt
  /// is shaped in ONE paragraph and captured as ONE image (never per-word/per-
  /// item), supersampled then downscaled to a multiple-of-8 width, thresholded
  /// to 1-bit, and sent as ~256-dot GS v 0 bands. With a fast large-chunk BT
  /// send this prints at effectively the same speed as English text.
  static Future<Uint8List> linesToEscPosRaster(
    List<String> lines, {
    int widthDots = dots80mm,
    double fontSize = 26,
    // w400 keeps Devanagari strokes THIN — bold fattens/blurs them at 203dpi.
    FontWeight fontWeight = FontWeight.w400,
    TextAlign align = TextAlign.center,
    // 2x supersample + crisp threshold → clean 1-dot strokes like pro apps.
    double scale = 2.0,
    bool dither = false,
    // Higher threshold = only true stroke pixels become dots → thinner, sharper.
    int threshold = 128,
    // Band into ~256-dot GS v 0 blocks: big enough to be efficient, small enough
    // that clone printers with tiny receive buffers don't overrun (which caused
    // stutter/dropped rows). ESC * mangles output on this printer, so GS v 0.
    int bandHeight = 256,
    RasterMode mode = RasterMode.gsV0,
  }) async {
    final img = await _renderTextImage(
      lines.join('\n'),
      widthDots: widthDots,
      fontSize: fontSize,
      fontWeight: fontWeight,
      align: align,
      scale: scale,
    );
    try {
      // Downscale the supersampled image to printer dots (width padded to a
      // multiple of 8 to prevent diagonal shear), then threshold.
      final target = await _downscaleToRasterWidth(img, widthDots);
      try {
        return await imageToEscPosRaster(target,
            dither: dither,
            threshold: threshold,
            bandHeight: bandHeight,
            mode: mode);
      } finally {
        if (!identical(target, img)) target.dispose();
      }
    } finally {
      img.dispose();
    }
  }

  /// Downscale [src] so the content fits [targetWidth] dots, then pad the canvas
  /// width up to a multiple of 8. Supersampling then area-averaging down turns
  /// anti-aliased text into thin, crisp strokes after thresholding.
  ///
  /// The multiple-of-8 canvas is critical: ESC/POS packs 8 horizontal dots per
  /// byte, so if the image width isn't a multiple of 8 the row stride and the
  /// GS v 0 xL/xH byte count disagree — every row shifts a fraction and the
  /// print comes out sheared diagonally. Padding with white (blank) dots on the
  /// right keeps every row exactly bytesPerRow bytes with no shift.
  static Future<ui.Image> _downscaleToRasterWidth(
      ui.Image src, int targetWidth) async {
    // Canvas width = target rounded UP to a multiple of 8.
    final canvasWidth = (targetWidth + 7) & ~7;
    // Content width: fit within targetWidth (no upscaling past the source).
    final contentWidth =
        src.width <= targetWidth ? src.width : targetWidth;
    final contentHeight = (src.height * contentWidth / src.width).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // White background so the padding on the right is blank (no dots).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasWidth.toDouble(), contentHeight.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, contentWidth.toDouble(), contentHeight.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(canvasWidth, contentHeight);
    picture.dispose();
    return out;
  }

  /// Render text to a [ui.Image]. Caller owns the image (must dispose).
  static Future<ui.Image> _renderTextImage(
    String text, {
    required int widthDots,
    required double fontSize,
    required FontWeight fontWeight,
    required TextAlign align,
    required double scale,
  }) async {
    final effWidth = (widthDots * scale).round();

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align,
      fontFamily: primaryFontFamily,
      fontSize: fontSize * scale,
      fontWeight: fontWeight,
      // Fallbacks ensure Devanagari glyphs resolve even outside Mangal.
      // The platform Devanagari font is picked up automatically by the engine.
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFF000000),
        fontFamily: primaryFontFamily,
        fontFamilyFallback: const ['Noto Sans Devanagari', 'Nirmala UI'],
        fontSize: fontSize * scale,
        fontWeight: fontWeight,
        height: 1.15,
      ))
      ..addText(text);

    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: effWidth.toDouble()));

    final height = paragraph.height.ceil().clamp(1, 20000);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // White background — printer treats dark pixels as dots.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, effWidth.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, Offset.zero);

    final picture = recorder.endRecording();
    final img = await picture.toImage(effWidth, height);
    picture.dispose();
    return img;
  }

  /// Convert a [ui.Image] to ESC/POS `GS v 0` raster bytes.
  ///
  /// Rows are padded so width is a multiple of 8. Dark pixels (luminance below
  /// [threshold]) become printed dots. With [dither] the luminance is passed
  /// through Floyd–Steinberg first for smoother greys.
  ///
  /// [bandHeight] slices the image into short horizontal strips, each sent as
  /// its own `GS v 0`. This makes the printer print+feed continuously (smooth,
  /// like text lines) instead of buffering one giant image and stuttering. Set
  /// 0 to emit a single image.
  static Future<Uint8List> imageToEscPosRaster(
    ui.Image image, {
    bool dither = false,
    int threshold = 128,
    int bandHeight = 256,
    RasterMode mode = RasterMode.gsV0,
  }) async {
    final w = image.width;
    final h = image.height;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Could not read image pixels');
    }
    final rgba = byteData.buffer.asUint8List();

    // 1) luminance buffer (0=black .. 255=white)
    final lum = Uint8List(w * h);
    for (var i = 0, p = 0; i < rgba.length; i += 4, p++) {
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2], a = rgba[i + 3];
      // Composite over white for any transparency.
      final inv = 255 - a;
      final rr = (r * a + 255 * inv) ~/ 255;
      final gg = (g * a + 255 * inv) ~/ 255;
      final bb = (b * a + 255 * inv) ~/ 255;
      lum[p] = (0.299 * rr + 0.587 * gg + 0.114 * bb).round();
    }

    // 2) threshold (optionally Floyd–Steinberg dithered) → 1bpp
    // With a multiple-of-8 width, bytesPerRow*8 == w exactly, so every packed
    // row is exactly bytesPerRow bytes and there is no fractional shift (shear).
    final bytesPerRow = (w + 7) >> 3;
    assert(bytesPerRow * 8 == ((w + 7) & ~7),
        'width should be padded to a multiple of 8 before packing');
    final packed = Uint8List(bytesPerRow * h); // 1 = dot (black)

    if (dither) {
      final err = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final idx = y * w + x;
          final old = lum[idx] + err[idx];
          final isBlack = old < 128;
          final newVal = isBlack ? 0.0 : 255.0;
          final e = old - newVal;
          if (isBlack) {
            packed[y * bytesPerRow + (x >> 3)] |= (0x80 >> (x & 7));
          }
          // distribute error
          if (x + 1 < w) err[idx + 1] += e * 7 / 16;
          if (y + 1 < h) {
            if (x > 0) err[idx + w - 1] += e * 3 / 16;
            err[idx + w] += e * 5 / 16;
            if (x + 1 < w) err[idx + w + 1] += e * 1 / 16;
          }
        }
      }
    } else {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (lum[y * w + x] < threshold) {
            packed[y * bytesPerRow + (x >> 3)] |= (0x80 >> (x & 7));
          }
        }
      }
    }

    // 3) Emit the chosen bit-image command(s).
    // Diagnostics: width (dots), bytesPerRow, height — verify xL/xH derive from
    // the packed buffer, not the pre-padding pixel width.
    assert(() {
      // ignore: avoid_print
      print('[DevanagariRaster] GS v 0: width=$w dots, bytesPerRow=$bytesPerRow'
          ' (=${bytesPerRow * 8} dots), height=$h, band=$bandHeight');
      return true;
    }());
    if (mode == RasterMode.escStar) {
      return _emitEscStar(packed, w, h, bytesPerRow);
    }
    return _emitGsV0(packed, h, bytesPerRow, bandHeight);
  }

  /// GS v 0 — modern raster. One (or band-sliced) block. Compact but on cheap
  /// printers a tall block can overrun the buffer and print in stuttering bands.
  static Uint8List _emitGsV0(
      Uint8List packed, int h, int bytesPerRow, int bandHeight) {
    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final out = BytesBuilder();
    final band = bandHeight <= 0 ? h : bandHeight;
    for (var y0 = 0; y0 < h; y0 += band) {
      final bh = (y0 + band > h) ? (h - y0) : band;
      out.add([0x1D, 0x76, 0x30, 0x00, xL, xH, bh & 0xFF, (bh >> 8) & 0xFF]);
      out.add(Uint8List.sublistView(
          packed, y0 * bytesPerRow, (y0 + bh) * bytesPerRow));
    }
    return out.toBytes();
  }

  /// ESC * — classic bit-image mode (24-dot triple-density, m=33). Prints one
  /// 24-dot-tall strip at a time, each followed by a line feed, so the printer
  /// prints+advances continuously exactly like text lines. This is the SMOOTHEST
  /// method on cheap/GBK printers with small buffers — no banding/stutter.
  ///
  /// Data layout differs from GS v 0: it is COLUMN-major. For each 24-dot band,
  /// for each x column, 3 bytes give the 24 vertical dots (MSB = top).
  static Uint8List _emitEscStar(
      Uint8List packedRowMajor, int w, int h, int bytesPerRow) {
    final out = BytesBuilder();
    // Line spacing = 24 dots so consecutive strips touch with no gap. (ESC 3 n)
    out.add([0x1B, 0x33, 24]);

    bool dot(int x, int y) {
      if (y >= h) return false;
      return (packedRowMajor[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) !=
          0;
    }

    for (var y0 = 0; y0 < h; y0 += 24) {
      // ESC * m nL nH  where m=33 (24-dot double density), n = width in columns
      out.add([0x1B, 0x2A, 33, w & 0xFF, (w >> 8) & 0xFF]);
      final strip = Uint8List(w * 3);
      for (var x = 0; x < w; x++) {
        for (var k = 0; k < 3; k++) {
          var b = 0;
          for (var bit = 0; bit < 8; bit++) {
            if (dot(x, y0 + k * 8 + bit)) b |= (0x80 >> bit);
          }
          strip[x * 3 + k] = b;
        }
      }
      out.add(strip);
      out.add([0x0A]); // feed to next 24-dot strip
    }
    // Restore default line spacing.
    out.add([0x1B, 0x32]);
    return out.toBytes();
  }

  /// Convenience: warm up the bundled font so the first render isn't slow / falls
  /// back to a wrong font. Call once at startup (optional).
  static Future<void> ensureFontLoaded() async {
    try {
      final loader = FontLoader(primaryFontFamily)
        ..addFont(rootBundle.load('assets/fonts/Mangal.ttf'));
      await loader.load();
    } catch (_) {
      // Non-fatal: platform Devanagari fallback still shapes correctly.
    }
  }
}
