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
            unit: it.unit,
            currentStock: v.stockQuantity,
            lowStockThreshold: v.lowStockThreshold,
            variantId: v.id,
            hsnCode: it.hsnCode,
            taxRate: it.taxRate,
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
                                  'In stock: ${_fmtQty(r.currentStock!)} ${r.unit}')
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
