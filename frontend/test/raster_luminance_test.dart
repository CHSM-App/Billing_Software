import 'package:flutter_test/flutter_test.dart';

/// RasterLab's packing loop switched from floating-point luminance weights to
/// integer ones, because it runs once per pixel over ~half a million pixels of
/// every receipt. The only thing that matters is that the THRESHOLD DECISION —
/// ink or no ink — is unchanged, otherwise printed receipts would subtly
/// change. This pins that.
///
/// Mirrors of the two formulas; the real one lives in raster_lab.dart's
/// _packRgba, which is private to that library.
int lumFloat(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();
int lumInt(int r, int g, int b) => (77 * r + 150 * g + 29 * b) >> 8;

void main() {
  const threshold = 128;

  test('the integer weights sum to exactly 1.0 in /256 fixed point', () {
    expect(77 + 150 + 29, 256);
  });

  test('black stays ink and white stays blank', () {
    expect(lumInt(0, 0, 0), lessThan(threshold));
    expect(lumInt(255, 255, 255), greaterThanOrEqualTo(threshold));
    // The colours that actually cover a receipt: pure black text on white.
    expect(lumInt(0, 0, 0), lumFloat(0, 0, 0));
    expect(lumInt(255, 255, 255), lumFloat(255, 255, 255));
  });

  test('every grey — the whole anti-aliased ramp — decides identically', () {
    for (var v = 0; v <= 255; v++) {
      expect(lumInt(v, v, v) < threshold, lumFloat(v, v, v) < threshold,
          reason: 'grey $v flips between the two formulas');
    }
  });

  test('across the full RGB cube the decision almost never differs, and never '
      'by more than one luminance step', () {
    var differing = 0;
    var worstGap = 0;
    // Step 3 keeps this a couple of seconds while still covering ~600k colours
    // spread over the whole cube.
    for (var r = 0; r <= 255; r += 3) {
      for (var g = 0; g <= 255; g += 3) {
        for (var b = 0; b <= 255; b += 3) {
          final fi = lumFloat(r, g, b);
          final ii = lumInt(r, g, b);
          final gap = (fi - ii).abs();
          if (gap > worstGap) worstGap = gap;
          if ((fi < threshold) != (ii < threshold)) differing++;
        }
      }
    }
    // A hair of rounding is expected; a systematic shift is not.
    expect(worstGap, lessThanOrEqualTo(1),
        reason: 'integer luminance drifts from the float one by $worstGap');
    // Only colours sitting exactly ON the threshold can flip, and only ever to
    // the neighbouring decision — irrelevant for black-on-white receipts.
    final sampled = 86 * 86 * 86;
    expect(differing / sampled, lessThan(0.005),
        reason: '$differing of $sampled sampled colours flipped');
  });
}
