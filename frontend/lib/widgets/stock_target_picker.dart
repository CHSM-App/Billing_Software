import 'package:flutter/material.dart';

import '../models/models.dart';
import 'app_widgets.dart';

/// Something a purchase can be received into: a plain item, one size/variant
/// of an item, or a raw material. Exactly one of [itemId], [variantId] or
/// [rawMaterialId] is set — the server rejects a line that names more than
/// one target.
class StockTarget {
  final String name;
  final String unit;
  final double? currentStock;
  final double? lowStockThreshold;
  final String? itemId;
  final String? variantId;
  final String? rawMaterialId;

  /// Carried through from the item so a purchase line can be pre-filled.
  final String? hsnCode;
  final double? taxRate;

  /// The item's or size's pack ("1 box = 15"), so a purchase can be typed in
  /// boxes. Null for raw materials and unpacked items.
  final String? packUnit;
  final double? packSize;

  const StockTarget({
    required this.name,
    required this.unit,
    this.currentStock,
    this.lowStockThreshold,
    this.itemId,
    this.variantId,
    this.rawMaterialId,
    this.hsnCode,
    this.taxRate,
    this.packUnit,
    this.packSize,
  }) : assert(
          (itemId != null ? 1 : 0) +
                  (variantId != null ? 1 : 0) +
                  (rawMaterialId != null ? 1 : 0) ==
              1,
          'A StockTarget must name exactly one of item, variant or raw material',
        );

  bool get isLowStock =>
      currentStock != null &&
      lowStockThreshold != null &&
      currentStock! <= lowStockThreshold!;
}

bool isRestaurantBusiness(String businessType) =>
    businessType == 'restaurant_with_tables' ||
    businessType == 'restaurant_no_tables';

