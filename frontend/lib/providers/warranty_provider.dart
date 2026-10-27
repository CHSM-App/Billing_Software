import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;
import '../models/models.dart';

/// Every item category's custom warranty fields for this business, keyed by
/// category (migration 063 / routes/warranty_field_templates.js). The
/// Warranty screen reads this once a record's category is known, to render
/// the right extra inputs; the Items screen's template editor writes it.
class WarrantyFieldTemplatesNotifier
    extends AsyncNotifier<Map<String, WarrantyFieldTemplate>> {
  @override
  Future<Map<String, WarrantyFieldTemplate>> build() => _fetch();

  Future<Map<String, WarrantyFieldTemplate>> _fetch() async {
    final raw = await api.getWarrantyFieldTemplates();
    final templates = raw
        .map((j) => WarrantyFieldTemplate.fromJson(j as Map<String, dynamic>))
        .toList();
    return {for (final t in templates) t.category: t};
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> save(String category, List<WarrantyTemplateField> fields) async {
    await api.putWarrantyFieldTemplate(
      category,
      fields
          .map((f) => {'key': f.key, 'label': f.label, 'type': f.type})
          .toList(),
    );
    await reload();
  }

  Future<void> remove(String category) async {
    await api.deleteWarrantyFieldTemplate(category);
    await reload();
  }
}

final warrantyFieldTemplatesProvider = AsyncNotifierProvider<
    WarrantyFieldTemplatesNotifier, Map<String, WarrantyFieldTemplate>>(
  WarrantyFieldTemplatesNotifier.new,
);

/// Bumped whenever a bill carrying a warranty-eligible item is finalized
/// online, so the Warranty tab (kept alive in the shell's IndexedStack, not
/// rebuilt on tab switch) can refresh itself immediately instead of only on
/// a manual pull-to-refresh. A plain counter, not the warranty data itself —
/// the Warranty screen still owns its own paginated/filtered fetch; this is
/// only a "something changed, re-fetch" signal.
final warrantyRefreshSignalProvider = StateProvider<int>((ref) => 0);
