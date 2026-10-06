import 'dart:async';

import 'package:Vittam/l10n/app_localizations.dart';
import 'package:Vittam/models/models.dart';
import 'package:Vittam/screens/customers_screen.dart';
import 'package:Vittam/theme/app_theme.dart';
import 'package:Vittam/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app theme gives Elevated/Outlined buttons an infinitely wide
/// minimumSize. Placed in a Row, such a button fails layout and the WHOLE page
/// renders blank — which is exactly what tapping a customer did (the "Stop
/// offers" button sits in a Row). Rendered here against the real theme.
Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

final _customerJson = {
  'id': 'c-1',
  'name': 'Asha',
  'phone': '9876543210',
  'opted_out': false,
  'bill_count': 2,
  'total_spend': 450,
  'last_visit': '2026-10-01T10:00:00Z',
};

Map<String, dynamic> _bill(String id, String number) => {
      'id': id,
      'business_id': 'b-1',
      'bill_number': number,
      'customer_name': 'Asha',
      'customer_phone': '9876543210',
      'subtotal': 200,
      'tax_amount': 0,
      'discount_amount': 0,
      'charges_amount': 0,
      'additional_charges': [],
      'total': 200,
      'round_off': 0,
      'payment_mode': 'cash',
      'payment_status': 'paid',
      'status': 'finalized',
      'created_by_user_id': 'u-1',
      'created_at': '2026-10-01T10:00:00Z',
      'items': [
        {
          'id': 'i-$id', 'bill_id': id, 'item_id': 'it-1', 'item_name': 'Tea',
          'quantity': 2, 'unit_price': 100, 'tax_rate': 0, 'line_total': 200,
        },
      ],
    };

/// Stands in for GET /api/customers: applies min/max visits, pages by
/// offset/limit and returns the same counts the server does. Records every
/// request so tests can check what the screen asked for.
class _FakeCustomersApi {
  final List<Map<String, dynamic>> rows;
  final requests = <Map<String, String>>[];
  _FakeCustomersApi(this.rows);

  List<Map<String, dynamic>> _match(Map<String, String> p) => rows.where((r) {
        final v = r['bill_count'] as int;
        final min = int.tryParse(p['min_visits'] ?? '');
        final max = int.tryParse(p['max_visits'] ?? '');
        return (min == null || v >= min) && (max == null || v <= max);
      }).toList();

  Future<Map<String, dynamic>> list(Map<String, String> p) async {
    requests.add(p);
    final m = _match(p);
    final offset = int.tryParse(p['offset'] ?? '') ?? 0;
    final limit = int.tryParse(p['limit'] ?? '') ?? 30;
    return {
      'items': m.skip(offset).take(limit).toList(),
      'total': m.length,
      'total_all': rows.length,
      'total_eligible': m.where((r) => r['opted_out'] != true).length,
    };
  }

  Future<List<String>> ids(Map<String, String> p) async =>
      _match(p).where((r) => r['opted_out'] != true).map((r) => r['id'] as String).toList();
}

