import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../api.dart';

String rawMaterialUnitLabel(BuildContext context, String unit) {
  final l10n = context.l10n;
  switch (unit) {
    case 'kg':
      return l10n.itemsUnitKg;
    case 'g':
      return l10n.itemsUnitGram;
    case 'litre':
      return l10n.itemsUnitLitre;
    case 'ml':
      return l10n.itemsUnitMl;
    default:
      return l10n.itemsUnitPiece;
  }
}

const rawMaterialUnits = ['piece', 'g', 'kg', 'ml', 'litre'];

/// One line in the stock-overview sheet: a product name and its remaining stock.
/// [unitLabel] is the already-localized unit (each tab formats its own units).
class StockOverviewRow {
  final String name;
  final double? stockQuantity;
  final String unitLabel;
  final bool isLowStock;
  const StockOverviewRow({
    required this.name,
    required this.stockQuantity,
    required this.unitLabel,
    this.isLowStock = false,
  });
}

/// A compact stock-overview card (same look as the item/raw-material cards) that
/// shows only a product's name and its remaining stock. Used inline when the
/// stock-overview toggle is on.
Widget buildStockCard(BuildContext context, StockOverviewRow r) {
  final stockStr = r.stockQuantity != null
      ? '${formatQty(r.stockQuantity!)} ${r.unitLabel}'
      : '—';
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: AppColors.border, width: 1),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: r.isLowStock ? AppColors.warning : AppColors.border,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            stockStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: r.isLowStock ? AppColors.warning : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A stock-overview card for an item whose stock is tracked per variant.
/// Shows the item name as a header, then one line per variant with its
/// remaining stock (low-stock variants highlighted).
Widget buildVariantStockCard(
  BuildContext context, {
  required String name,
  required List<StockOverviewRow> variants,
}) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: AppColors.border, width: 1),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.border,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final v in variants)
            Padding(
              padding: const EdgeInsets.only(left: 15, top: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      v.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: v.isLowStock
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    v.stockQuantity != null
                        ? '${formatQty(v.stockQuantity!)} ${v.unitLabel}'
                        : '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: v.isLowStock
                          ? AppColors.warning
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Wraps a card so toggling the stock overview cross-fades and gently scales
/// between the two card variants. [stockMode] keys the transition.
Widget animatedCardSwap(bool stockMode, Widget child) {
  return AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (c, anim) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
        child: c,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(stockMode), child: child),
  );
}

