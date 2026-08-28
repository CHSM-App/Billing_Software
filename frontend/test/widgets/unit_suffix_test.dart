import 'package:Vittam/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [field] in the minimum app scaffolding a TextFormField needs.
Widget _host(Widget field) => MaterialApp(
      home: Scaffold(body: Material(child: Center(child: field))),
    );

void main() {
  group('UnitSuffix inside AppTextField', () {
    testWidgets('renders the unit label next to the input', (tester) async {
      await tester.pumpWidget(_host(AppTextField(
        label: 'Stock',
        controller: TextEditingController(text: '12'),
        suffixIcon: const UnitSuffix('kg'),
      )));

      expect(find.text('kg'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('a long unit label does not overflow', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 200,
        child: AppTextField(
          label: 'Low stock alert',
          controller: TextEditingController(),
          suffixIcon: const UnitSuffix('kilograms-per-crate'),
        ),
      )));

      // An overflowing Text paints an error stripe and trips tester's
      // exception check; reaching here with none means it ellipsized instead.
      expect(tester.takeException(), isNull);
    });

    testWidgets('adding a suffix leaves the field height unchanged',
        (tester) async {
      // Measure the InputDecorator's own box: it is the widget that grows when
      // a suffix is taller than the text line, and unlike the enclosing
      // TextFormField it is laid out tightly in both cases.
      Future<double> heightOf(Widget? suffix) async {
        await tester.pumpWidget(_host(SizedBox(
          width: 240,
          child: AppTextField(
            label: 'Stock',
            controller: TextEditingController(),
            suffixIcon: suffix,
          ),
        )));
        return tester.getSize(find.byType(InputDecorator)).height;
      }

      final bare = await heightOf(null);
      final withSuffix = await heightOf(const UnitSuffix('kg'));

      expect(withSuffix, bare);
    });
  });
}
