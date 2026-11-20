import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Shrink a picked photo to something worth uploading.
///
/// Every image the app sends to the server (item photos, the store's payment QR)
/// goes through here, so uploads stay a few hundred KB on a phone connection and
/// the server only ever receives JPEG — which is all its upload routes accept.
///
/// The CPU-heavy encode runs in a background isolate so the UI stays smooth.
/// Purchase-bill scans pass a larger [maxEdge] so small print stays legible.
Future<Uint8List> compressToJpeg(Uint8List bytes,
        {int maxEdge = 1000, int quality = 80}) =>
    compute(compressJpegSync, (bytes, maxEdge, quality));

/// Decode, resize to max [maxEdge] on the long edge, and JPEG-encode.
///
/// Must stay a top-level function: [compute] cannot take a closure.
Uint8List compressJpegSync((Uint8List, int, int) args) {
  final (bytes, maxEdge, quality) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes; // not decodable — send as-is, server validates
  img.Image out = decoded;
  // JPEG has no alpha: transparent pixels (a PNG logo's background) would
  // encode as black. Flatten onto white first.
  if (decoded.hasAlpha) {
    out = img.compositeImage(
        img.Image(width: decoded.width, height: decoded.height)
          ..clear(img.ColorRgb8(255, 255, 255)),
        decoded);
  }
  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longEdge > maxEdge) {
    if (decoded.width >= decoded.height) {
      out = img.copyResize(out, width: maxEdge);
    } else {
      out = img.copyResize(out, height: maxEdge);
    }
  }
  return img.encodeJpg(out, quality: quality);
}