Map<String, dynamic> _cust(int i, {int visits = 2}) => {
      ..._customerJson,
      'id': 'c-$i',
      'name': 'Customer $i',
      'phone': '98765${i.toString().padLeft(5, '0')}',
      'bill_count': visits,
    };

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a customer’s page shows their bills (no blank page)',
      (tester) async {
    await tester.pumpWidget(_app(CustomerBillsScreen(
      customer: Customer.fromJson(_customerJson),
      loadBills: (_, {offset = 0, limit = 20}) async => {
        'items': [_bill('b1', 'INV-0001'), _bill('b2', 'INV-0002')],
        'total': 2,
      },
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('INV-0001'), findsOneWidget);
    expect(find.text('INV-0002'), findsOneWidget);
    expect(find.text('Stop offers'), findsOneWidget);
  });

  testWidgets('a customer’s bills load page by page as you scroll',
      (tester) async {
    final all = [for (var i = 1; i <= 45; i++) _bill('b$i', 'INV-${i.toString().padLeft(4, '0')}')];
    final offsets = <int>[];
    await tester.pumpWidget(_app(CustomerBillsScreen(
      customer: Customer.fromJson(_customerJson),
      loadBills: (_, {offset = 0, limit = 20}) async {
        offsets.add(offset);
        return {'items': all.skip(offset).take(limit).toList(), 'total': all.length};
      },
    )));
    await tester.pumpAndSettle();
    expect(offsets, [0]);
    expect(find.text('INV-0045'), findsNothing);

    // Scroll to the end until every page is in.
    for (var i = 0; i < 10 && offsets.length < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    expect(offsets, [0, 20, 40]);
    await tester.dragUntilVisible(find.text('INV-0045'), find.byType(ListView),
        const Offset(0, -500));
    expect(find.text('INV-0045'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skeletons show while loading, then give way to the data',
      (tester) async {
    final customers = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_app(CustomersScreen(
      loadCustomers: (_) => customers.future,
      loadIds: (_) async => const [],
    )));
    await tester.pump();
    expect(find.byType(CustomersSkeleton), findsOneWidget);

    customers.complete(await _FakeCustomersApi([_customerJson]).list(const {}));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersSkeleton), findsNothing);
    expect(find.text('Asha'), findsOneWidget);

    // A customer's bills: real header at once, skeleton rows until they load.
    final bills = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_app(CustomerBillsScreen(
      customer: Customer.fromJson(_customerJson),
      loadBills: (_, {offset = 0, limit = 20}) => bills.future,
    )));
    await tester.pump();
    expect(find.byType(CustomerBillsSkeleton), findsOneWidget);
    expect(find.text('Stop offers'), findsOneWidget);

    bills.complete({'items': [_bill('b1', 'INV-0001')], 'total': 1});
    await tester.pumpAndSettle();
    expect(find.byType(CustomerBillsSkeleton), findsNothing);
    expect(find.text('INV-0001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a customer shows the Next bar without breaking layout',
      (tester) async {
    final api = _FakeCustomersApi([_customerJson]);
    await tester.pumpWidget(_app(CustomersScreen(loadCustomers: api.list, loadIds: api.ids)));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('the list pages as you scroll; Select all covers every page',
      (tester) async {
    final api = _FakeCustomersApi([for (var i = 1; i <= 70; i++) _cust(i)]);
    await tester.pumpWidget(_app(CustomersScreen(loadCustomers: api.list, loadIds: api.ids)));
    await tester.pumpAndSettle();

    expect(api.requests.single, containsPair('offset', '0'));
    expect(find.text('70 of 70 customers'), findsOneWidget);

    for (var i = 0; i < 10 && api.requests.length < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();
    }
    expect(api.requests.map((r) => r['offset']), ['0', '30', '60']);

    // Select all picks all 70, not just what is loaded on screen.
    await tester.tap(find.text('Select all (70)'));
    await tester.pumpAndSettle();
    expect(find.text('70 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters go to the server; the sheet shows its live count',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = _FakeCustomersApi([
      {..._cust(1, visits: 7), 'name': 'Asha'},
      {..._cust(2, visits: 1), 'name': 'Bala'},
    ]);
    await tester.pumpWidget(_app(CustomersScreen(loadCustomers: api.list, loadIds: api.ids)));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 customers'), findsOneWidget);

    // Filters sheet: at least 5 visits → server count → apply.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Min').first, '5');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();
    expect(api.requests.last, containsPair('limit', '0')); // count-only query
    await tester.tap(find.text('Show 1 customer'));
    await tester.pumpAndSettle();

    expect(api.requests.last, containsPair('min_visits', '5'));
    expect(find.text('1 of 2 customers'), findsOneWidget);
    expect(find.text('Bala'), findsNothing);
    expect(find.text('Visits: 5+'), findsOneWidget); // active chip

    // Remove it from its chip → back to everyone.
    await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'Visits: 5+'),
        matching: find.byTooltip('Delete')));
    await tester.pumpAndSettle();
    expect(api.requests.last.containsKey('min_visits'), isFalse);
    expect(find.text('2 of 2 customers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