/// Square icon button placed beside a search box to toggle the stock overview.
class StockOverviewButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  const StockOverviewButton(
      {super.key,
      required this.tooltip,
      required this.onTap,
      this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 40,
        width: 40,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(Icons.inventory_2_outlined,
                  size: 20,
                  color: active ? Colors.white : AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The unit a recipe amount is *entered* in for a raw material stocked in
/// [stockUnit], and the factor to multiply the entered amount by to convert it
/// into the stock unit. A material stocked in kg is stocked in bulk but a single
/// plate uses grams, so the recipe is typed in grams (250) and stored as kg
/// (0.25). Litres behave the same via ml. Small units pass through unchanged.
({String unit, double toStock}) recipeEntryUnit(String stockUnit) {
  switch (stockUnit) {
    case 'kg':
      return (unit: 'g', toStock: 0.001);
    case 'litre':
      return (unit: 'ml', toStock: 0.001);
    default:
      return (unit: stockUnit, toStock: 1.0);
  }
}

/// Label for the recipe entry unit, e.g. a kg-stocked material shows "g".
String recipeEntryUnitLabel(BuildContext context, String stockUnit) =>
    rawMaterialUnitLabel(context, recipeEntryUnit(stockUnit).unit);

// ---------------------------------------------------------------------------
// Raw Materials tab — restaurant ingredient inventory. Owner-only. These never
// appear on the billing page; they are consumed by dishes via item recipes.
// ---------------------------------------------------------------------------
class RawMaterialsTab extends ConsumerStatefulWidget {
  const RawMaterialsTab({super.key});

  @override
  ConsumerState<RawMaterialsTab> createState() => _RawMaterialsTabState();
}

class _RawMaterialsTabState extends ConsumerState<RawMaterialsTab> {
  final _searchController = TextEditingController();
  String _search = '';
  bool _showStock = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
        () => setState(() => _search = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RawMaterial> _filtered(List<RawMaterial> all) {
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  Widget _searchBarSliver() => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.space12, 6, AppSpacing.space12, AppSpacing.space4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: context.l10n.itemsSearch,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_outlined,
                          size: 18, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space16, vertical: 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              // Toggle the in-place stock overview.
              StockOverviewButton(
                tooltip: context.l10n.itemsStockOverview,
                active: _showStock,
                onTap: () => setState(() => _showStock = !_showStock),
              ),
            ],
          ),
        ),
      );

  void _showForm(BuildContext context, WidgetRef ref, {RawMaterial? material}) {
    showDialog(
      context: context,
      builder: (_) => RawMaterialFormDialog(
        material: material,
        onSaved: (data) async {
          if (material == null) {
            await ref.read(rawMaterialsProvider.notifier).add(data);
          } else {
            await ref.read(rawMaterialsProvider.notifier).edit(material.id, data);
          }
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RawMaterial m) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.itemsRawMaterialDeleteTitle),
        content: Text(l10n.itemsRawMaterialDeleteBody(m.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(rawMaterialsProvider.notifier).remove(m.id);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(rawMaterialsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () => ref.read(rawMaterialsProvider.notifier).reload(),
      ),
      data: (allMaterials) {
        final materials = _filtered(allMaterials);
        final isWide = MediaQuery.of(context).size.width >= 720;
        return RefreshIndicator(
          onRefresh: () => ref.read(rawMaterialsProvider.notifier).reload(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _searchBarSliver(),
              if (materials.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.egg_alt_outlined,
                    message: allMaterials.isEmpty
                        ? l10n.itemsRawMaterialsEmpty
                        : l10n.itemsNoneFound,
                    actionLabel:
                        allMaterials.isEmpty ? l10n.itemsAddRawMaterial : null,
                    onAction: allMaterials.isEmpty
                        ? () => _showForm(context, ref)
                        : null,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.space8, AppSpacing.space4, AppSpacing.space8, 96),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 1,
                      crossAxisSpacing: AppSpacing.space8,
                      mainAxisSpacing: 6,
                      mainAxisExtent: 52,
                    ),
                    itemCount: materials.length,
                    itemBuilder: (_, i) {
                      final m = materials[i];
                      // Stock overview toggle: same compact card, name + stock.
                      final child = _showStock
                          ? buildStockCard(
                              context,
                              StockOverviewRow(
                                name: m.name,
                                stockQuantity: m.stockQuantity,
                                unitLabel:
                                    rawMaterialUnitLabel(context, m.unit),
                                isLowStock: m.isLowStock,
                              ),
                            )
                          : _buildCard(context, m);
                      return animatedCardSwap(_showStock, child);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Compact card matching the Items tab: colour dot, name + stock subtitle,
  // and a trailing delete action.
  Widget _buildCard(BuildContext context, RawMaterial m) {
    final l10n = context.l10n;
    final stockStr = m.stockQuantity != null
        ? '${formatQty(m.stockQuantity!)} ${rawMaterialUnitLabel(context, m.unit)}'
        : '—';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: InkWell(
          onTap: () => _showForm(context, ref, material: m),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.border,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.itemsStockLabel(stockStr),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (m.isLowStock) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· ${l10n.itemsLowStock}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _delete(context, ref, m),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RawMaterialFormDialog extends StatefulWidget {
  final RawMaterial? material;
  final Future<void> Function(Map<String, dynamic> data) onSaved;

  const RawMaterialFormDialog({super.key, this.material, required this.onSaved});

  @override
  State<RawMaterialFormDialog> createState() => _RawMaterialFormDialogState();
}

class _RawMaterialFormDialogState extends State<RawMaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController();
  String _unit = 'piece';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.material;
    if (m != null) {
      _nameCtrl.text = m.name;
      _stockCtrl.text = m.stockQuantity?.toString() ?? '';
      _thresholdCtrl.text = m.lowStockThreshold?.toString() ?? '';
      _unit = rawMaterialUnits.contains(m.unit) ? m.unit : 'piece';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = {
      'name': _nameCtrl.text.trim(),
      'unit': _unit,
      'stock_quantity': _stockCtrl.text.trim().isNotEmpty
          ? double.parse(_stockCtrl.text.trim())
          : null,
      'low_stock_threshold': _thresholdCtrl.text.trim().isNotEmpty
          ? double.parse(_thresholdCtrl.text.trim())
          : null,
    };
    try {
      await widget.onSaved(data);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.material == null
          ? l10n.itemsAddRawMaterial
          : l10n.itemsEditRawMaterial),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: l10n.itemsFieldName,
                  controller: _nameCtrl,
                  capitalizeWords: true,
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.commonRequired : null,
                ),
                const SizedBox(height: AppSpacing.space12),
                DropdownButtonFormField<String>(
                  value: _unit,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.itemsFieldUnit,
                    prefixIcon: const Icon(Icons.straighten_outlined,
                        size: 18, color: AppColors.textSecondary),
                  ),
                  items: [
                    for (final u in rawMaterialUnits)
                      DropdownMenuItem(
                          value: u, child: Text(rawMaterialUnitLabel(context, u))),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? 'piece'),
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: l10n.itemsFieldStock,
                  controller: _stockCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: l10n.itemsLowStockThreshold,
                  controller: _thresholdCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.material == null ? l10n.commonAdd : l10n.commonSave),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recipe editor — set how much of each raw material a dish consumes per unit.
// Opened from the item form for restaurant businesses. Saving replaces the
// item's whole recipe.
// ---------------------------------------------------------------------------
class RecipeEditorDialog extends ConsumerStatefulWidget {
  final String itemId;
  final String itemName;

  const RecipeEditorDialog(
      {super.key, required this.itemId, required this.itemName});

  @override
  ConsumerState<RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends ConsumerState<RecipeEditorDialog> {
  // raw_material_id -> quantity text controller. Blank/zero means "not used".
  final Map<String, TextEditingController> _ctrls = {};
  // Ordered ids of materials the user has added to the recipe (only these are
  // shown in the list). Search-to-add appends; the remove button drops one.
  final List<String> _selectedIds = [];
  // The Autocomplete's own field focus, captured so we can keep focus on the
  // search box after adding a material (dropdown stays open for the next add).
  FocusNode? _fieldFocus;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Ensure the raw-materials list is available.
      final materials = await ref.read(rawMaterialsProvider.future);
      final recipeRaw = await getItemRecipe(widget.itemId);
      final recipe = recipeRaw
          .map((j) => RecipeRow.fromJson(j as Map<String, dynamic>))
          .toList();
      // Stored quantity is in the material's stock unit; show it in the entry
      // unit (kg -> g, L -> ml) so a plate reads as "250" not "0.25".
      final byId = {for (final r in recipe) r.rawMaterialId: r.quantity};
      for (final m in materials) {
        String text = '';
        if (byId.containsKey(m.id)) {
          final entry = recipeEntryUnit(m.unit);
          text = formatQty(byId[m.id]! / entry.toStock);
          // Already part of the recipe -> show it in the added list.
          _selectedIds.add(m.id);
        }
        _ctrls[m.id] = TextEditingController(text: text);
      }
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = sanitizeUiErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final materials = ref.read(rawMaterialsProvider).valueOrNull ?? [];
    final unitById = {for (final m in materials) m.id: m.unit};
    final rows = <Map<String, dynamic>>[];
    for (final entry in _ctrls.entries) {
      final typed = double.tryParse(entry.value.text.trim());
      if (typed != null && typed > 0) {
        // Convert the entered amount (g/ml) back to the material's stock unit
        // (kg/L) before storing, so deduction math stays in the stock unit.
        final conv = recipeEntryUnit(unitById[entry.key] ?? 'piece');
        rows.add({
          'raw_material_id': entry.key,
          'quantity': typed * conv.toStock,
        });
      }
    }
    setState(() => _saving = true);
    try {
      await setItemRecipe(widget.itemId, rows);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error));
      }
    }
  }

  /* OLD: showed the full materials list inline. Replaced by search-to-add flow
     (only added materials appear in the table). Kept for reference.
  /// Compact, Excel-like table: a header row plus one striped, bordered row
  /// per raw material with an inline quantity cell.
  Widget _buildRecipeTable(BuildContext context, List<RawMaterial> materials) {
    final border = BorderSide(color: AppColors.border, width: 0.5);
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        );

    Widget cell(Widget child, {bool right = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          child: Align(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: 26,
            color: AppColors.border.withOpacity(0.25),
            child: Row(
              children: [
                Expanded(
                    flex: 75,
                    child: cell(Text('Raw material', style: headerStyle))),
                Expanded(
                    flex: 25,
                    child: cell(Text('Quantity', style: headerStyle))),
              ],
            ),
          ),
          if (materials.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No materials found',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < materials.length; i++)
                    Container(
                      decoration: BoxDecoration(
                        color: i.isOdd
                            ? AppColors.border.withOpacity(0.08)
                            : null,
                        border: Border(top: border),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 75,
                              child: cell(Text(materials[i].name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.w500))),
                            ),
                            Expanded(
                              flex: 25,
                              child: Container(
                              decoration: BoxDecoration(
                                border: Border(left: border),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 0),
                              child: TextField(
                                controller: _ctrls[materials[i].id]!,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                textAlign: TextAlign.right,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                                decoration: InputDecoration(
                                  isDense: true,
                                  isCollapsed: true,
                                  hintText: '0',
                                  suffixText: recipeEntryUnitLabel(
                                      context, materials[i].unit),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  END OLD */

  /// Adds a material to the recipe without touching the search field, then
  /// keeps focus on the search box so the (now-filtered) dropdown stays open.
  void _addMaterial(RawMaterial m) {
    if (_selectedIds.contains(m.id)) return;
    setState(() => _selectedIds.add(m.id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fieldFocus?.requestFocus();
    });
  }

  /// Search-to-add box: an autocomplete over all raw materials not yet added.
  /// Shows the full list on focus and filters as the user types; picking an
  /// option appends it to the recipe.
  Widget _buildAddSearch(BuildContext context, List<RawMaterial> materials) {
    return Autocomplete<RawMaterial>(
      displayStringForOption: (m) => m.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return materials.where((m) {
          if (_selectedIds.contains(m.id)) return false; // already added
          return q.isEmpty || m.name.toLowerCase().contains(q);
        });
      },
      // We never route selection through Autocomplete's onSelected (which
      // writes the option name into the field). _addMaterial handles it and
      // leaves the search text untouched.
      onSelected: (_) {},
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        _fieldFocus = focusNode;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search material to add',
            prefixIcon: const Icon(Icons.search, size: 20),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 520),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final m = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(m.name),
                    trailing: Text(recipeEntryUnitLabel(context, m.unit),
                        style: TextStyle(color: AppColors.textSecondary)),
                    onTap: () => _addMaterial(m),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Compact table of the materials the user has added, each with an inline
  /// quantity cell and a remove button.
  Widget _buildSelectedTable(
      BuildContext context, List<RawMaterial> materials) {
    final border = BorderSide(color: AppColors.border, width: 0.5);
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        );
    final byId = {for (final m in materials) m.id: m};

    Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          child: Align(alignment: Alignment.centerLeft, child: child),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: 26,
            color: AppColors.border.withOpacity(0.25),
            child: Row(
              children: [
                Expanded(
                    flex: 60,
                    child: cell(Text('Raw material', style: headerStyle))),
                Expanded(
                    flex: 35,
                    child: cell(Text('Quantity', style: headerStyle))),
                const SizedBox(width: 36),
              ],
            ),
          ),
          if (_selectedIds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No materials added yet',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _selectedIds.length; i++)
                    if (byId[_selectedIds[i]] != null)
                      _selectedRow(context, byId[_selectedIds[i]]!, i, border),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedRow(
      BuildContext context, RawMaterial m, int i, BorderSide border) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: i.isOdd ? AppColors.border.withOpacity(0.08) : null,
        border: Border(top: border),
      ),
      child: Row(
        children: [
          // Name
          Expanded(
            flex: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ),
          // Quantity — a compact filled input cell with padding around it.
          Expanded(
            flex: 35,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _ctrls[m.id]!,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  // Unit shown as placeholder; disappears once a value is typed.
                  hintText: recipeEntryUnitLabel(context, m.unit),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          // Remove
          SizedBox(
            width: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.close, size: 16),
              color: AppColors.textSecondary,
              tooltip: 'Remove',
              onPressed: () {
                setState(() {
                  _selectedIds.remove(m.id);
                  _ctrls[m.id]?.clear(); // don't save a removed material
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materials = ref.watch(rawMaterialsProvider).valueOrNull ?? [];

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Text(l10n.itemsRecipeTitle(widget.itemName),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 560,
        height: MediaQuery.of(context).size.height * 0.7,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppColors.error))
                : materials.isEmpty
                    ? Text(l10n.itemsRecipeNoMaterials)
                    // Tapping the dialog body (outside the search field/list)
                    // drops focus, which closes the Autocomplete dropdown.
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => FocusScope.of(context).unfocus(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(l10n.itemsRecipeHint,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            _buildAddSearch(context, materials),
                            const SizedBox(height: 8),
                            Flexible(
                              child: _buildSelectedTable(context, materials),
                            ),
                          ],
                        ),
                      ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        ElevatedButton(
          onPressed: (_saving || _loading) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l10n.commonSave),
        ),
      ],
    );
  }
}