/// Flattens the stock-tracked things a business can buy into pickable rows.
///
/// Restaurants buy raw materials (buns, patties); everyone else buys the items
/// they sell, with a sized item contributing one row per variant (named
/// "Item (Size)") rather than a row for the parent, since stock lives on the
/// variants once any exist.
List<StockTarget> buildStockTargets({
  required bool isRestaurant,
  required List<Item> items,
  required List<RawMaterial> materials,
  Set<String> exclude = const {},
}) {
  final out = <StockTarget>[];
  if (isRestaurant) {
    for (final m in materials) {
      if (exclude.contains(m.name)) continue;
      out.add(StockTarget(
        name: m.name,
        unit: m.unit,
        currentStock: m.stockQuantity,
        lowStockThreshold: m.lowStockThreshold,
        rawMaterialId: m.id,
      ));
    }
  } else {
    for (final it in items) {
      if (it.hasVariants) {
        for (final v in it.variants) {
          final name = '${it.name} (${v.label})';
          if (exclude.contains(name)) continue;
          out.add(StockTarget(
            name: name,
            unit: v.unit ?? it.unit,
            currentStock: v.stockQuantity,
            lowStockThreshold: v.lowStockThreshold,
            variantId: v.id,
            hsnCode: it.hsnCode,
            taxRate: it.taxRate,
            packUnit: v.packUnit,
            packSize: v.packSize,
          ));
        }
      } else if (!exclude.contains(it.name)) {
        out.add(StockTarget(
          name: it.name,
          unit: it.unit,
          currentStock: it.stockQuantity,
          lowStockThreshold: it.lowStockThreshold,
          itemId: it.id,
          hsnCode: it.hsnCode,
          taxRate: it.taxRate,
          packUnit: it.packUnit,
          packSize: it.packSize,
        ));
      }
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// Case-insensitive exact-name lookup, used to re-link rows that only carry a
/// name (e.g. those recovered from a purchase-list PDF).
StockTarget? findStockTargetByName(List<StockTarget> targets, String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final t in targets) {
    if (t.name.toLowerCase() == key) return t;
  }
  return null;
}

// Count words that carry no meaning of their own.
const _noiseWords = {'pc', 'pcs', 'nos', 'no', 'x'};

// One spelling per unit, so "1 LTR" and "1L" are the same size.
const _unitSpelling = {
  'kgs': 'kg', 'gms': 'g', 'gm': 'g', 'ltr': 'l', 'lt': 'l', 'litre': 'l',
};

/// [s] split into numbers ("how much / which size") and words ("what").
/// A number stays glued to its unit ("1 kg" → "1kg") and a tyre's rim to its
/// R ("195/60R15" → "195", "60", "r15"), so the same size reads the same
/// however the bill spaces it.
({Set<String> sizes, Set<String> words}) _tokens(String s) {
  final norm = s
      .toLowerCase()
      .replaceAllMapped(RegExp(r'(\d)\s*(kgs|kg|gms|gm|g|ml|litre|ltr|lt|l)\b'),
          (m) => '${m[1]}${_unitSpelling[m[2]] ?? m[2]}')
      .replaceAllMapped(
          RegExp(r'(\d)\s*z?r\s*(\d{2})\b'), (m) => '${m[1]} r${m[2]}');
  final sizes = <String>{};
  final words = <String>{};
  for (final t in norm.split(RegExp(r'[^a-z0-9.]+'))) {
    if (t.isEmpty || _noiseWords.contains(t)) continue;
    if (RegExp(r'^(\d+(\.\d+)?[a-z]*|r\d+)$').hasMatch(t)) {
      sizes.add(t);
    } else if (t.length >= 2) {
      words.add(t.replaceAll('.', ''));
    }
  }
  return (sizes: sizes, words: words);
}

/// Up to [max] targets that fit [text] — e.g. a supplier's "PARLE-G BISCUIT
/// 50G" suggests "Parle G Biscuit". Numbers are the identity of a tyre or a
/// pack, so a target with a number the line doesn't have is never offered
/// ("215/65 R16" never suggests "255/65 R16"); the rest is shared words. Only
/// a suggestion for the owner to tap; never used to link on its own.
// ponytail: word overlap, no typo tolerance ("Biscut" won't match); add
// edit distance if owners report misses.
List<StockTarget> suggestStockTargets(List<StockTarget> targets, String text,
    {int max = 3}) {
  final line = _tokens(text);
  // Bills run words together ("TATASALT"); a longer item word found inside
  // the squashed text counts too. Short words don't — "oil" is in "boiled".
  final joined = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  if (joined.isEmpty) return const [];
  final scored = <(StockTarget, double)>[];
  for (final t in targets) {
    final own = _tokens(t.name);
    final total = own.sizes.length + own.words.length;
    if (total == 0) continue;
    if (line.sizes.isNotEmpty && !own.sizes.every(line.sizes.contains)) continue;
    final hits = own.sizes.where(line.sizes.contains).length +
        own.words
            .where((w) =>
                line.words.contains(w) || (w.length >= 4 && joined.contains(w)))
            .length;
    final score = hits / total;
    if (score >= 0.5) scored.add((t, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored.take(max)) s.$1];
}

/// Opens the searchable bottom sheet and returns the chosen target, or null
/// when dismissed.
Future<StockTarget?> showStockTargetPicker(
    BuildContext context, List<StockTarget> candidates) {
  return showModalBottomSheet<StockTarget>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _StockTargetPickerSheet(candidates: candidates),
  );
}

String _fmtQty(double q) =>
    q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

/// Bottom sheet listing candidates, filterable by name. Candidates are
/// pre-built by the caller via [buildStockTargets], so this sheet doesn't need
/// to know whether they came from items or raw materials.
class _StockTargetPickerSheet extends StatefulWidget {
  final List<StockTarget> candidates;
  const _StockTargetPickerSheet({required this.candidates});

  @override
  State<_StockTargetPickerSheet> createState() =>
      _StockTargetPickerSheetState();
}

class _StockTargetPickerSheetState extends State<_StockTargetPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.candidates;
    final filtered = _query.isEmpty
        ? rows
        : rows
            .where((r) => r.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search items',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No items found')
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        return ListTile(
                          title: Text(r.name),
                          subtitle: r.currentStock != null
                              ? Text(
                                  'In stock: ${_fmtQty(r.currentStock!)} ${unitShort(r.unit)}')
                              : null,
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
