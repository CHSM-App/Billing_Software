import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../api.dart';
import '../services/printer_service.dart';
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
    return items.where((i) => i.name.toLowerCase().contains(q)).toList();
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
        categories: categories,
        onSaved: (data) async {
          if (item == null) {
            await ref.read(itemsProvider.notifier).addItem(data);
          } else {
            await ref.read(itemsProvider.notifier).updateItem(item.id, data);
          }
          await ref.read(categoriesProvider.notifier).reload();
        },
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
            SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
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
              automaticallyImplyLeading: false),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.space8, AppSpacing.space4, AppSpacing.space8, 96),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.space8,
          mainAxisSpacing: 6,
          mainAxisExtent: 52,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          final stockMode = _showStock && inventoryEnabled;
          // Cross-fade + scale between the normal card and the stock card when
          // the overview is toggled. The ValueKey drives the transition.
          final child = stockMode
              ? buildStockCard(
                  context,
                  StockOverviewRow(
                    name: it.name,
                    stockQuantity: it.stockQuantity,
                    unitLabel: itemUnitLabel(context, it.unit),
                    isLowStock: it.isLowStock,
                  ),
                )
              : _buildItemCard(it, userRole, inventoryEnabled);
          return animatedCardSwap(stockMode, child);
        },
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
                // Price
                Text(
                  '₹${item.price.toStringAsFixed(2)}',
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

  double get _current => widget.item.stockQuantity ?? 0;
  double get _adding => double.tryParse(_addCtrl.text.trim()) ?? 0;
  double get _total => _current + _adding;

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
    if (_adding <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.onStockUpdated(_total);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasInput = _adding > 0;
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
                Text('₹${item.price.toStringAsFixed(2)}',
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
              AppTextField(
                label: l10n.itemsAddQuantity,
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
                      child: Text(l10n.itemsTotalAfterAdding,
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
// Add / Edit item dialog — stays StatefulWidget (no need for Riverpod here)
// ---------------------------------------------------------------------------
class _ItemFormDialog extends StatefulWidget {
  final Item? item;
  final bool inventoryEnabled;
  final List<String> categories;
  final Future<void> Function(Map<String, dynamic> data) onSaved;
  final VoidCallback? onManageSizes;
  final VoidCallback? onManageRecipe;

  const _ItemFormDialog(
      {this.item,
      required this.inventoryEnabled,
      this.categories = const [],
      required this.onSaved,
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
  final _barcodeCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  String _unit = 'piece';
  bool _saving = false;

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
      _barcodeCtrl.text = item.barcode ?? '';
      _stockCtrl.text = item.stockQuantity?.toString() ?? '';
      _unit = _units.contains(item.unit) ? item.unit : 'piece';
    }
  }

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
    _barcodeCtrl.dispose();
    _stockCtrl.dispose();
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Auto-generate a 12-digit barcode for new items that have no barcode.
    // Use current timestamp so it's unique and scannable immediately.
    final barcodeInput = _barcodeCtrl.text.trim();
    final autoBarcode = (widget.item == null && barcodeInput.isEmpty)
        ? DateTime.now().millisecondsSinceEpoch.toString().substring(1, 13)
        : null;

    // Items with sizes track stock per size — force item-level stock to null so
    // it is never considered.
    final hasVariants = widget.item?.hasVariants ?? false;

    final data = {
      'name': _nameCtrl.text.trim(),
      if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
      'price': double.parse(_priceCtrl.text.trim()),
      if (_taxCtrl.text.trim().isNotEmpty)
        'tax_rate': double.parse(_taxCtrl.text.trim()),
      'barcode': barcodeInput.isNotEmpty ? barcodeInput : autoBarcode,
      'unit': _unit,
      if (widget.inventoryEnabled && hasVariants)
        'stock_quantity': null
      else if (widget.inventoryEnabled && _stockCtrl.text.trim().isNotEmpty)
        'stock_quantity': double.parse(_stockCtrl.text.trim()),
    };

    try {
      await widget.onSaved(data);
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: l10n.itemsFieldName,
                  controller: _nameCtrl,
                  validator: (v) =>
                      v == null || v.isEmpty ? l10n.commonRequired : null,
                ),
                const SizedBox(height: AppSpacing.space12),
                _buildCategoryField(context, l10n),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: l10n.itemsFieldPrice,
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
                const SizedBox(height: AppSpacing.space12),
                DropdownButtonFormField<String>(
                  initialValue: _unit,
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
                AppTextField(
                  label: l10n.itemsFieldBarcode,
                  controller: _barcodeCtrl,
                  keyboardType: TextInputType.number,
                ),
                // Item-level stock is only meaningful when the item has NO
                // sizes. With sizes, stock is tracked per size, so hide it and
                // show a hint pointing to the size manager.
                if (widget.inventoryEnabled &&
                    !(widget.item?.hasVariants ?? false)) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldStock,
                    controller: _stockCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                if (widget.onManageSizes != null) ...[
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
  final Future<void> Function(String barcode) onBarcodeGenerated;

  const _BarcodePrintDialog({
    required this.item,
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

  @override
  void initState() {
    super.initState();
    // Use existing barcode or auto-generate one from the item id
    _barcodeValue = widget.item.barcode ?? _generateBarcode(widget.item.id);
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
      // If item had no barcode, save the generated one first
      if (widget.item.barcode == null && !_saved) {
        await widget.onBarcodeGenerated(_barcodeValue);
        _saved = true;
      }
      await PrinterService.instance.printBarcodeLabel(
        barcodeValue: _barcodeValue,
        itemName: widget.item.name,
        price: widget.item.price,
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
              content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item.barcode == null;
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
              Center(
                child: Text(
                  '₹${widget.item.price.toStringAsFixed(2)}',
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
    super.dispose();
  }

  Future<void> _add() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        'label': label,
        if (_priceCtrl.text.trim().isNotEmpty)
          'price': double.tryParse(_priceCtrl.text.trim()),
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
      });
      widget.onChanged(List.unmodifiable(_variants));
    } on ApiException catch (e) {
      _snack(e.message);
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
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
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
                  final price = v.price ?? widget.item.price;
                  final sub = [
                    '₹${price.toStringAsFixed(2)}',
                    if (widget.inventoryEnabled && v.stockQuantity != null)
                      l10n.itemsStockLabel(formatQty(v.stockQuantity!)),
                  ].join('  ·  ');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(sub),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.error),
                      onPressed: _busy ? null : () => _delete(v),
                    ),
                  );
                }),
              const Divider(height: 20),
              AppTextField(
                  label: l10n.itemsSizeLabel, controller: _labelCtrl),
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

  @override
  void initState() {
    super.initState();
    _variants = [...widget.item.variants];
    // Fields hold the quantity to ADD to the current stock — start empty.
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

  // Quantity being added for a size (0 when blank/invalid).
  double _adding(ItemVariant v) =>
      double.tryParse(_ctrls[v.id]!.text.trim()) ?? 0;

  bool get _anyInput => _variants.any((v) => _adding(v) > 0);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = <ItemVariant>[];
      for (final v in _variants) {
        final adding = _adding(v);
        // Skip sizes with no quantity added.
        if (adding <= 0) {
          updated.add(v);
          continue;
        }
        final newStock = (v.stockQuantity ?? 0) + adding;
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
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                            // Live preview of the resulting stock after adding.
                            if (_adding(v) > 0)
                              Text(
                                '${l10n.itemsTotalAfterAdding}: ${formatQty((v.stockQuantity ?? 0) + _adding(v))} ${itemUnitLabel(context, widget.item.unit)}',
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
                        width: 110,
                        child: AppTextField(
                          label: l10n.itemsAddQuantity,
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
