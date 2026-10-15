import 'package:Vittam/models/models.dart';
import 'package:Vittam/providers/open_drafts_provider.dart';
import 'package:Vittam/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SessionNotifier {
  _Session(this.m);
  final Map<String, dynamic> m;
  @override
  Future<SessionData> build() async => SessionData.fromMap(m);
}

class _Drafts extends OpenDraftsNotifier {
  _Drafts(this.drafts);
  final List<Bill> drafts;
  @override
  Future<List<Bill>> build() async => drafts;
}

Bill _draft(String id, List<String?> statuses) => Bill(
      id: id,
      businessId: 'b',
      billNumber: id,
      subtotal: 0,
      taxAmount: 0,
      total: 0,
      paymentMode: 'cash',
      status: 'draft',
      createdByUserId: 'u',
      createdAt: DateTime(2026, 10, 15),
      items: [
        for (var i = 0; i < statuses.length; i++)
          BillItem(
              id: '$id-$i',
              billId: id,
              itemName: 'Dish $i',
              quantity: 1,
              unitPrice: 0,
              lineTotal: 0,
              kitchenStatus: statuses[i]),
      ],
    );

void main() {
  group('show_item_no session flag', () {
    test('fromMap: only a real true turns it on', () {
      expect(SessionData.fromMap({'show_item_no': true}).showItemNo, isTrue);
      expect(SessionData.fromMap({'show_item_no': false}).showItemNo, isFalse);
      expect(SessionData.fromMap({'show_item_no': 1}).showItemNo, isFalse);
      // Session saved before the flag existed.
      expect(SessionData.fromMap({}).showItemNo, isFalse);
      expect(SessionData.empty().showItemNo, isFalse);
    });

    test('showItemNoProvider follows the session, false while loading', () async {
      final c = ProviderContainer(overrides: [
        sessionProvider.overrideWith(() => _Session({'show_item_no': true})),
      ]);
      addTearDown(c.dispose);
      expect(c.read(showItemNoProvider), isFalse);
      await c.read(sessionProvider.future);
      expect(c.read(showItemNoProvider), isTrue);
    });
  });

  group('openOrdersReadyCountProvider', () {
    Future<int> count(List<Bill> drafts) async {
      final c = ProviderContainer(overrides: [
        openDraftsProvider.overrideWith(() => _Drafts(drafts)),
      ]);
      addTearDown(c.dispose);
      await c.read(openDraftsProvider.future);
      return c.read(openOrdersReadyCountProvider);
    }

    test('counts ready dishes across all open orders', () async {
      expect(
          await count([
            _draft('a', ['ready', 'pending', 'ready']),
            _draft('b', ['delivered', 'ready', null]),
          ]),
          3);
    });

    test('pending, delivered and unknown dishes do not count', () async {
      expect(await count([_draft('a', ['pending', 'delivered', null])]), 0);
    });

    test('no open orders → 0', () async {
      expect(await count([]), 0);
    });

    test('0 while the list is still loading', () {
      final c = ProviderContainer(overrides: [
        openDraftsProvider.overrideWith(() => _Drafts([_draft('a', ['ready'])])),
      ]);
      addTearDown(c.dispose);
      expect(c.read(openOrdersReadyCountProvider), 0);
    });
  });
}
