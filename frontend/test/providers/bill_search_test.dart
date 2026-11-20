import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/bills_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bill = Bill.fromJson({
    'id': 'b1',
    'bill_number': 'INV-0012',
    'customer_name': 'Ravi',
    'customer_phone': '9876543210',
    'warranty_extra_data': [
      {'label': 'Vehicle No', 'value': 'MH07AB1234'},
    ],
    'subtotal': 100,
    'tax_amount': 0,
    'total': 100,
    'payment_mode': 'cash',
    'status': 'finalized',
    'created_at': '2026-11-16T10:00:00Z',
    'items': [],
  });

  test('history search matches number, customer, label and value', () {
    for (final q in [null, '', '0012', 'ravi', '98765', 'vehicle', 'mh07ab']) {
      expect(billMatchesSearch(bill, q), isTrue, reason: '$q');
    }
    expect(billMatchesSearch(bill, 'kolhapur'), isFalse);
  });

  test('typing a search never moves the date range (no refetch); presets '
      'still set the range and keep the search', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(billFilterProvider.notifier);
    var rangeChanges = 0;
    c.listen(billFilterProvider.select((f) => (f.from, f.to)),
        (_, __) => rangeChanges++);

    final today = c.read(billFilterProvider);
    expect(today.preset, BillDatePreset.today);
    expect(today.from, today.to);

    n.setSearch('mh07');
    n.setSearch('');
    n.setSearch('ravi');
    expect(rangeChanges, 0);

    n.setPreset(BillDatePreset.yesterday);
    final y = c.read(billFilterProvider);
    expect(rangeChanges, 1);
    expect(y.from, today.from.subtract(const Duration(days: 1)));
    expect(y.search, 'ravi');

    n.setDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
    final custom = c.read(billFilterProvider);
    expect(custom.preset, BillDatePreset.custom);
    expect(custom.from, DateTime(2026, 1, 1));
    expect(custom.search, 'ravi');
  });
}
