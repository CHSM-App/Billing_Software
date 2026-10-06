import 'package:Vittam/screens/customers_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server does the filtering (GET /api/customers); these pin the query the
/// app sends for each filter, so the screen and the backend agree.
void main() {
  test('no filter sends only the default sort', () {
    expect(customerListParams(), {'sort': 'spend', 'dir': 'desc'});
  });

  test('ranges, recency and offers map to the server parameter names', () {
    const f = CustomerFilter(
      minVisits: 2,
      maxVisits: 10,
      minSpend: 500,
      maxSpend: 2500.5,
      recency: CustomerRecency.inactive30,
      offers: CustomerOffers.optedOut,
    );
    expect(f.toQuery(), {
      'min_visits': '2',
      'max_visits': '10',
      'min_spend': '500',
      'max_spend': '2500.5',
      'recency': 'inactive30',
      'offers': 'opted_out',
    });
  });

  test('"receiving offers" is sent as allowed; "all" sends nothing', () {
    expect(const CustomerFilter(offers: CustomerOffers.allowed).toQuery(),
        {'offers': 'allowed'});
    expect(const CustomerFilter(offers: CustomerOffers.all).toQuery(), isEmpty);
  });

  test('search is trimmed and sent as q; blank search is not sent', () {
    expect(customerListParams(query: '  Asha ')['q'], 'Asha');
    expect(customerListParams(query: '   ').containsKey('q'), isFalse);
  });

  test('sort field and direction', () {
    expect(customerListParams(sort: CustomerSort.name, descending: false),
        {'sort': 'name', 'dir': 'asc'});
    expect(customerListParams(sort: CustomerSort.recent),
        {'sort': 'recent', 'dir': 'desc'});
  });

  test('active count drives the Filters badge; filters compare by value', () {
    expect(CustomerFilter.none.activeCount, 0);
    expect(
        const CustomerFilter(minVisits: 2, offers: CustomerOffers.allowed)
            .activeCount,
        2);
    expect(const CustomerFilter(minVisits: 5), const CustomerFilter(minVisits: 5));
    expect(const CustomerFilter(minVisits: 5) == CustomerFilter.none, isFalse);
  });
}
