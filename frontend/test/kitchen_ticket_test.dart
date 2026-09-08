import 'package:flutter/material.dart' show TextAlign;
import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/services/kitchen_ticket.dart';
import 'package:Vittam/services/raster_lab.dart';

/// One entry as `GET /api/kitchen/orders` returns it.
Map<String, dynamic> _order({
  Object? table = '5',
  Object? customer,
  List<Map<String, dynamic>>? items,
}) =>
    {
      'id': 'abc',
      'bill_number': 'INV-0026',
      'table_number': table,
      'customer_name': customer,
      'created_at': '2026-09-08T10:01:00.000Z',
      'items': items ??
          [
            {'item_name': 'Cream of Mushroom Soup', 'quantity': 2},
            {'item_name': 'Butter Naan', 'quantity': 4},
          ],
    };

/// Every cell's text, flattened — for "does the slip say X anywhere" checks.
String _text(List<ReceiptRow> rows) =>
    rows.expand((r) => r.cells).map((c) => c.text).join('\n');

/// The rows that carry a dish (two columns: quantity + name).
List<ReceiptRow> _dishRows(List<ReceiptRow> rows) =>
    rows.where((r) => !r.isRule && !r.isCenter && r.cells.length == 2).toList();

void main() {
  group('KitchenTicket', () {
    test('every multi-column row fills exactly the paper width', () {
      // The bug this guards: cells whose fractions do not sum to 1 leave the
      // renderer short of width, which is how a slip ends up re-wrapped and
      // unreadable.
      for (final r in _order()
          .let(KitchenTicket.build)
          .where((r) => !r.isRule && !r.isCenter)) {
        final sum = r.cells.fold<double>(0, (s, c) => s + c.widthFraction);
        expect(sum, closeTo(1.0, 0.0001), reason: 'row does not fill the roll');
      }
    });

    test('quantity leads each dish in its own right-aligned column', () {
      final dishes = _dishRows(KitchenTicket.build(_order()));
      expect(dishes.first.cells.first.text, '2 x');
      expect(dishes.first.cells.first.align, TextAlign.right);
      expect(dishes.first.cells.last.text, 'Cream of Mushroom Soup');
    });

    test('the destination is the largest thing on the slip', () {
      final rows = KitchenTicket.build(_order());
      final destination =
          rows.firstWhere((r) => r.cells.any((c) => c.text == 'TABLE 5'));
      final biggest =
          rows.map((r) => r.size).reduce((a, b) => a > b ? a : b);
      expect(destination.size, biggest);
      expect(destination.bold, isTrue);
    });

    test('dishes are set larger than the administrative lines', () {
      final rows = KitchenTicket.build(_order());
      final dish = _dishRows(rows).first;
      final billNo =
          rows.firstWhere((r) => r.cells.any((c) => c.text == 'INV-0026'));
      expect(dish.size, greaterThan(billNo.size));
      expect(dish.bold, isTrue);
    });

    test('never prints money', () {
      // A cook prices nothing, and a ticket with totals gets handed over as a
      // bill. Guards against someone later reusing the receipt row builder.
      final t = _text(KitchenTicket.build(_order()));
      expect(t, isNot(contains('₹')));
      expect(t, isNot(contains('Rs')));
      expect(t, isNot(contains('Total')));
    });

    test('says where the food goes — table, else customer, else parcel', () {
      expect(_text(KitchenTicket.build(_order())), contains('TABLE 5'));

      final takeaway =
          _text(KitchenTicket.build(_order(table: null, customer: 'Rahul')));
      expect(takeaway, contains('RAHUL'));
      expect(takeaway, isNot(contains('TABLE')));

      expect(_text(KitchenTicket.build(_order(table: null))),
          contains('PARCEL'));
    });

    test('a long dish name is passed through whole, for the cell to wrap', () {
      // Nothing may be truncated — a kitchen cannot cook "Paneer Butter Mas…".
      const long = 'Paneer Butter Masala With Extra Gravy';
      final dishes = _dishRows(
          KitchenTicket.build(_order(items: [
        {'item_name': long, 'quantity': 1}
      ])));
      expect(dishes.single.cells.last.text, long);
    });

    test('shows quantities as counts, keeping fractions for weighed items', () {
      final t = _text(KitchenTicket.build(_order(items: [
        {'item_name': 'Mutton', 'quantity': 1.5},
        {'item_name': 'Roti', 'quantity': 3.0},
      ])));
      expect(t, contains('1.5 x'));
      expect(t, contains('3 x')); // not "3.0 x"
      expect(t, contains('4.5 item(s)'));
    });

    test('attributes a self-ordered dish to the diner', () {
      final t = _text(KitchenTicket.build(_order(items: [
        {'item_name': 'Cold Coffee', 'quantity': 1, 'diner_name': 'Priya'}
      ])));
      expect(t, contains('Priya'));
    });

    test('one diner ordering several dishes is named once, not per line', () {
      final t = _text(KitchenTicket.build(_order(items: [
        {'item_name': 'Chicken Handi', 'quantity': 3, 'diner_name': 'Sagar'},
        {'item_name': 'Butter Chicken', 'quantity': 4, 'diner_name': 'Sagar'},
        {'item_name': 'Butter Naan', 'quantity': 6, 'diner_name': 'Sagar'},
      ])));
      expect('Sagar'.allMatches(t).length, 1);
      // Named above the dishes, not hung off the first one.
      expect(t, isNot(contains('- Sagar')));
    });

    test('a table split between diners still attributes every run', () {
      final t = _text(KitchenTicket.build(_order(items: [
        {'item_name': 'Cold Coffee', 'quantity': 1, 'diner_name': 'Priya'},
        {'item_name': 'Butter Naan', 'quantity': 2, 'diner_name': 'Priya'},
        {'item_name': 'Chicken Handi', 'quantity': 1, 'diner_name': 'Sagar'},
      ])));
      // Once each: Priya heads her run, Sagar heads his.
      expect('- Priya'.allMatches(t).length, 1);
      expect('- Sagar'.allMatches(t).length, 1);
    });

    test('a counter order with no diner names prints no attribution', () {
      final t = _text(KitchenTicket.build(_order()));
      expect(t, isNot(contains('- ')));
    });

    test('marks a reprint so a duplicate slip is not cooked twice', () {
      expect(_text(KitchenTicket.build(_order())), isNot(contains('REPRINT')));
      expect(_text(KitchenTicket.build(_order(), reprint: true)),
          contains('(REPRINT)'));
    });

    test('an order with no or malformed items still prints a usable slip', () {
      expect(_text(KitchenTicket.build(_order(items: []))),
          allOf(contains('TABLE 5'), contains('0 item(s)')));
      // A missing items key must not throw — a ticket that throws never prints.
      expect(() => KitchenTicket.build({'table_number': '2'}), returnsNormally);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
