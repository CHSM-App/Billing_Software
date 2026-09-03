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
Future<Uint8List> compressToJpeg(Uint8List bytes) => compute(compressJpegSync, bytes);

/// Decode, resize to max 1000px on the long edge, and JPEG-encode at ~80%.
///
/// Must stay a top-level function: [compute] cannot take a closure.
Uint8List compressJpegSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes; // not decodable — send as-is, server validates
  const maxEdge = 1000;
  img.Image out = decoded;
  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longEdge > maxEdge) {
    if (decoded.width >= decoded.height) {
      out = img.copyResize(decoded, width: maxEdge);
    } else {
      out = img.copyResize(decoded, height: maxEdge);
    }
  }
  return img.encodeJpg(out, quality: 80);
}
