import 'package:Vittam/providers/items_provider.dart';
import 'package:Vittam/providers/major_category_order_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The billing screen's major-category chip strip reads its order from here.
/// Two behaviours matter: a business that never touched drag-reorder gets
/// plain alphabetical (categoryTreeProvider's own order), and a saved order
/// must survive the catalog changing under it — a renamed/deleted major drops
/// out, a brand new one is appended rather than lost.
class _FakeCategoryTree extends CategoryTreeNotifier {
  _FakeCategoryTree(this._tree);
  final Map<String, List<String>> _tree;

  @override
  Future<Map<String, List<String>>> build() async => _tree;
}

const _businessId = 'biz-1';

Map<String, List<String>> _tree(List<String> majors) =>
    {for (final m in majors) m: const <String>[]};

ProviderContainer _containerWith(List<String> majors) {
  final c = ProviderContainer(overrides: [
    categoryTreeProvider.overrideWith(() => _FakeCategoryTree(_tree(majors))),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MajorCategoryOrderNotifier — no saved order', () {
    test('falls back to categoryTreeProvider\'s own (alphabetical) order',
        () async {
      SharedPreferences.setMockInitialValues({'business_id': _businessId});
      final c = _containerWith(['Veg', 'Bar', 'Beverages']);
      final result = await c.read(majorCategoryOrderProvider.future);
      // categoryTreeProvider already sorts, so the fake supplies it pre-sorted
      // exactly as the real notifier would.
      expect(result, ['Veg', 'Bar', 'Beverages']);
    });

    test('the "" (no major set) bucket never reaches the list', () async {
      SharedPreferences.setMockInitialValues({'business_id': _businessId});
      final c = ProviderContainer(overrides: [
        categoryTreeProvider.overrideWith(
            () => _FakeCategoryTree({'': [], 'Veg': []})),
      ]);
      addTearDown(c.dispose);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Veg']);
    });
  });

  group('MajorCategoryOrderNotifier — saved order', () {
    test('applies the saved order over the alphabetical one', () async {
      SharedPreferences.setMockInitialValues({
        'business_id': _businessId,
        'major_category_order_$_businessId': '["Bar","Beverages","Veg"]',
      });
      final c = _containerWith(['Bar', 'Beverages', 'Veg']);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Bar', 'Beverages', 'Veg']);
    });

    test('a major renamed/deleted since saving is dropped, not left as a '
        'stale entry', () async {
      SharedPreferences.setMockInitialValues({
        'business_id': _businessId,
        'major_category_order_$_businessId':
            '["Bar","Discontinued","Veg"]',
      });
      final c = _containerWith(['Bar', 'Veg']);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Bar', 'Veg']);
    });

    test('a major added since saving lands at the end', () async {
      SharedPreferences.setMockInitialValues({
        'business_id': _businessId,
        'major_category_order_$_businessId': '["Bar","Veg"]',
      });
      final c = _containerWith(['Bar', 'Beverages', 'Veg']);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Bar', 'Veg', 'Beverages']);
    });

    test('corrupt saved JSON falls back to alphabetical instead of failing',
        () async {
      SharedPreferences.setMockInitialValues({
        'business_id': _businessId,
        'major_category_order_$_businessId': 'not valid json',
      });
      final c = _containerWith(['Bar', 'Veg']);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Bar', 'Veg']);
    });

    test('no cached business id yet falls back to alphabetical', () async {
      // getBusinessId() reads nothing when no session has been saved.
      final c = _containerWith(['Bar', 'Veg']);
      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Bar', 'Veg']);
    });
  });

  group('MajorCategoryOrderNotifier.reorder', () {
    test('updates state immediately and persists for the next build',
        () async {
      SharedPreferences.setMockInitialValues({'business_id': _businessId});
      final c = _containerWith(['Bar', 'Beverages', 'Veg']);
      await c.read(majorCategoryOrderProvider.future);

      await c
          .read(majorCategoryOrderProvider.notifier)
          .reorder(['Veg', 'Bar', 'Beverages']);

      expect(c.read(majorCategoryOrderProvider).valueOrNull,
          ['Veg', 'Bar', 'Beverages']);

      // A fresh container simulates the next app launch reading the same
      // persisted preference back.
      final c2 = _containerWith(['Bar', 'Beverages', 'Veg']);
      final reloaded = await c2.read(majorCategoryOrderProvider.future);
      expect(reloaded, ['Veg', 'Bar', 'Beverages']);
    });

    test('survives a rebuild racing the still-in-flight save', () async {
      // Reproduces the real symptom: drag, then immediately navigate away.
      // The screen's onReorder does NOT await reorder() (a drag gesture
      // callback isn't async), so the save is genuinely still in flight when
      // whatever else invalidated categoryTreeProvider (item edits, screen
      // navigation, ...) forces majorCategoryOrderProvider to rebuild. A
      // rebuild that read disk at that exact moment would see the PRE-drag
      // value and silently revert the chip strip.
      SharedPreferences.setMockInitialValues({'business_id': _businessId});
      final c = _containerWith(['Bar', 'Beverages', 'Veg']);
      await c.read(majorCategoryOrderProvider.future);

      // Fire-and-forget, exactly like ReorderableListView's onReorder.
      // ignore: unawaited_futures
      c.read(majorCategoryOrderProvider.notifier).reorder(['Veg', 'Bar', 'Beverages']);

      // Force a rebuild in the same breath, before the write above can have
      // landed on disk.
      c.invalidate(majorCategoryOrderProvider);

      final result = await c.read(majorCategoryOrderProvider.future);
      expect(result, ['Veg', 'Bar', 'Beverages']);
    });
  });
}
