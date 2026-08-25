import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/skeletons.dart';
import '../api.dart';
import '../services/printer_service.dart';
import 'menu_photos_screen.dart';
import 'raw_materials_tab.dart';

/// Localized short label for an item's unit-of-measure (e.g. 'kg', 'plate').
/// Covers every unit an item may use — a superset of [rawMaterialUnitLabel].
String itemUnitLabel(BuildContext context, String unit) {
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
    case 'metre':
      return l10n.itemsUnitMetre;
    case 'dozen':
      return l10n.itemsUnitDozen;
    case 'plate':
      return l10n.itemsUnitPlate;
    default:
      return l10n.itemsUnitPiece;
  }
}

/// Price shown for an item in a list.
///
/// A sized item has no price of its own — its sizes do — so show the range they
/// span ("₹180 – ₹280") rather than a meaningless figure. Falls back to a dash
/// when nothing is priced yet.
String itemPriceLabel(Item item) {
  if (item.hasVariants) {
    final prices = item.variants
        .map((v) => v.price ?? item.price)
        .whereType<double>()
        .toList()
      ..sort();
    if (prices.isEmpty) return '—';
    if (prices.first == prices.last) {
      return '₹${prices.first.toStringAsFixed(2)}';
    }
    return '₹${prices.first.toStringAsFixed(2)} – ₹${prices.last.toStringAsFixed(2)}';
  }
  final p = item.price;
  return p == null ? '—' : '₹${p.toStringAsFixed(2)}';
}

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  TabController? _tabController;
  int _activeTab = 0;
  // When on, the Items list renders a compact stock overview (name + remaining
  // stock) in place, instead of the normal cards.
  bool _showStock = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  /// Whether the Raw Materials tab should be offered — restaurant businesses
  /// with inventory enabled (only owners manage it).
  bool _showRawMaterials(String businessType, bool inventoryEnabled, String role) {
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    return isRestaurant && inventoryEnabled && role == 'owner';
  }

  void _ensureTabController(bool withRawMaterials) {
    final desiredLength = withRawMaterials ? 2 : 1;
    if (_tabController?.length == desiredLength) return;
    _tabController?.dispose();
    _tabController = TabController(length: desiredLength, vsync: this)
      ..addListener(() {
        if (!(_tabController!.indexIsChanging)) {
          setState(() => _activeTab = _tabController!.index);
        }
      });
    _activeTab = 0;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  List<Item> _filtered(List<Item> items) {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return items;
    return items.where((i) {
      final name = i.name.toLowerCase();
      final category = (i.category ?? '').toLowerCase();
      return name.contains(q) || category.contains(q);
    }).toList();
  }

  void _showBarcodePrint(Item item) {
    showDialog(
      context: context,
      builder: (_) => _BarcodePrintDialog(
        item: item,
        onBarcodeGenerated: (newBarcode) async {
          await ref
              .read(itemsProvider.notifier)
              .updateItem(item.id, {'barcode': newBarcode});
        },
      ),
    );
  }

  void _showStockPopup(Item item) {
    final inventoryEnabled = ref.read(inventoryEnabledProvider);

    // Items with sizes track stock per size — show a per-size stock editor
    // instead of the item-level one.
    if (inventoryEnabled && item.hasVariants) {
      showDialog(
        context: context,
        builder: (_) => _VariantStockDialog(
          item: item,
          onSaved: (variants) {
            ref.read(itemsProvider.notifier).setItemVariants(item.id, variants);
          },
          onEditTapped: () {
            Navigator.pop(context);
            _showItemForm(item: item);
          },
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _StockPopupDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        onStockUpdated: (newStock) async {
          await ref
              .read(itemsProvider.notifier)
              .updateItem(item.id, {'stock_quantity': newStock});
        },
        onEditTapped: () {
          Navigator.pop(context);
          _showItemForm(item: item);
        },
      ),
    );
  }

  void _showItemForm({Item? item}) {
    final inventoryEnabled = ref.read(inventoryEnabledProvider);
    final gstEnabled = ref.read(gstEnabledProvider);
    final businessType = ref.read(businessTypeProvider);
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    // Recipes only apply to restaurant dishes with inventory, and need a saved
    // item to attach to.
    final showRecipe = isRestaurant && inventoryEnabled && item != null;
    // Existing categories for this business, to offer as dropdown suggestions.
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    showDialog(
      context: context,
      builder: (_) => _ItemFormDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        gstEnabled: gstEnabled,
        categories: categories,
        onSaved: (data, variants) async {
          final saved = item == null
              ? await ref.read(itemsProvider.notifier).addItem(data)
              : await ref.read(itemsProvider.notifier).updateItem(item.id, data);
          await ref.read(categoriesProvider.notifier).reload();
          return saved;
        },
        onVariantsCreated: (itemId, variants) =>
            ref.read(itemsProvider.notifier).setItemVariants(itemId, variants),
        onManageSizes:
            item != null ? () => _showVariantManager(item) : null,
        onManageRecipe: showRecipe
            ? () => showDialog(
                  context: context,
                  builder: (_) => RecipeEditorDialog(
                      itemId: item.id, itemName: item.name),
                )
            : null,
      ),
    );
  }

  void _showVariantManager(Item item) {
    final inventoryEnabled = ref.read(inventoryEnabledProvider);
    showDialog(
      context: context,
      builder: (_) => _VariantManagerDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        onChanged: (variants) {
          // Patch this item's variants locally — instant, no network refetch.
          ref.read(itemsProvider.notifier).setItemVariants(item.id, variants);
        },
      ),
    );
  }

  Future<void> _deleteItem(Item item) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.itemsDeleteTitle),
        content: Text(l10n.itemsDeleteBody(item.name)),
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(itemsProvider.notifier).removeItem(item.id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userRole = ref.watch(userRoleProvider);
    final inventoryEnabled = ref.watch(inventoryEnabledProvider);
    final itemsAsync = ref.watch(itemsProvider);
    final l10n = context.l10n;

    final businessType = ref.watch(businessTypeProvider);
    // Menu photos are customer-facing DISH images shown on the QR menu, so they
    // only apply to food businesses. A retail shop has no menu to photograph.
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    final withRawMaterials =
        _showRawMaterials(businessType, inventoryEnabled, userRole);
    _ensureTabController(withRawMaterials);
    final onRawTab = withRawMaterials && _activeTab == 1;

    return Scaffold(
      body: Column(
        children: [
          // Bottom-bar root tab: never imply a back arrow. Without this,
          // opening a dialog (add item / stock) pushes a route and flips
          // Navigator.canPop() to true, making a stray back arrow appear.
          ShellAppBar(
              title: Text(l10n.itemsTitle),
              automaticallyImplyLeading: false,
              // Owners manage customer-facing dish photos here. Photos live in a
              // dedicated screen and never appear during billing. Restaurants
              // only — a retail shop has no QR menu for the photos to appear on.
              actions: userRole == 'owner' && isRestaurant
                  ? [
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined),
                        color: AppColors.textPrimary,
                        tooltip: l10n.menuPhotosTooltip,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MenuPhotosScreen()),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ]
                  : null),
          if (withRawMaterials)
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: l10n.itemsTabItems),
                Tab(text: l10n.itemsTabRawMaterials),
              ],
            ),
          Expanded(
            child: withRawMaterials
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBody(itemsAsync, userRole, inventoryEnabled),
                      const RawMaterialsTab(),
                    ],
                  )
                : _buildBody(itemsAsync, userRole, inventoryEnabled),
          ),
        ],
      ),
      floatingActionButton: userRole == 'owner'
          ? FloatingActionButton.extended(
              // Explicit tag to avoid the shared default hero tag colliding with
              // other FABs kept alive in the shell's IndexedStack.
              heroTag: 'addItemFab',
              onPressed: () =>
                  onRawTab ? _showRawMaterialForm() : _showItemForm(),
              icon: const Icon(Icons.add),
              label: Text(onRawTab
                  ? l10n.itemsAddRawMaterial
                  : l10n.itemsAddItem),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showRawMaterialForm({RawMaterial? material}) {
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

  Widget _searchBarSliver({bool inventoryEnabled = false}) =>
      SliverToBoxAdapter(
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
              // Toggle the in-place stock overview (name + remaining stock).
              if (inventoryEnabled) ...[
                const SizedBox(width: AppSpacing.space8),
                StockOverviewButton(
                  tooltip: context.l10n.itemsStockOverview,
                  active: _showStock,
                  onTap: () => setState(() => _showStock = !_showStock),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildBody(
      AsyncValue<List<Item>> itemsAsync, String userRole, bool inventoryEnabled) {
    final l10n = context.l10n;
    return itemsAsync.when(
      loading: () => const ItemsSkeleton(),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () => ref.invalidate(itemsProvider),
      ),
      data: (allItems) {
        if (allItems.isEmpty && !ref.read(connectivityProvider)) {
          return NoInternetWidget(
            onRetry: () => ref.invalidate(itemsProvider),
          );
        }
        final items = _filtered(allItems);
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(itemsProvider);
              await ref.read(itemsProvider.future);
            },
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              _searchBarSliver(inventoryEnabled: inventoryEnabled),
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: userRole == 'owner'
                      ? l10n.itemsNoneYetOwner
                      : l10n.itemsNoneFound,
                  actionLabel: userRole == 'owner' ? l10n.itemsAddItem : null,
                  onAction: userRole == 'owner' ? () => _showItemForm() : null,
                ),
              ),
            ]),
          );
        }

        final isWide = MediaQuery.of(context).size.width >= 720;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(itemsProvider);
            await ref.read(itemsProvider.future);
          },
          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
            _searchBarSliver(inventoryEnabled: inventoryEnabled),
            _buildGridSliver(items, userRole, inventoryEnabled,
                crossAxisCount: isWide ? 3 : 1),
          ]),
        );
      },
    );
  }

  Widget _buildGridSliver(List<Item> items, String userRole, bool inventoryEnabled,
      {int crossAxisCount = 1}) {
    final stockMode = _showStock && inventoryEnabled;
    const padding = EdgeInsets.fromLTRB(
        AppSpacing.space8, AppSpacing.space4, AppSpacing.space8, 96);

    // In stock mode, item cards with variants expand to a variable-height list
    // of their variants. A fixed-extent grid can't handle that, so use a
    // masonry column layout (same approach as the Kitchen screen): split cards
    // across N columns, each keeping its natural height, packed into the
    // shortest column so there are no big gaps.
    if (stockMode) {
      if (crossAxisCount <= 1) {
        return SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: animatedCardSwap(true, _buildStockCard(items[i])),
            ),
          ),
        );
      }
      return SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: LayoutBuilder(builder: (context, constraints) {
            const spacing = AppSpacing.space8;
            final cols = crossAxisCount;
            final cardWidth =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;

            // Masonry: place each card into the currently shortest column.
            final columns = List.generate(cols, (_) => <Widget>[]);
            final columnHeights = List.filled(cols, 0.0);
            for (var i = 0; i < items.length; i++) {
              var target = 0;
              for (var c = 1; c < cols; c++) {
                if (columnHeights[c] < columnHeights[target]) target = c;
              }
              // ~44px header + ~24px per variant row; only relative height matters.
              final variantCount = items[i].variants.length;
              columnHeights[target] += 44 + variantCount * 24 + spacing;
              columns[target].add(Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: animatedCardSwap(true, _buildStockCard(items[i])),
              ));
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) const SizedBox(width: spacing),
                  SizedBox(
                    width: cardWidth,
                    child: Column(children: columns[c]),
                  ),
                ],
              ],
            );
          }),
        ),
      );
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.space8,
          mainAxisSpacing: 6,
          mainAxisExtent: 52,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            animatedCardSwap(false, _buildItemCard(items[i], userRole, inventoryEnabled)),
      ),
    );
  }

  /// Stock-overview card for a single item. Items whose stock is tracked per
  /// variant show each variant's remaining stock; others show a single total.
  Widget _buildStockCard(Item item) {
    if (item.hasVariants) {
      return buildVariantStockCard(
        context,
        name: item.name,
        variants: [
          for (final v in item.variants)
            StockOverviewRow(
              name: v.label,
              stockQuantity: v.stockQuantity,
              unitLabel: itemUnitLabel(context, item.unit),
              isLowStock: v.isLowStock,
            ),
        ],
      );
    }
    return buildStockCard(
      context,
      StockOverviewRow(
        name: item.name,
        stockQuantity: item.stockQuantity,
        unitLabel: itemUnitLabel(context, item.unit),
        isLowStock: item.isLowStock,
      ),
    );
  }

  Widget _buildItemCard(Item item, String userRole, bool inventoryEnabled) {
    final l10n = context.l10n;
    final subtitle = [
      if (item.category != null) item.category!,
      if (inventoryEnabled && item.stockQuantity != null)
        l10n.itemsStockLabel(formatQty(item.stockQuantity!)),
    ].join('  ·  ');

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
          onTap: () => _showStockPopup(item),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // Color dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.border,
                  ),
                ),
                const SizedBox(width: 8),
                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty || (inventoryEnabled && item.isLowStock))
                        Row(
                          children: [
                            if (subtitle.isNotEmpty)
                              Flexible(
                                child: Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    height: 1.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (inventoryEnabled && item.isLowStock) ...[
                              if (subtitle.isNotEmpty)
                                const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '· ${l10n.itemsLowStock}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                // Price — a range for a sized item, whose own price is null.
                Text(
                  itemPriceLabel(item),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.space8),
                // Actions
                InkWell(
                  onTap: () => _showBarcodePrint(item),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.qr_code_outlined,
                      size: 16,
                      color: item.barcode != null
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (userRole == 'owner') ...[
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => _deleteItem(item),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 16, color: AppColors.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stock quick-update popup — tap item to update stock, Edit button for full edit
// ---------------------------------------------------------------------------
class _StockPopupDialog extends StatefulWidget {
  final Item item;
  final bool inventoryEnabled;
  final Future<void> Function(double stock) onStockUpdated;
  final VoidCallback onEditTapped;

  const _StockPopupDialog({
    required this.item,
    required this.inventoryEnabled,
    required this.onStockUpdated,
    required this.onEditTapped,
  });

  @override
  State<_StockPopupDialog> createState() => _StockPopupDialogState();
}

class _StockPopupDialogState extends State<_StockPopupDialog> {
  late final TextEditingController _addCtrl;
  bool _saving = false;
  bool _removing = false;

  double get _current => widget.item.stockQuantity ?? 0;
  double get _entered => double.tryParse(_addCtrl.text.trim()) ?? 0;
  double get _adding => _removing ? -_entered : _entered;
  // Stock can never go negative, regardless of how much was requested to remove.
  double get _total => (_current + _adding).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _addCtrl = TextEditingController();
    _addCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_entered <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.onStockUpdated(_total);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasInput = _entered > 0;
    final l10n = context.l10n;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(item.name,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: l10n.itemsEditItemTooltip,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: widget.onEditTapped,
          ),
        ],
      ),
      content: SizedBox(
        width: 280,
        // Scrollable so longer scripts (Marathi/Devanagari at large text
        // scales) that exceed the dialog's bounded height scroll instead of
        // overflowing.
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item details row
            Row(
              children: [
                Text(itemPriceLabel(item),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        )),
                if (item.category != null) ...[
                  const SizedBox(width: 8),
                  const Text('·',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(item.category!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                ],
              ],
            ),
            if (widget.inventoryEnabled) ...[
              const SizedBox(height: 20),
              // Current stock display
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(l10n.itemsCurrentStock,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            )),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${formatQty(_current)} ${itemUnitLabel(context, widget.item.unit)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Add / Remove mode toggle. expandedInsets stretches the control
              // to fill the row and split it into two equal-width segments, so
              // the layout stays static when switching between "Add" and the
              // wider "Remove" label — only the selected fill moves.
              SegmentedButton<bool>(
                expandedInsets: EdgeInsets.zero,
                segments: [
                  ButtonSegment(
                      value: false, label: Text(l10n.itemsStockModeAdd)),
                  ButtonSegment(
                      value: true, label: Text(l10n.itemsStockModeRemove)),
                ],
                selected: {_removing},
                onSelectionChanged: (selection) {
                  setState(() => _removing = selection.first);
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: _removing ? l10n.itemsRemoveQuantity : l10n.itemsAddQuantity,
                controller: _addCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              // Total stock preview
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: hasInput
                      ? AppColors.primaryLight
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                          _removing
                              ? l10n.itemsTotalAfterRemoving
                              : l10n.itemsTotalAfterAdding,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: hasInput
                                        ? AppColors.primaryDark
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  )),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatQty(_total)} ${itemUnitLabel(context, widget.item.unit)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: hasInput
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(l10n.itemsInventoryDisabled,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        if (widget.inventoryEnabled)
          ElevatedButton(
            onPressed: (_saving || !hasInput) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(l10n.commonUpdate),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One in-progress variant row in the Add Item form.
//
// Owns its own controllers rather than living in a map keyed by index, so
// deleting a middle row doesn't shuffle everyone else's text.
// ---------------------------------------------------------------------------
class _VariantDraft {
  final label = TextEditingController();
  final price = TextEditingController();
  final barcode = TextEditingController();
  final stock = TextEditingController();
  final lowStock = TextEditingController();

  /// A row the user added and then left completely untouched. Dropped silently
  /// on save — a trailing blank row is a change of mind, not an error.
  bool get isBlank =>
      label.text.trim().isEmpty &&
      price.text.trim().isEmpty &&
      barcode.text.trim().isEmpty &&
      stock.text.trim().isEmpty &&
      lowStock.text.trim().isEmpty;

  void dispose() {
    label.dispose();
    price.dispose();
    barcode.dispose();
    stock.dispose();
    lowStock.dispose();
  }
}

// ---------------------------------------------------------------------------
// Add / Edit item dialog — stays StatefulWidget (no need for Riverpod here)
// ---------------------------------------------------------------------------
class _ItemFormDialog extends StatefulWidget {
  final Item? item;
  final bool inventoryEnabled;
  final bool gstEnabled;
  final List<String> categories;

  /// Saves the item and returns it, so the variants can be created against the
  /// new id. [variants] is empty unless the "has variants" box was ticked.
  final Future<Item> Function(
      Map<String, dynamic> data, List<Map<String, dynamic>> variants) onSaved;
  /// Called once the inline variants have been created, so the caller can patch
  /// the item in local state. Without this the freshly-created item keeps
  /// `variants: []` and would bill at its base price.
  final void Function(String itemId, List<ItemVariant> variants)?
      onVariantsCreated;
  final VoidCallback? onManageSizes;
  final VoidCallback? onManageRecipe;

  const _ItemFormDialog(
      {this.item,
      required this.inventoryEnabled,
      this.gstEnabled = false,
      this.categories = const [],
      required this.onSaved,
      this.onVariantsCreated,
      this.onManageSizes,
      this.onManageRecipe});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _categoryFocus = FocusNode();
  final _priceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  String _unit = 'piece';
  bool _saving = false;

  /// Whether the entered price already contains GST (an MRP) rather than being
  /// a net price GST is added to. Only meaningful when GST is on and a tax rate
  /// is set; billing back-calculates the net rate from an inclusive price.
  bool _priceInclusiveTax = false;

  /// Whether the user ticked "this item has variants" while CREATING. Editing an
  /// existing item still routes to the dedicated size manager, which already
  /// handles update/delete of persisted sizes safely.
  bool _hasVariants = false;
  final List<_VariantDraft> _variantDrafts = [];

  /// The item created by a previous save attempt that then failed part-way
  /// through its variants. Held so a retry adds only the MISSING variants
  /// instead of creating a second item.
  Item? _savedItem;

  /// Indexes (into the non-blank draft list) whose variant was already created.
  final Set<int> _createdDraftIndexes = {};

  /// Shown as a banner when the item saved but some variants did not.
  String? _partialFailure;

  static const _units = [
    'piece',
    'kg',
    'g',
    'litre',
    'ml',
    'metre',
    'dozen',
    'plate',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _nameCtrl.text = item.name;
      _categoryCtrl.text = item.category ?? '';
      _priceCtrl.text = item.price.toString();
      _taxCtrl.text = item.taxRate?.toString() ?? '';
      _priceInclusiveTax = item.priceInclusiveTax;
      _hsnCtrl.text = item.hsnCode ?? '';
      _barcodeCtrl.text = item.barcode ?? '';
      _stockCtrl.text = item.stockQuantity?.toString() ?? '';
      _lowStockCtrl.text = item.lowStockThreshold?.toString() ?? '';
      _unit = _units.contains(item.unit) ? item.unit : 'piece';
    }
  }

  /// "Price already includes GST" toggle.
  ///
  /// This is the one setting an owner cannot infer from the price field alone:
  /// ₹100 at 5% is either ₹105.00 or ₹100.00 at the counter, and nothing on
  /// screen distinguishes them. So the tile always carries a plain-language
  /// explanation of what the switch decides, and — as soon as a price and a tax
  /// rate are both entered — a live line stating the rupee amount the customer
  /// will actually be charged. The owner should never have to run the division
  /// in their head to find out what they just configured.
  ///
  /// Rebuilt from the price/tax controllers directly (AppTextField exposes no
  /// onChanged) so the figures track every keystroke.
  Widget _buildInclusiveTaxToggle(AppLocalizations l10n) {
    return AnimatedBuilder(
      animation: Listenable.merge([_priceCtrl, _taxCtrl]),
      builder: (context, _) {
        final theme = Theme.of(context);
        // A sized item has no price of its own — its sizes do — so there is no
        // single figure to break down. The flag still applies to those sizes.
        final sized = _hasVariants || (widget.item?.hasVariants ?? false);
        final price = sized ? null : double.tryParse(_priceCtrl.text.trim());
        final rate = double.tryParse(_taxCtrl.text.trim());

        // What this switch means, in both positions. Shown always — it is the
        // answer to "what is this for?", which a state readout never gives.
        final meaning = _priceInclusiveTax
            ? l10n.itemsPriceInclusiveTaxOn
            : l10n.itemsPriceInclusiveTaxOff;

        // The concrete consequence in rupees, once there is enough to compute.
        // Mirrors CartEntry/netUnitPrice: an inclusive price is the gross and
        // the net is backed out of it; an exclusive price is the net and tax
        // goes on top.
        String? outcome;
        if (rate == null || rate <= 0) {
          outcome = sized ? null : l10n.itemsPriceBreakdownNeedsRate;
        } else if (sized) {
          outcome = l10n.itemsPriceBreakdownSized;
        } else if (price != null && price > 0) {
          final net = _priceInclusiveTax ? price / (1 + rate / 100) : price;
          final tax = net * (rate / 100);
          final args = [
            (net + tax).toStringAsFixed(2),
            net.toStringAsFixed(2),
            tax.toStringAsFixed(2),
            _trimRate(rate),
          ];
          outcome = _priceInclusiveTax
              ? l10n.itemsPriceBreakdownOn(args[0], args[1], args[2], args[3])
              : l10n.itemsPriceBreakdownOff(args[0], args[1], args[2], args[3]);
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: _priceInclusiveTax,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _priceInclusiveTax = v),
                title: Text(
                  l10n.itemsPriceInclusiveTax,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    // Instruction first (when to switch it on), then what the
                    // current position does.
                    '${l10n.itemsPriceInclusiveTaxHelp}\n$meaning',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                isThreeLine: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space12),
              ),
              if (outcome != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.medium),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          outcome,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Price-field label, spelling out whether GST is already in the figure.
  ///
  /// Falls back to the plain label when GST is off for the business — there is
  /// no distinction to draw, and naming GST there would only confuse.
  String _priceLabel(AppLocalizations l10n) {
    if (!widget.gstEnabled) return l10n.itemsFieldPrice;
    return _priceInclusiveTax
        ? l10n.itemsFieldPriceInclusive
        : l10n.itemsFieldPriceExclusive;
  }

  /// Tax rate for display: "5" not "5.0", but "2.5" kept intact.
  String _trimRate(double rate) => rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate.toString();

  String _unitLabel(BuildContext context, String unit) {
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
      case 'metre':
        return l10n.itemsUnitMetre;
      case 'dozen':
        return l10n.itemsUnitDozen;
      case 'plate':
        return l10n.itemsUnitPlate;
      default:
        return l10n.itemsUnitPiece;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _categoryFocus.dispose();
    _priceCtrl.dispose();
    _taxCtrl.dispose();
    _hsnCtrl.dispose();
    _barcodeCtrl.dispose();
    _stockCtrl.dispose();
    _lowStockCtrl.dispose();
    for (final d in _variantDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  /// Category field: a text field you can type into freely, with a dropdown of
  /// this business's existing categories. Typing a new value keeps it — on save
  /// that category is added to the business (categories come from the items, so
  /// a new category exists as soon as an item uses it). Picking a suggestion
  /// fills the field.
  Widget _buildCategoryField(BuildContext context, AppLocalizations l10n) {
    return RawAutocomplete<String>(
      textEditingController: _categoryCtrl,
      focusNode: _categoryFocus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        final all = [...widget.categories]..sort();
        if (q.isEmpty) return all;
        return all.where((c) => c.toLowerCase().contains(q));
      },
      onSelected: (sel) => _categoryCtrl.text = sel,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return AppTextField(
          label: l10n.itemsFieldCategory,
          controller: controller,
          focusNode: focusNode,
          hint: l10n.itemsFieldCategoryHint,
          suffixIcon: widget.categories.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondary),
                  tooltip: l10n.itemsFieldCategory,
                  // Toggle the suggestion list by nudging focus + an empty edit
                  // so optionsBuilder re-runs and the overlay shows all options.
                  onPressed: () {
                    if (focusNode.hasFocus) {
                      focusNode.unfocus();
                    } else {
                      focusNode.requestFocus();
                    }
                  },
                ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 368),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Barcodes are compared the way the server's lookup normalises them (see the
  /// REPLACE chain in routes/items.js) — otherwise "12-34" and "1234" look
  /// distinct here but collide at scan time.
  static String _normaliseBarcode(String s) =>
      s.replaceAll(RegExp(r'[\s\-.]'), '');

  /// Cross-row checks that a per-field validator can't express. Returns an error
  /// message, or null when the drafts are fine.
  ///
  /// Worth doing carefully: a duplicate barcode reaches the server as a unique
  /// index violation, and duplicate LABELS aren't constrained at all — two sizes
  /// called "M" would both be created and be indistinguishable when billing.
  String? _validateVariants(AppLocalizations l10n, String? itemBarcode) {
    final drafts = _variantDrafts.where((d) => !d.isBlank).toList();
    if (drafts.isEmpty) return l10n.itemsVariantsNoneEntered;

    final seenLabels = <String>{};
    final seenBarcodes = <String>{};
    final normalisedItemBarcode =
        itemBarcode == null ? null : _normaliseBarcode(itemBarcode);

    for (final d in drafts) {
      final label = d.label.text.trim();
      if (!seenLabels.add(label.toLowerCase())) {
        return l10n.itemsVariantDuplicateLabel(label);
      }
      final barcode = d.barcode.text.trim();
      if (barcode.isEmpty) continue;
      final normalised = _normaliseBarcode(barcode);
      if (!seenBarcodes.add(normalised)) {
        return l10n.itemsVariantDuplicateBarcode(barcode);
      }
      if (normalisedItemBarcode != null && normalised == normalisedItemBarcode) {
        return l10n.itemsVariantBarcodeSameAsItem;
      }
    }
    return null;
  }

  Map<String, dynamic> _draftPayload(_VariantDraft d, int sortOrder) => {
        'label': d.label.text.trim(),
        if (d.price.text.trim().isNotEmpty)
          'price': double.parse(d.price.text.trim()),
        if (d.barcode.text.trim().isNotEmpty) 'barcode': d.barcode.text.trim(),
        if (widget.inventoryEnabled && d.stock.text.trim().isNotEmpty)
          'stock_quantity': double.parse(d.stock.text.trim()),
        if (widget.inventoryEnabled && d.lowStock.text.trim().isNotEmpty)
          'low_stock_threshold': double.parse(d.lowStock.text.trim()),
        'sort_order': sortOrder,
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Auto-generate a 12-digit barcode for new items that have no barcode.
    // Use current timestamp so it's unique and scannable immediately. A sized
    // item gets none — its sizes are what get scanned.
    final barcodeInput = _hasVariants ? '' : _barcodeCtrl.text.trim();
    final autoBarcode =
        (widget.item == null && !_hasVariants && barcodeInput.isEmpty)
            ? DateTime.now().millisecondsSinceEpoch.toString().substring(1, 13)
            : null;
    final effectiveBarcode = barcodeInput.isNotEmpty ? barcodeInput : autoBarcode;

    if (_hasVariants) {
      final err = _validateVariants(context.l10n, effectiveBarcode);
      if (err != null) {
        _showError(err);
        return;
      }
    }

    setState(() {
      _saving = true;
      _partialFailure = null;
    });

    // Items with sizes track stock per size — the server nulls the parent's
    // stock as soon as a size exists, so don't send a figure that will be
    // discarded.
    final sizedItem = _hasVariants || (widget.item?.hasVariants ?? false);

    final data = {
      'name': _nameCtrl.text.trim(),
      if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
      // A sized item has no price of its own — the sizes carry it. The server
      // only accepts a null price when has_variants says so.
      if (_hasVariants) 'has_variants': true,
      'price': _hasVariants ? null : double.parse(_priceCtrl.text.trim()),
      if (_taxCtrl.text.trim().isNotEmpty)
        'tax_rate': double.parse(_taxCtrl.text.trim()),
      // Always sent (not conditional on the tax field) so clearing the rate or
      // switching the toggle off is persisted rather than leaving a stale 1
      // behind on the server.
      if (widget.gstEnabled) 'price_inclusive_tax': _priceInclusiveTax,
      if (widget.gstEnabled)
        'hsn_code': _hsnCtrl.text.trim().isNotEmpty ? _hsnCtrl.text.trim() : null,
      'barcode': effectiveBarcode,
      'unit': _unit,
      if (widget.inventoryEnabled && sizedItem)
        'stock_quantity': null
      else if (widget.inventoryEnabled && _stockCtrl.text.trim().isNotEmpty)
        'stock_quantity': double.parse(_stockCtrl.text.trim()),
      if (widget.inventoryEnabled && !sizedItem && _lowStockCtrl.text.trim().isNotEmpty)
        'low_stock_threshold': double.parse(_lowStockCtrl.text.trim()),
    };

    final drafts = _variantDrafts.where((d) => !d.isBlank).toList();

    try {
      // On a retry after a partial failure the item already exists — creating it
      // again would leave a duplicate behind.
      final saved = _savedItem ?? await widget.onSaved(data, const []);
      _savedItem = saved;

      if (_hasVariants && drafts.isNotEmpty) {
        final created = <ItemVariant>[];
        final failed = <String>[];
        for (var i = 0; i < drafts.length; i++) {
          if (_createdDraftIndexes.contains(i)) continue;
          try {
            final res = await createVariant(saved.id, _draftPayload(drafts[i], i));
            created.add(ItemVariant.fromJson(res));
            _createdDraftIndexes.add(i);
          } catch (_) {
            failed.add(drafts[i].label.text.trim());
          }
        }
        // Patch local state even on partial success: without this the item sits
        // in the list with variants: [], so tapping it while billing would
        // charge the base price instead of opening the size picker.
        if (created.isNotEmpty) {
          widget.onVariantsCreated?.call(saved.id, created);
        }
        if (failed.isNotEmpty) {
          if (!mounted) return;
          setState(() => _partialFailure = context.l10n
              .itemsVariantsPartialFail(failed.length, drafts.length));
          return;
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      _showError(sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleHasVariants(bool value) {
    setState(() {
      _hasVariants = value;
      // Start with one row so ticking the box shows something to fill in
      // straight away. Drafts are kept on untick so an accidental toggle
      // doesn't wipe typed data.
      if (_hasVariants && _variantDrafts.isEmpty) {
        _variantDrafts.add(_VariantDraft());
      }
    });
  }

  void _removeVariantRow(int index) {
    setState(() {
      _variantDrafts.removeAt(index).dispose();
      // An empty section with only an "add" button reads as broken — untick
      // instead once the last row is gone.
      if (_variantDrafts.isEmpty) _hasVariants = false;
    });
  }

  /// The "this item has variants" toggle plus, once ticked, one card per size.
  Widget _buildVariantsSection(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _hasVariants,
            onChanged: _saving ? null : (v) => _toggleHasVariants(v ?? false),
            title: Text(l10n.itemsHasVariants),
            subtitle: Text(
              l10n.itemsHasVariantsSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: AppColors.primary,
          ),
          if (_hasVariants) ...[
            // The item's own stock box stays visible (it still applies to a
            // plain item), so be explicit that it is ignored once sizes exist.
            if (widget.inventoryEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.itemsVariantsStockIgnoredHint,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            for (var i = 0; i < _variantDrafts.length; i++)
              _buildVariantCard(l10n, i),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space8),
              child: OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _variantDrafts.add(_VariantDraft())),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.itemsAddAnotherVariant,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One size: name + price, then barcode + stock, then the low-stock alert.
  /// Two fields per row — the dialog is 400px wide and each AppTextField
  /// carries 16px of padding either side, so more than two per row is unusable.
  Widget _buildVariantCard(AppLocalizations l10n, int index) {
    final d = _variantDrafts[index];
    final numeric = const TextInputType.numberWithOptions(decimal: true);

    String? nonNegative(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = double.tryParse(v.trim());
      if (n == null || n < 0) return l10n.commonEnterValidNumber;
      return null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space8),
      padding: const EdgeInsets.all(AppSpacing.space8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.itemsVariantRowTitle(index + 1),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _saving ? null : () => _removeVariantRow(index),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: l10n.itemsVariantNameShort,
                  hint: l10n.itemsVariantNameHint,
                  controller: d.label,
                  capitalizeWords: true,
                  maxLength: 50,
                  validator: (v) => d.isBlank
                      ? null
                      : (v == null || v.trim().isEmpty
                          ? l10n.commonRequired
                          : null),
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Expanded(
                child: AppTextField(
                  // Required now: with no item-level price to fall back on, a
                  // size with no price would have nothing to charge.
                  // Sizes inherit the item's inclusive/exclusive flag, so the
                  // label tracks it too.
                  label: _priceLabel(l10n),
                  controller: d.price,
                  keyboardType: numeric,
                  validator: (v) {
                    if (d.isBlank) return null;
                    if (v == null || v.trim().isEmpty) {
                      return l10n.commonRequired;
                    }
                    return nonNegative(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: l10n.itemsSizeBarcodeOptional,
                  controller: d.barcode,
                  keyboardType: TextInputType.number,
                  maxLength: 100,
                ),
              ),
              if (widget.inventoryEnabled) ...[
                const SizedBox(width: AppSpacing.space8),
                Expanded(
                  child: AppTextField(
                    label: l10n.itemsSizeStock,
                    controller: d.stock,
                    keyboardType: numeric,
                    validator: nonNegative,
                  ),
                ),
              ],
            ],
          ),
          if (widget.inventoryEnabled) ...[
            const SizedBox(height: AppSpacing.space8),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: l10n.itemsFieldLowStock,
                    controller: d.lowStock,
                    keyboardType: numeric,
                    validator: nonNegative,
                  ),
                ),
                const SizedBox(width: AppSpacing.space8),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.error,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.item == null ? l10n.itemsAddItem : l10n.itemsEditItem),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          // Several variant cards on top of the item fields easily exceed a
          // small phone's height — cap it so the content scrolls instead of the
          // dialog being squeezed and the Save button becoming unreachable.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_partialFailure != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(bottom: AppSpacing.space12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _partialFailure!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
                AppTextField(
                  label: l10n.itemsFieldName,
                  controller: _nameCtrl,
                  capitalizeWords: true,
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.commonRequired : null,
                ),
                const SizedBox(height: AppSpacing.space12),
                _buildCategoryField(context, l10n),
                // The variants toggle sits here, before price/barcode/stock,
                // because it decides whether those fields apply at all: a sized
                // item owns none of them — each size carries its own.
                if (widget.item == null) ...[
                  const SizedBox(height: AppSpacing.space12),
                  _buildVariantsSection(l10n),
                ],
                // Price belongs to the item only when it has no sizes.
                if (!_hasVariants) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    // The label states which kind of price is expected, so the
                    // GST question is answered at the moment the number is
                    // typed rather than only at the toggle further down.
                    label: _priceLabel(l10n),
                    controller: _priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return l10n.commonRequired;
                      if (double.tryParse(v) == null) {
                        return l10n.commonEnterValidNumber;
                      }
                      return null;
                    },
                  ),
                ],
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
                    for (final u in _units)
                      DropdownMenuItem(
                        value: u,
                        child: Text(_unitLabel(context, u),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? 'piece'),
                ),
                // Tax rate + HSN/SAC only appear when GST is enabled for the
                // business. When off, the item form has no tax fields at all —
                // exactly as before GST support existed.
                if (widget.gstEnabled) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldTaxRate,
                    controller: _taxCtrl,
                    hint: l10n.itemsFieldTaxRateHint,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                        return l10n.commonEnterValidNumber;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space12),
                  _buildInclusiveTaxToggle(l10n),
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldHsn,
                    controller: _hsnCtrl,
                    hint: l10n.itemsFieldHsnHint,
                  ),
                ],
                // A sized item is never scanned directly — each size has its own
                // barcode, so the item-level one would be ambiguous.
                if (!_hasVariants) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldBarcode,
                    controller: _barcodeCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ],
                // Item-level stock is only meaningful when the item has NO
                // sizes. With sizes, stock is tracked per size, so hide it and
                // show a hint pointing to the size manager.
                if (widget.inventoryEnabled &&
                    !_hasVariants &&
                    !(widget.item?.hasVariants ?? false)) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldStock,
                    controller: _stockCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSpacing.space12),
                  // Low-stock alert level. Until now this was hardcoded to 50
                  // server-side and could not be set at all from the app.
                  AppTextField(
                    label: l10n.itemsFieldLowStock,
                    hint: l10n.itemsFieldLowStockHint,
                    controller: _lowStockCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      if (n == null) return l10n.commonEnterValidNumber;
                      return n < 0 ? l10n.commonEnterValidNumber : null;
                    },
                  ),
                ] else if (widget.inventoryEnabled &&
                    (widget.item?.hasVariants ?? false)) ...[
                  const SizedBox(height: AppSpacing.space12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.itemsStockPerSizeHint,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.onManageSizes != null && !_hasVariants) ...[
                  const SizedBox(height: AppSpacing.space12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onManageSizes!();
                    },
                    icon: const Icon(Icons.straighten_outlined, size: 18),
                    label: Text(
                      widget.item != null && widget.item!.hasVariants
                          ? l10n.itemsManageSizesCount(
                              widget.item!.variants.length)
                          : l10n.itemsManageSizes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
                if (widget.onManageRecipe != null) ...[
                  const SizedBox(height: AppSpacing.space12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onManageRecipe!();
                    },
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      l10n.itemsManageRecipe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ],
            ),
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
              : Text(widget.item == null ? l10n.commonAdd : l10n.commonSave),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barcode print dialog — generates a barcode for items that don't have one,
// shows a preview, and sends the label to the thermal printer via TSPL.
// ---------------------------------------------------------------------------

class _BarcodePrintDialog extends StatefulWidget {
  final Item item;

  /// When set, the dialog generates/prints a barcode for this size (variant)
  /// rather than the whole item. The label shows the size name and its price.
  final ItemVariant? variant;
  final Future<void> Function(String barcode) onBarcodeGenerated;

  const _BarcodePrintDialog({
    required this.item,
    this.variant,
    required this.onBarcodeGenerated,
  });

  @override
  State<_BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<_BarcodePrintDialog> {
  late String _barcodeValue;
  late final TextEditingController _barcodeCtrl;
  final _copiesCtrl = TextEditingController(text: '1');
  bool _printing = false;
  bool _saved = false;

  // Effective target — a size (variant) if one was passed, else the whole item.
  String? get _existingBarcode => widget.variant?.barcode ?? widget.item.barcode;
  String get _targetId => widget.variant?.id ?? widget.item.id;
  // 0 when neither is priced — a barcode label for a sized item is printed per
  // size, so the parent's own (null) price is never the one shown.
  double get _targetPrice =>
      widget.variant?.price ?? widget.item.price ?? 0.0;
  String? get _subtitle => widget.variant?.label;

  @override
  void initState() {
    super.initState();
    // Use existing barcode or auto-generate one from the target's id
    _barcodeValue = _existingBarcode ?? _generateBarcode(_targetId);
    _barcodeCtrl = TextEditingController(text: _barcodeValue);
    _barcodeCtrl.addListener(() {
      final v = _barcodeCtrl.text.trim();
      if (v.isNotEmpty && v != _barcodeValue) {
        setState(() => _barcodeValue = v);
      }
    });
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _copiesCtrl.dispose();
    super.dispose();
  }

  /// Generate a numeric barcode from the item's UUID (12 digits, EAN-13 compatible)
  static String _generateBarcode(String id) {
    // Take first 12 hex chars of the id and convert to digits
    final hex = id.replaceAll('-', '');
    final digits = hex.substring(0, 12).split('').map((c) {
      final code = c.codeUnitAt(0);
      // 0-9 → same digit; a-f → 0-5
      return code >= 48 && code <= 57 ? c : (code - 97).toString();
    }).join();
    return digits.padLeft(12, '0');
  }

  Future<void> _print() async {
    final copies = int.tryParse(_copiesCtrl.text.trim()) ?? 1;
    if (copies < 1) return;

    final sentMessage = context.l10n.itemsBarcodeSentToPrinter;
    setState(() => _printing = true);
    try {
      // If the target had no barcode, save the generated one first
      if (_existingBarcode == null && !_saved) {
        await widget.onBarcodeGenerated(_barcodeValue);
        _saved = true;
      }
      await PrinterService.instance.printBarcodeLabel(
        barcodeValue: _barcodeValue,
        itemName: widget.item.name,
        price: _targetPrice,
        subtitle: _subtitle,
        copies: copies,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sentMessage)),
        );
        Navigator.pop(context);
      }
    } on PrinterException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(sanitizeUiErrorMessage(e)),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _existingBarcode == null;
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(isNew
          ? l10n.itemsBarcodeGenerateTitle
          : l10n.itemsBarcodePrintTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isNew)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.itemsBarcodeGeneratedNote,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              // Barcode preview
              Center(
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: _barcodeValue.isEmpty ? '000000000000' : _barcodeValue,
                  width: 280,
                  height: 80,
                  drawText: true,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  widget.item.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              if (_subtitle != null)
                Center(
                  child: Text(
                    _subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              Center(
                child: Text(
                  '₹${_targetPrice.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: l10n.itemsBarcodeValue,
                controller: _barcodeCtrl,
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: l10n.itemsBarcodeCopies,
                controller: _copiesCtrl,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        ElevatedButton.icon(
          onPressed: _printing ? null : _print,
          icon: _printing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(l10n.commonPrint),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Variant (sizes) manager — list, add and delete sizes for an existing item.
// Talks to the API directly; calls onChanged() to reload the catalog.
// ---------------------------------------------------------------------------
class _VariantManagerDialog extends StatefulWidget {
  final Item item;
  final bool inventoryEnabled;
  final void Function(List<ItemVariant> variants) onChanged;

  const _VariantManagerDialog({
    required this.item,
    required this.inventoryEnabled,
    required this.onChanged,
  });

  @override
  State<_VariantManagerDialog> createState() => _VariantManagerDialogState();
}

class _VariantManagerDialogState extends State<_VariantManagerDialog> {
  late List<ItemVariant> _variants;
  final _labelCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _variants = [...widget.item.variants];
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    setState(() => _busy = true);
    try {
      final barcode = _barcodeCtrl.text.trim();
      final data = <String, dynamic>{
        'label': label,
        if (_priceCtrl.text.trim().isNotEmpty)
          'price': double.tryParse(_priceCtrl.text.trim()),
        if (barcode.isNotEmpty) 'barcode': barcode,
        if (widget.inventoryEnabled && _stockCtrl.text.trim().isNotEmpty)
          'stock_quantity': double.tryParse(_stockCtrl.text.trim()),
        'sort_order': _variants.length,
      };
      final created = await createVariant(widget.item.id, data);
      setState(() {
        _variants.add(ItemVariant.fromJson(created));
        _labelCtrl.clear();
        _priceCtrl.clear();
        _stockCtrl.clear();
        _barcodeCtrl.clear();
      });
      widget.onChanged(List.unmodifiable(_variants));
    } on ApiException catch (e) {
      _snack(sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ItemVariant v) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(l10n.itemsSizeDeleteConfirm(v.label)),
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
    setState(() => _busy = true);
    try {
      await deleteVariant(widget.item.id, v.id);
      setState(() => _variants.removeWhere((x) => x.id == v.id));
      widget.onChanged(List.unmodifiable(_variants));
    } on ApiException catch (e) {
      _snack(sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  /// Generate/print a barcode label for a single size. Persists the generated
  /// barcode onto the variant so future scans and reprints match.
  void _printVariantBarcode(ItemVariant v) {
    showDialog(
      context: context,
      builder: (_) => _BarcodePrintDialog(
        item: widget.item,
        variant: v,
        onBarcodeGenerated: (newBarcode) async {
          final result =
              await updateVariant(widget.item.id, v.id, {'barcode': newBarcode});
          final updated = ItemVariant.fromJson(result);
          if (!mounted) return;
          setState(() {
            final i = _variants.indexWhere((x) => x.id == v.id);
            if (i != -1) _variants[i] = updated;
          });
          widget.onChanged(List.unmodifiable(_variants));
        },
      ),
    );
  }

  /// Edit (or clear) the barcode value of an existing size. Persists the change
  /// and patches the local list so scans/prints use the new value immediately.
  Future<void> _editVariantBarcode(ItemVariant v) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController(text: v.barcode ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.itemsSizeBarcodeEditTitle(v.label)),
        content: AppTextField(
          label: l10n.itemsSizeBarcodeOptional,
          controller: ctrl,
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(l10n.commonCancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(l10n.commonSave)),
        ],
      ),
    );
    ctrl.dispose();
    if (saved != true) return;

    final newBarcode = ctrl.text.trim();
    // No change → skip the round-trip.
    if (newBarcode == (v.barcode ?? '')) return;

    setState(() => _busy = true);
    try {
      // Empty string clears the barcode (backend maps '' → null).
      final result = await updateVariant(
          widget.item.id, v.id, {'barcode': newBarcode.isEmpty ? null : newBarcode});
      final updated = ItemVariant.fromJson(result);
      if (!mounted) return;
      setState(() {
        final i = _variants.indexWhere((x) => x.id == v.id);
        if (i != -1) _variants[i] = updated;
      });
      widget.onChanged(List.unmodifiable(_variants));
    } on ApiException catch (e) {
      _snack(sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.itemsSizesTitle(widget.item.name),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_variants.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l10n.itemsNoSizesYet,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                )
              else
                ..._variants.map((v) {
                  // A size inherits the item's price only when the item has one;
                  // a sized item's own price is null.
                  final price = v.price ?? widget.item.price;
                  final sub = [
                    price == null ? '—' : '₹${price.toStringAsFixed(2)}',
                    if (widget.inventoryEnabled && v.stockQuantity != null)
                      l10n.itemsStockLabel(formatQty(v.stockQuantity!)),
                  ].join('  ·  ');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(sub,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.itemsSizeBarcodeEditTitle(v.label),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.textSecondary),
                          onPressed:
                              _busy ? null : () => _editVariantBarcode(v),
                        ),
                        IconButton(
                          tooltip: l10n.itemsBarcodePrintTitle,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: Icon(
                            v.barcode != null
                                ? Icons.qr_code_2
                                : Icons.qr_code_2_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          onPressed: _busy ? null : () => _printVariantBarcode(v),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          onPressed: _busy ? null : () => _delete(v),
                        ),
                      ],
                    ),
                  );
                }),
              const Divider(height: 20),
              AppTextField(
                  label: l10n.itemsSizeLabel,
                  controller: _labelCtrl,
                  capitalizeWords: true),
              const SizedBox(height: AppSpacing.space8),
              AppTextField(
                label: l10n.itemsSizePrice,
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              if (widget.inventoryEnabled) ...[
                const SizedBox(height: AppSpacing.space8),
                AppTextField(
                  label: l10n.itemsSizeStock,
                  controller: _stockCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              const SizedBox(height: AppSpacing.space8),
              // Optional barcode for this size. Leave blank to auto-generate
              // one later via the print (QR) button on the size row.
              AppTextField(
                label: l10n.itemsSizeBarcodeOptional,
                controller: _barcodeCtrl,
                keyboardType: TextInputType.text,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose)),
        ElevatedButton.icon(
          onPressed: _busy ? null : _add,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add, size: 18),
          label: Text(l10n.itemsAddSize),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-size stock editor — shown for items that have sizes. Each size has its
// own editable stock field; Update saves only the sizes that changed.
// ---------------------------------------------------------------------------
class _VariantStockDialog extends StatefulWidget {
  final Item item;
  final void Function(List<ItemVariant> variants) onSaved;
  final VoidCallback onEditTapped;

  const _VariantStockDialog({
    required this.item,
    required this.onSaved,
    required this.onEditTapped,
  });

  @override
  State<_VariantStockDialog> createState() => _VariantStockDialogState();
}

class _VariantStockDialogState extends State<_VariantStockDialog> {
  late final List<ItemVariant> _variants;
  late final Map<String, TextEditingController> _ctrls;
  bool _saving = false;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _variants = [...widget.item.variants];
    // Fields hold the quantity to ADD/REMOVE relative to current stock — start empty.
    _ctrls = {
      for (final v in _variants) v.id: TextEditingController(),
    };
    for (final c in _ctrls.values) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Quantity entered for a size (0 when blank/invalid), always positive.
  double _entered(ItemVariant v) =>
      double.tryParse(_ctrls[v.id]!.text.trim()) ?? 0;

  // Signed adjustment for a size, depending on the Add/Remove mode.
  double _adding(ItemVariant v) => _removing ? -_entered(v) : _entered(v);

  bool get _anyInput => _variants.any((v) => _entered(v) > 0);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = <ItemVariant>[];
      for (final v in _variants) {
        final entered = _entered(v);
        // Skip sizes with no quantity entered.
        if (entered <= 0) {
          updated.add(v);
          continue;
        }
        // Stock can never go negative, regardless of how much was requested to remove.
        final newStock =
            ((v.stockQuantity ?? 0) + _adding(v)).clamp(0, double.infinity);
        final result = await updateVariant(
          widget.item.id,
          v.id,
          {'stock_quantity': newStock},
        );
        updated.add(ItemVariant.fromJson(result));
      }
      widget.onSaved(List.unmodifiable(updated));
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sanitizeUiErrorMessage(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Dialog width: roomy on desktop/tablet, compact on phones. Uses the same
  /// 720 breakpoint as the items list. Always capped to the available width
  /// (less the dialog's own margins) so a small window can't overflow.
  static double _dialogWidth(BuildContext context) {
    final screen = MediaQuery.of(context).size.width;
    final target = screen >= 720 ? 520.0 : 360.0;
    return target.clamp(0.0, screen - 80).toDouble();
  }

  /// Quantity field width — wide enough for the full "Add quantity" label when
  /// the dialog is wide, otherwise the original compact size.
  static double _qtyFieldWidth(BuildContext context) =>
      MediaQuery.of(context).size.width >= 720 ? 170.0 : 110.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(l10n.itemsSizesTitle(widget.item.name),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: l10n.itemsEditItemTooltip,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: widget.onEditTapped,
          ),
        ],
      ),
      content: SizedBox(
        // Wider on a large window (desktop) so the quantity field can show its
        // full "Add quantity" label instead of truncating to "Add qu…". Falls
        // back to the compact width on phones, capped to the screen so a small
        // window never overflows.
        width: _dialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Add / Remove mode toggle — applies to all sizes below.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space12),
                child: SegmentedButton<bool>(
                  // expandedInsets keeps both segments equal-width so the
                  // control's layout stays static when the mode is toggled.
                  expandedInsets: EdgeInsets.zero,
                  segments: [
                    ButtonSegment(
                        value: false, label: Text(l10n.itemsStockModeAdd)),
                    ButtonSegment(
                        value: true, label: Text(l10n.itemsStockModeRemove)),
                  ],
                  selected: {_removing},
                  onSelectionChanged: (selection) {
                    setState(() => _removing = selection.first);
                  },
                ),
              ),
              for (final v in _variants)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(v.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${l10n.itemsCurrentStock}: ${v.stockQuantity != null ? '${formatQty(v.stockQuantity!)} ${itemUnitLabel(context, widget.item.unit)}' : '—'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            // Live preview of the resulting stock after the adjustment.
                            if (_entered(v) > 0)
                              Text(
                                '${_removing ? l10n.itemsTotalAfterRemoving : l10n.itemsTotalAfterAdding}: ${formatQty(((v.stockQuantity ?? 0) + _adding(v)).clamp(0, double.infinity))} ${itemUnitLabel(context, widget.item.unit)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        // 110 was too narrow for the "Add quantity" label, which
                        // truncated to "Add qu…". Widen it wherever the dialog
                        // itself is wide enough to afford it.
                        width: _qtyFieldWidth(context),
                        child: AppTextField(
                          label: _removing
                              ? l10n.itemsRemoveQuantity
                              : l10n.itemsAddQuantity,
                          controller: _ctrls[v.id]!,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ],
                  ),
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
          onPressed: (_saving || !_anyInput) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(l10n.commonUpdate),
        ),
      ],
    );
  }
}
