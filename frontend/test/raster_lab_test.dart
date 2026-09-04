import 'package:Vittam/services/raster_lab.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the fix for thin receipt-table rules/separators intermittently
/// vanishing on print: a stroke drawn at a fractional supersample position
/// gets antialiased across source pixels, softened again by the eventual 2x
/// downscale, and a hairline that lands close to the 1-bit threshold can then
/// disappear — differently on every bill, since the position comes from that
/// bill's own (content-fitted) row heights and column widths. snapToGrid must
/// always return a value that is an exact multiple of [unit], so a stroke's
/// edge always lands on a source-pixel boundary regardless of the fractional
/// input the layout math produced.
void main() {
  group('RasterLab.snapToGrid', () {
    const unit = 2.0; // matches the supersample factor (ss) used when printing

    test('an already-aligned value is returned unchanged', () {
      expect(RasterLab.snapToGrid(10.0, unit), 10.0);
      expect(RasterLab.snapToGrid(0.0, unit), 0.0);
    });

    test('a fractional value snaps to the nearest multiple of unit', () {
      expect(RasterLab.snapToGrid(10.3, unit), 10.0);
      expect(RasterLab.snapToGrid(11.7, unit), 12.0);
      // Exactly halfway rounds up, same as Dart's roundToDouble.
      expect(RasterLab.snapToGrid(9.0, unit), 10.0);
    });

    test('every result is an exact multiple of unit, across a spread of '
        'the kind of accumulated fractional positions row-height math '
        'actually produces', () {
      // gapY * 0.5, paragraph heights, etc. — never round numbers in practice.
      for (final v in [0.37, 1.9, 4.51, 7.0, 13.229, 40.0001, 99.99]) {
        final snapped = RasterLab.snapToGrid(v, unit);
        expect(snapped % unit, 0.0,
            reason: '$v snapped to $snapped, not a multiple of $unit');
      }
    });

    test('never moves a value by more than half a unit', () {
      // The whole point is to correct sub-pixel drift, not relocate the line.
      for (final v in [0.37, 1.9, 4.51, 7.0, 13.229, 40.0001, 99.99]) {
        final snapped = RasterLab.snapToGrid(v, unit);
        expect((snapped - v).abs(), lessThanOrEqualTo(unit / 2));
      }
    });
  });
}
