import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/jpeg_compress.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/category_tree_list.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/floating_bar_physics.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/skeletons.dart';
import '../widgets/warranty_extra_fields_editor.dart'
    show WarrantyLabelField, allTemplateLabels;
import '../api.dart';
import '../services/printer_service.dart';
import 'menu_photos_screen.dart';
import 'major_category_order_screen.dart';
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
    case 'packet':
      return l10n.itemsUnitPacket;
    case 'box':
      return l10n.itemsUnitBox;
    case 'bottle':
      return l10n.itemsUnitBottle;
    case 'pair':
      return l10n.itemsUnitPair;
    case 'set':
      return l10n.itemsUnitSet;
    case 'bundle':
      return l10n.itemsUnitBundle;
    case 'bag':
      return l10n.itemsUnitBag;
    case 'sqft':
      return l10n.itemsUnitSqft;
    case 'ton':
      return l10n.itemsUnitTon;
    case 'quintal':
      return l10n.itemsUnitQuintal;
    case 'roll':
      return l10n.itemsUnitRoll;
    case 'case':
      return l10n.itemsUnitCase;
    case 'crate':
      return l10n.itemsUnitCrate;
    case 'carton':
      return l10n.itemsUnitCarton;
    default:
      return l10n.itemsUnitPiece;
  }
}

/// Units a pack can be. A subset of the item units — a pack is something you
/// count, never a weight.
const _packUnits = [
  'box', 'case', 'crate', 'carton', 'packet', 'dozen', 'bag',
  'bundle', 'set', 'roll',
];

/// Wire fields for a pack row. Always sends both, so choosing "No pack" clears.
Map<String, dynamic> _packPayload(String? unit, TextEditingController size) => {
      'pack_unit': unit,
      'pack_size': unit == null ? null : double.tryParse(size.text.trim()),
    };

/// "Sold in packs: [Box ▾]   1 Box = [15] bottle" — the optional pack of an
/// item or one size. Entry/display only: billing shows 17 as "1 box + 2" and can
/// add a whole box in one tap; stock and bills stay in [baseUnit].
class _PackRow extends StatelessWidget {
  final String? unit;
  final TextEditingController size;
  final String baseUnit;
  final ValueChanged<String?>? onUnitChanged;

  const _PackRow({
    required this.unit,
    required this.size,
    required this.baseUnit,
    required this.onUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: _packUnits.contains(unit) ? unit : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.itemsFieldPack),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.itemsPackNone)),
              for (final u in _packUnits)
                DropdownMenuItem(
                  value: u,
                  child: Text(itemUnitLabel(context, u),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onUnitChanged,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            child: AppTextField(
              label: l10n.itemsFieldPackSize(itemUnitLabel(context, unit!)),
              controller: size,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              suffixIcon: UnitSuffix(itemUnitLabel(context, baseUnit)),
              validator: (v) => (double.tryParse(v?.trim() ?? '') ?? 0) > 1
                  ? null
                  : l10n.itemsPackSizeInvalid,
            ),
          ),
        ],
      ],
    );
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
    with TickerProviderStateMixin, CategoryTreeNav<ItemsScreen> {
  final _searchController = TextEditingController();
  TabController? _tabController;
  int _activeTab = 0;

  /// The header — app bar, Items/Raw tabs, search box — folds away with the
  /// list on a phone, as one block, while the major/minor strip below it stays
  /// pinned. See [FoldingHeader].
  late final FoldingHeader _header = FoldingHeader(
    vsync: this,
    extent: () => _topBarHeight + _searchBarHeight,
    // Not while typing: the search box would fold away under the keyboard.
    // (View, not MediaQuery — the Scaffolds above strip the keyboard inset.)
    canFold: () =>
        View.of(context).viewInsets.bottom == 0 &&
        MediaQuery.sizeOf(context).width < 720,
  );

  /// ShellAppBar (50 + divider), plus the Items/Raw tab bar when it shows.
  double get _topBarHeight =>
      51 + ((_tabController?.length ?? 1) > 1 ? kTextTabBarHeight : 0);

  /// [_searchBar]: 6 + 40 + 4.
  static const double _searchBarHeight = 50;
  // When on, the Items list renders a compact stock overview (name + remaining
  // stock) in place, instead of the normal cards.
  bool _showStock = false;

  // The item list is the billing screen's tree (see CategoryTreeNav): major
  // cards with a jump strip on top when the menu has majors, otherwise the
  // category cards with a category strip.

  @override
  void initState() {
    super.initState();
    initTreeNav();
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
          _header.show(); // the Raw tab does not fold it
        }
      });
    _activeTab = 0;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController?.dispose();
    _header.dispose();
    disposeTreeNav();
    super.dispose();
  }

  List<Item> _filtered(List<Item> items) {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return items;
    return items.where((i) {
      final name = i.name.toLowerCase();
      final category = (i.category ?? '').toLowerCase();
      return name.contains(q) ||
          category.contains(q) ||
          (i.itemNo ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// Barcode label for an item row.
  ///
  /// A sized item has no price of its own — each size carries one — so it must
  /// be printed per size. Printing the parent produced a label reading
  /// "Rs. 0.00" and saved a barcode onto the priceless parent, giving a
  /// scannable code that resolves to nothing sellable. Ask which size first.
  Future<void> _showBarcodePrint(Item item) async {
    if (!item.hasVariants) {
      _showBarcodePrintFor(item, null);
      return;
    }
    final variant = await _pickVariantForBarcode(item);
    if (variant == null || !mounted) return;
    _showBarcodePrintFor(item, variant);
  }

  /// Size chooser shown before printing a sized item's label. Lists each size
  /// with the price that will actually be printed on it.
  Future<ItemVariant?> _pickVariantForBarcode(Item item) {
    final l10n = context.l10n;
    return showDialog<ItemVariant>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.itemsPickSizeForBarcode),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final v in item.variants)
                ListTile(
                  dense: true,
                  title: Text(v.label),
                  // The price shown here is exactly what lands on the label.
                  trailing: Text(
                    '₹${(v.price ?? item.price ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(ctx, v),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }

  /// Opens the print dialog and persists the generated barcode onto whichever
  /// row actually owns it — the size when there is one, else the item. Saving a
  /// size's barcode onto the parent is what made a scan resolve to the parent.
  void _showBarcodePrintFor(Item item, ItemVariant? variant) {
    showDialog(
      context: context,
      builder: (_) => _BarcodePrintDialog(
        item: item,
        variant: variant,
        onBarcodeGenerated: (newBarcode) async {
          if (variant == null) {
            await ref
                .read(itemsProvider.notifier)
                .updateItem(item.id, {'barcode': newBarcode});
            return;
          }
          final result =
              await updateVariant(item.id, variant.id, {'barcode': newBarcode});
          final updated = ItemVariant.fromJson(result);
          // Patch local state so a reprint uses the value just saved.
          ref.read(itemsProvider.notifier).setItemVariants(
                item.id,
                [
                  for (final v in item.variants)
                    v.id == updated.id ? updated : v,
                ],
              );
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
    // item to attach to. A SIZED item has no recipe of its own — each size
    // carries one — so its item-level button is hidden; otherwise an owner
    // could fill in a recipe no bill would ever reach.
    final showRecipe = isRestaurant &&
        inventoryEnabled &&
        item != null &&
        !item.hasVariants;
    // Existing categories for this business, to offer as dropdown suggestions.
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    // …and the same, one level up, so the Major Category field can suggest the
    // groups already in use and the Category field can scope to the one typed.
    final categoryTree =
        ref.read(categoryTreeProvider).valueOrNull ?? const <String, List<String>>{};
    showDialog(
      context: context,
      builder: (_) => _ItemFormDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        gstEnabled: gstEnabled,
        categories: categories,
        categoryTree: categoryTree,
        onSaved: (data, variants) async {
          final saved = item == null
              ? await ref.read(itemsProvider.notifier).addItem(data)
              : await ref.read(itemsProvider.notifier).updateItem(item.id, data);
          await ref.read(categoriesProvider.notifier).reload();
          await ref.read(categoryTreeProvider.notifier).reload();
          // Spread open the saved item's category so the owner sees the new
          // (or moved) row instead of a folded bar.
          if (mounted) revealSection(saved.majorCategory, saved.category ?? '');
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
        isWarrantyShop: ref.read(warrantyEnabledProvider),
        onManageWarrantyFields: ref.read(warrantyEnabledProvider)
            ? (category) => _showWarrantyFieldTemplateEditor(category)
            : null,
      ),
    );
  }

  /// Opens the editor for [category]'s custom warranty fields (e.g. "KM
  /// Reading"/"Vehicle Number" for Tyres) — see warranty_field_templates.js.
  void _showWarrantyFieldTemplateEditor(String category) {
    showDialog(
      context: context,
      builder: (_) => _WarrantyFieldTemplateDialog(category: category),
    );
  }

  void _showVariantManager(Item item) {
    final inventoryEnabled = ref.read(inventoryEnabledProvider);
    final businessType = ref.read(businessTypeProvider);
    final isRestaurant = businessType == 'restaurant_with_tables' ||
        businessType == 'restaurant_no_tables';
    showDialog(
      context: context,
      builder: (_) => _VariantManagerDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        // A sized item's recipes live here, one per size.
        showRecipe: isRestaurant && inventoryEnabled,
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
    // Nothing to reorder for a business that has never filed an item under a
    // major category — same "real majors only" filter the billing chip strip
    // itself uses, so this button appears exactly when that strip does.
    final hasMajors = (ref.watch(categoryTreeProvider).valueOrNull ?? {})
        .keys
        .any((m) => m.isNotEmpty);
    final onRawTab = withRawMaterials && _activeTab == 1;
    // Folded on a phone, then widened (where it never folds): open it back up.
    if (MediaQuery.sizeOf(context).width >= 720 && _header.bar.value < 1) {
      _header.bar.value = 1;
    }

    return Scaffold(
      body: Column(
        children: [
          // The status-bar band stays put; the header folds away beneath it.
          ColoredBox(
            color: AppColors.surface,
            child: SizedBox(
                width: double.infinity,
                height: MediaQuery.paddingOf(context).top),
          ),
          // Folds first; the search box below it folds once this has gone, so
          // the whole header slides up as one block.
          FoldAway(
            bar: FoldAway.slice(_header.bar,
                below: _searchBarHeight,
                height: _topBarHeight,
                total: _topBarHeight + _searchBarHeight),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Bottom-bar root tab: never imply a back arrow. Without this,
          // opening a dialog (add item / stock) pushes a route and flips
          // Navigator.canPop() to true, making a stray back arrow appear.
          ShellAppBar(
              title: Text(l10n.itemsTitle),
              automaticallyImplyLeading: false,
              // Owners manage customer-facing dish photos here. Photos live in a
              // dedicated screen and never appear during billing. Restaurants
              // only — a retail shop has no QR menu for the photos to appear on.
              actions: userRole == 'owner'
                  ? [
                      if (hasMajors)
                        IconButton(
                          icon: const Icon(Icons.swap_vert_outlined),
                          color: AppColors.textPrimary,
                          tooltip: l10n.categoryOrderTooltip,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const MajorCategoryOrderScreen()),
                          ),
                        ),
                      // if (isRestaurant)
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
              ]),
            ),
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
          // Lifted clear of the floating glass nav bar, and dropped out of
          // sight along with it when scrolling hides the bar (2 = its own
          // height plus the bottom margin, so it fully clears the edge).
          ? HidesWithNavBar(
              drop: 2,
              child: Padding(
              padding:
                  EdgeInsets.only(bottom: AppBottomNavBar.fabLift(context)),
              child: FloatingActionButton.extended(
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
            ),
          ),
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

  /// Search box (+ stock-overview toggle) that sits above the list. It is a
  /// plain widget rather than a sliver so the sheet's scroll offsets stay
  /// list-local — a chip tap can then compute its target exactly.
  Widget _searchBar({bool inventoryEnabled = false}) => Padding(
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
        Future<void> refresh() async {
          ref.invalidate(itemsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(categoryTreeProvider);
          await ref.read(itemsProvider.future);
        }

        // Same sources and order as the billing list: the owner's major order,
        // falling back to the majors in use. Empty → no major level at all.
        final cats =
            ref.watch(categoriesProvider).valueOrNull ?? const <String>[];
        final majors = ref.watch(majorCategoryOrderProvider).valueOrNull ??
            (ref.watch(categoryTreeProvider).valueOrNull ?? {})
                .keys
                .where((m) => m.isNotEmpty)
                .toList();
        final stockMode = _showStock && inventoryEnabled;
        // Built before the strip, which reads the tree it lists.
        final tree = stockMode
            ? const <TreeMajor>[]
            : buildTree(items, cats, majors,
                searching: _searchController.text.trim().isNotEmpty,
                // Two columns only where the sheet is wide enough for two rows.
                twoColumns: MediaQuery.of(context).size.width >= 900);
        final strip = (stockMode || allItems.isEmpty)
            ? null
            : buildTreeStrip(majors, cats);

        final Widget list;
        if (items.isEmpty) {
          list = CustomScrollView(
            physics: _header.physics,
            slivers: [
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
            ],
          );
        } else if (stockMode) {
          final isWide = MediaQuery.of(context).size.width >= 720;
          list = CustomScrollView(
            physics: _header.physics,
            slivers: [
              _buildStockSliver(items, crossAxisCount: isWide ? 3 : 1),
            ],
          );
        } else {
          list = _buildTreeList(tree, userRole, inventoryEnabled);
        }

        // The search box folds with the header above it; the major/minor
        // strip does not, so it ends up pinned at the top.
        return Column(
          children: [
            FoldAway(
              bar: FoldAway.slice(_header.bar,
                  below: 0,
                  height: _searchBarHeight,
                  total: _topBarHeight + _searchBarHeight),
              child: _searchBar(inventoryEnabled: inventoryEnabled),
            ),
            if (strip != null) strip,
            Expanded(
              // The list's scrolls carry and settle the header's fold.
              child: NotificationListener<ScrollNotification>(
                onNotification: _header.onScroll,
                child: RefreshIndicator(onRefresh: refresh, child: list),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The billing-style tree: major cards, category cards, item rows.
  Widget _buildTreeList(
      List<TreeMajor> tree, String userRole, bool inventoryEnabled) {
    final isOwner = userRole == 'owner';
    return CategoryTreeList(
      tree: tree,
      controller: treeScrollCtrl,
      physics: _header.physics,
      twoColumns: MediaQuery.of(context).size.width >= 900,
      onToggleMajor: toggleMajor,
      onToggleSection: toggleCategory,
      itemBuilder: (item, index) => _ItemSheetRow(
        index: index,
        item: item,
        inventoryEnabled: inventoryEnabled,
        isOwner: isOwner,
        onTap: () => _showStockPopup(item),
        onBarcode: () => _showBarcodePrint(item),
        onDelete: isOwner ? () => _deleteItem(item) : null,
      ),
    );
  }

  /// Stock-overview mode. Item cards with variants expand to a variable-height
  /// list of their variants. A fixed-extent grid can't handle that, so use a
  /// masonry column layout (same approach as the Kitchen screen): split cards
  /// across N columns, each keeping its natural height, packed into the
  /// shortest column so there are no big gaps.
  Widget _buildStockSliver(List<Item> items, {int crossAxisCount = 1}) {
    final padding = EdgeInsets.fromLTRB(AppSpacing.space8, AppSpacing.space4,
        AppSpacing.space8, 96 + MediaQuery.paddingOf(context).bottom);

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

}

// ---------------------------------------------------------------------------
// Item row of the billing-style tree (see widgets/category_tree_list.dart).
// ---------------------------------------------------------------------------

/// One item row of the sheet: running number, name (+ stock / sizes line),
/// price, and the barcode / delete actions. Tap opens the stock popup.
class _ItemSheetRow extends StatelessWidget {
  final int index;
  final Item item;
  final bool inventoryEnabled;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback onBarcode;
  final VoidCallback? onDelete;

  const _ItemSheetRow({
    required this.index,
    required this.item,
    required this.inventoryEnabled,
    required this.isOwner,
    required this.onTap,
    required this.onBarcode,
    required this.onDelete,
  });

  static const double indexWidth = 24;
  static const double priceWidth = 72;
  static const double _iconTap = 26;

  /// Space the action icons take: barcode, plus delete for owners.
  static double actionsWidth(bool isOwner) =>
      isOwner ? _iconTap * 2 + 2 : _iconTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hint = <String>[
      if (item.hasVariants) l10n.billingSizesCount(item.variants.length),
      if (inventoryEnabled && !item.hasVariants && item.stockQuantity != null)
        l10n.itemsStockLabel(formatQty(item.stockQuantity!)),
    ].join('  ·  ');
    final lowStock = inventoryEnabled && item.isLowStock;
    // Orange at the low-stock alert, red at zero — same stripe as Billing.
    final stockColor = inventoryEnabled ? stockAlertColor(item) : null;

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: stockColor == null
            ? null
            : Border(left: BorderSide(color: stockColor, width: 3)),
      ),
      child: Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: indexWidth,
                child: Text(
                  '$index',
                  textAlign: TextAlign.right,
                  style: AppFont.style(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    if (hint.isNotEmpty || lowStock)
                      Row(
                        children: [
                          if (hint.isNotEmpty)
                            Flexible(
                              child: Text(
                                hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFont.style(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          if (lowStock) ...[
                            if (hint.isNotEmpty) const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                hint.isNotEmpty
                                    ? '· ${l10n.itemsLowStock}'
                                    : l10n.itemsLowStock,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFont.style(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              // Price — a range for a sized item, whose own price is null.
              SizedBox(
                width: priceWidth,
                child: Text(
                  itemPriceLabel(item),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: actionsWidth(isOwner),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _RowIcon(
                      icon: Icons.qr_code_outlined,
                      color: item.barcode != null
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      onTap: onBarcode,
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 2),
                      _RowIcon(
                        icon: Icons.delete_outline,
                        color: AppColors.error,
                        onTap: onDelete!,
                      ),
                    ],
                  ],
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

class _RowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RowIcon({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: _ItemSheetRow._iconTap,
          height: _ItemSheetRow._iconTap,
          child: Icon(icon, size: 16, color: color),
        ),
      );
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
                    // Shown as "Major › Category" once the item is filed under
                    // a group, so the row says where it actually lives.
                    child: Text(
                        item.majorCategory == null
                            ? item.category!
                            : '${item.majorCategory} › ${item.category}',
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
  final packSize = TextEditingController();
  String? packUnit;

  /// A row the user added and then left completely untouched. Dropped silently
  /// on save — a trailing blank row is a change of mind, not an error.
  bool get isBlank =>
      label.text.trim().isEmpty &&
      price.text.trim().isEmpty &&
      barcode.text.trim().isEmpty &&
      stock.text.trim().isEmpty &&
      lowStock.text.trim().isEmpty &&
      packUnit == null;

  void dispose() {
    label.dispose();
    price.dispose();
    barcode.dispose();
    stock.dispose();
    lowStock.dispose();
    packSize.dispose();
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

  /// Major category → its categories, for the two suggestion lists. Empty for a
  /// business that has never filed anything under a major.
  final Map<String, List<String>> categoryTree;

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

  /// "Retail & Warranty" shops only: shows the "Carries warranty" toggle.
  final bool isWarrantyShop;

  /// Opens the category's custom warranty-field editor. Only offered once
  /// warranty is on and a category is entered — there must be something to
  /// key the template by.
  final void Function(String category)? onManageWarrantyFields;

  const _ItemFormDialog(
      {this.item,
      required this.inventoryEnabled,
      this.gstEnabled = false,
      this.categories = const [],
      this.categoryTree = const {},
      required this.onSaved,
      this.onVariantsCreated,
      this.onManageSizes,
      this.onManageRecipe,
      this.isWarrantyShop = false,
      this.onManageWarrantyFields});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _majorCtrl = TextEditingController();
  final _majorFocus = FocusNode();
  final _categoryCtrl = TextEditingController();
  final _categoryFocus = FocusNode();
  final _priceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _hsnCtrl = TextEditingController();
  final _itemNoCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  final _packSizeCtrl = TextEditingController();
  final _picker = ImagePicker();
  String _unit = 'piece';
  String? _packUnit;
  bool _saving = false;

  /// The item's photo (customer-facing on the QR menu / online store).
  /// [_photoUrl] is the stored one (fetched on edit); [_newPhoto] is a picked,
  /// compressed JPEG not yet uploaded; [_photoRemoved] clears it on save.
  String? _photoUrl;
  Uint8List? _newPhoto;
  bool _photoRemoved = false;

  /// Whether the entered price already contains GST (an MRP) rather than being
  /// a net price GST is added to. Only meaningful when GST is on and a tax rate
  /// is set; billing back-calculates the net rate from an inclusive price.
  bool _priceInclusiveTax = false;

  /// Whether the user ticked "this item has variants" while CREATING. Editing an
  /// existing item still routes to the dedicated size manager, which already
  /// handles update/delete of persisted sizes safely.
  bool _hasVariants = false;
  final List<_VariantDraft> _variantDrafts = [];

  /// "Retail & Warranty" shops only: whether selling this item auto-creates a
  /// warranty record, and the period (months) seeded onto it.
  bool _warrantyEligible = false;
  final _warrantyMonthsCtrl = TextEditingController();

  /// The item created by a previous save attempt that then failed part-way
  /// through its variants. Held so a retry adds only the MISSING variants
  /// instead of creating a second item.
  Item? _savedItem;

  /// Indexes (into the non-blank draft list) whose variant was already created.
  final Set<int> _createdDraftIndexes = {};

  /// Anything that went wrong with this form, shown as a banner above the first
  /// field: a validation failure, a rejected save (a duplicate name or barcode),
  /// or an item that saved while some of its variants did not.
  ///
  /// Inline rather than a SnackBar because this dialog is a route ABOVE the
  /// Scaffold, so a SnackBar renders behind its modal barrier.
  String? _formError;

  /// Scrolls the dialog body, so an error banner can be brought into view when
  /// the form is long enough to have scrolled past it.
  final _scrollCtrl = ScrollController();

  /// True whenever this item's prices live on its sizes — either the box was
  /// just ticked (create), or the item already has sizes (edit). Everything the
  /// sizes own (price, barcode, stock) is hidden and omitted on save.
  ///
  /// [_hasVariants] alone is create-only, so editing an existing sized item used
  /// to fall through to the plain-item branch and demand a price the item does
  /// not have.
  bool get _sizedItem => _hasVariants || (widget.item?.hasVariants ?? false);

  static const _units = [
    'piece',
    'kg',
    'g',
    'litre',
    'ml',
    'metre',
    'dozen',
    'plate',
    'packet',
    'box',
    'bottle',
    'pair',
    'set',
    'bundle',
    'bag',
    'sqft',
    'ton',
    'quintal',
    'roll',
    'case',
    'crate',
    'carton',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _nameCtrl.text = item.name;
      _itemNoCtrl.text = item.itemNo ?? '';
      _majorCtrl.text = item.majorCategory ?? '';
      _categoryCtrl.text = item.category ?? '';
      // ?? '' — a sized item has no price of its own, and `null.toString()`
      // would put the literal text "null" in the field.
      _priceCtrl.text = item.price?.toString() ?? '';
      _taxCtrl.text = item.taxRate?.toString() ?? '';
      _priceInclusiveTax = item.priceInclusiveTax;
      _hsnCtrl.text = item.hsnCode ?? '';
      _barcodeCtrl.text = item.barcode ?? '';
      _stockCtrl.text = item.stockQuantity?.toString() ?? '';
      _lowStockCtrl.text = item.lowStockThreshold?.toString() ?? '';
      _unit = _units.contains(item.unit) ? item.unit : 'piece';
      _packUnit = item.packUnit;
      _packSizeCtrl.text =
          item.packSize != null ? formatQty(item.packSize!) : '';
      _warrantyEligible = item.warrantyEligible;
      _warrantyMonthsCtrl.text = item.defaultWarrantyMonths?.toString() ?? '';
      // The items list never carries image_url, so look this one up.
      getItemImageUrl(item.id).then((url) {
        if (mounted) setState(() => _photoUrl = url);
      }).catchError((_) {});
    }
  }

  Future<void> _pickPhoto(ImageSource src) async {
    final failMsg = context.l10n.menuPhotosUploadFailed;
    try {
      final picked = await _picker.pickImage(
          source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
      if (picked == null) return;
      final jpeg = await compressToJpeg(await picked.readAsBytes());
      if (mounted) setState(() => _newPhoto = jpeg);
    } catch (_) {
      if (mounted) setState(() => _formError = failMsg);
    }
  }

  void _showPhotoSheet(AppLocalizations l10n, bool hasPhoto) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.menuPhotosPickCamera),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.menuPhotosPickGallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(l10n.menuPhotosRemove,
                    style: const TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _newPhoto = null;
                    _photoRemoved = true;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Thumbnail + add/change button for the item's photo.
  Widget _buildPhotoField(AppLocalizations l10n) {
    final showStored = _newPhoto == null && !_photoRemoved && _photoUrl != null;
    final hasPhoto = _newPhoto != null || showStored;
    final Widget placeholder = Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.image_outlined, color: AppColors.textDisabled),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: SizedBox(
            width: 64,
            height: 64,
            child: _newPhoto != null
                ? Image.memory(_newPhoto!, fit: BoxFit.cover)
                : showStored
                    ? Image.network(itemImageUrl(_photoUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder)
                    : placeholder,
          ),
        ),
        const SizedBox(width: AppSpacing.space12),
        // Expanded: the theme gives buttons an infinite min width, which a
        // Row can't lay out (the whole dialog then fails to render).
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _showPhotoSheet(l10n, hasPhoto),
            icon: Icon(
                hasPhoto ? Icons.edit_outlined : Icons.add_a_photo_outlined,
                size: 18),
            label: Text(hasPhoto ? l10n.menuPhotosChange : l10n.menuPhotosAdd),
          ),
        ),
      ],
    );
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _scrollCtrl.dispose();
    _majorCtrl.dispose();
    _majorFocus.dispose();
    _categoryCtrl.dispose();
    _categoryFocus.dispose();
    _priceCtrl.dispose();
    _taxCtrl.dispose();
    _hsnCtrl.dispose();
    _itemNoCtrl.dispose();
    _barcodeCtrl.dispose();
    _stockCtrl.dispose();
    _lowStockCtrl.dispose();
    _packSizeCtrl.dispose();
    _warrantyMonthsCtrl.dispose();
    for (final d in _variantDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  /// Major Category field — the coarse group ("Chinese") above the category
  /// ("Chinese Starters"). Deliberately the SAME widget as the category field
  /// below, so it behaves identically: free text you can type a brand-new
  /// group into, plus a dropdown of the groups this business already uses.
  Widget _buildMajorCategoryField(BuildContext context, AppLocalizations l10n) =>
      _buildSuggestField(
        context,
        controller: _majorCtrl,
        focusNode: _majorFocus,
        label: l10n.itemsFieldMajorCategory,
        hint: l10n.itemsFieldMajorCategoryHint,
        // Real groups only — '' is the "no major set" bucket, not a suggestion.
        options: widget.categoryTree.keys.where((m) => m.isNotEmpty).toList(),
      );

  /// Category field: a text field you can type into freely, with a dropdown of
  /// this business's existing categories. Typing a new value keeps it — on save
  /// that category is added to the business (categories come from the items, so
  /// a new category exists as soon as an item uses it). Picking a suggestion
  /// fills the field.
  ///
  /// The suggestions narrow to the typed major's own categories when there are
  /// any, so "Chinese" offers its starters rather than the whole menu. It never
  /// restricts what you may type, and with no major typed the list is exactly
  /// the full one it has always been.
  Widget _buildCategoryField(BuildContext context, AppLocalizations l10n) {
    final major = _majorCtrl.text.trim();
    final scoped = widget.categoryTree[major];
    return _buildSuggestField(
      context,
      controller: _categoryCtrl,
      focusNode: _categoryFocus,
      label: l10n.itemsFieldCategory,
      hint: l10n.itemsFieldCategoryHint,
      options: (scoped == null || scoped.isEmpty)
          ? widget.categories
          : scoped.where((c) => c.isNotEmpty).toList(),
    );
  }

  /// The shared free-text-with-suggestions field behind both category levels.
  ///
  /// Factored out of the original category field rather than copied, so the two
  /// levels cannot drift apart: same typing behaviour, same contains-match
  /// filtering, same dropdown toggle, same overlay.
  Widget _buildSuggestField(
    BuildContext context, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required List<String> options,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        final all = [...options]..sort();
        if (q.isEmpty) return all;
        return all.where((c) => c.toLowerCase().contains(q));
      },
      onSelected: (sel) => controller.text = sel,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return AppTextField(
          label: label,
          controller: controller,
          focusNode: focusNode,
          hint: hint,
          suffixIcon: options.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondary),
                  tooltip: label,
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
        if (d.packUnit != null) ..._packPayload(d.packUnit, d.packSize),
        'sort_order': sortOrder,
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Auto-generate a 12-digit barcode for new items that have no barcode.
    // Use current timestamp so it's unique and scannable immediately. A sized
    // item gets none — its sizes are what get scanned.
    final barcodeInput = _sizedItem ? '' : _barcodeCtrl.text.trim();
    final autoBarcode =
        (widget.item == null && !_sizedItem && barcodeInput.isEmpty)
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
      _formError = null;
    });

    // Items with sizes track stock per size — the server nulls the parent's
    // stock as soon as a size exists, so don't send a figure that will be
    // discarded.
    final sizedItem = _sizedItem;

    final data = {
      'name': _nameCtrl.text.trim(),
      // Always sent so clearing the number is persisted.
      'item_no': _itemNoCtrl.text.trim().isNotEmpty ? _itemNoCtrl.text.trim() : null,
      if (_majorCtrl.text.trim().isNotEmpty)
        'major_category': _majorCtrl.text.trim(),
      if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
      // A sized item has no price of its own — the sizes carry it. The server
      // only accepts a null price when has_variants says so.
      if (_hasVariants) 'has_variants': true,
      'price': sizedItem ? null : double.parse(_priceCtrl.text.trim()),
      // Sent as null when blank so clearing the rate is persisted. Only when GST
      // is on — otherwise the field is hidden and we'd wipe a rate never shown.
      if (widget.gstEnabled)
        'tax_rate': _taxCtrl.text.trim().isNotEmpty ? double.parse(_taxCtrl.text.trim()) : null,
      // Always sent (not conditional on the tax field) so clearing the rate or
      // switching the toggle off is persisted rather than leaving a stale 1
      // behind on the server.
      if (widget.gstEnabled) 'price_inclusive_tax': _priceInclusiveTax,
      if (widget.gstEnabled)
        'hsn_code': _hsnCtrl.text.trim().isNotEmpty ? _hsnCtrl.text.trim() : null,
      // Omitted entirely for a sized item: the field isn't shown, so sending
      // null would silently clear a barcode the user never saw. (On create the
      // server nulls it anyway when has_variants is set.)
      if (!sizedItem) 'barcode': effectiveBarcode,
      'unit': _unit,
      // A sized item's packs live on its sizes; the server nulls this on create.
      if (!sizedItem) ..._packPayload(_packUnit, _packSizeCtrl),
      if (widget.inventoryEnabled && sizedItem)
        'stock_quantity': null
      else if (widget.inventoryEnabled && _stockCtrl.text.trim().isNotEmpty)
        'stock_quantity': double.parse(_stockCtrl.text.trim()),
      if (widget.inventoryEnabled && !sizedItem && _lowStockCtrl.text.trim().isNotEmpty)
        'low_stock_threshold': double.parse(_lowStockCtrl.text.trim()),
      // Always sent (not conditional on the months field) so turning the
      // toggle off clears the period server-side too.
      if (widget.isWarrantyShop) 'warranty_eligible': _warrantyEligible,
      if (widget.isWarrantyShop)
        'default_warranty_months': _warrantyEligible
            ? int.parse(_warrantyMonthsCtrl.text.trim())
            : null,
    };

    final drafts = _variantDrafts.where((d) => !d.isBlank).toList();

    try {
      // On a retry after a partial failure the item already exists — creating it
      // again would leave a duplicate behind.
      final saved = _savedItem ?? await widget.onSaved(data, const []);
      _savedItem = saved;

      // Photo needs the item's id, so it goes up after the item is saved.
      // Cleared once done, so a retry for failed variants doesn't re-upload.
      try {
        if (_newPhoto != null) {
          _photoUrl = await uploadItemImage(saved.id, _newPhoto!);
          _newPhoto = null;
        } else if (_photoRemoved && _photoUrl != null) {
          await deleteItemImage(saved.id);
          _photoUrl = null;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _formError = context.l10n.menuPhotosUploadFailed);
        return;
      }

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
          setState(() => _formError = context.l10n
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
          const SizedBox(height: AppSpacing.space8),
          _PackRow(
            unit: d.packUnit,
            size: d.packSize,
            baseUnit: _unit,
            onUnitChanged: _saving ? null : (v) => setState(() => d.packUnit = v),
          ),
        ],
      ),
    );
  }

  /// Report a problem with this form.
  ///
  /// Rendered as the banner at the top of the dialog, NOT a SnackBar. A
  /// SnackBar belongs to the ScaffoldMessenger behind this route, so it painted
  /// underneath the dialog's modal barrier — dimmed, unreadable and impossible
  /// to dismiss without closing the form (losing the entry that caused it).
  void _showError(String message) {
    setState(() => _formError = message);
    // The banner sits above the first field; if the owner was editing further
    // down a long form they would never see it appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
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
            controller: _scrollCtrl,
            // The first field's floating label sits a few pixels ABOVE the field
            // box, so with the content starting at y=0 it was clipped by the
            // dialog. A small top pad gives it room.
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_formError != null) ...[
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
                      _formError!,
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
                AppTextField(
                  label: l10n.itemsFieldItemNo,
                  controller: _itemNoCtrl,
                  hint: l10n.itemsFieldItemNoHint,
                ),
                const SizedBox(height: AppSpacing.space12),
                _buildMajorCategoryField(context, l10n),
                const SizedBox(height: AppSpacing.space12),
                // Rebuilt as the major is typed so its suggestions re-scope —
                // scoped to just this field rather than setState-ing the whole
                // form on every keystroke.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _majorCtrl,
                  builder: (context, _, __) => _buildCategoryField(context, l10n),
                ),
                // The variants toggle sits here, before price/barcode/stock,
                // because it decides whether those fields apply at all: a sized
                // item owns none of them — each size carries its own.
                if (widget.item == null) ...[
                  const SizedBox(height: AppSpacing.space12),
                  _buildVariantsSection(l10n),
                ],
                // Price belongs to the item only when it has no sizes.
                if (!_sizedItem) ...[
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
                        child: Text(itemUnitLabel(context, u),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? 'piece'),
                ),
                if (!_sizedItem) ...[
                  const SizedBox(height: AppSpacing.space12),
                  _PackRow(
                    unit: _packUnit,
                    size: _packSizeCtrl,
                    baseUnit: _unit,
                    onUnitChanged: (v) => setState(() => _packUnit = v),
                  ),
                ] else if (widget.item?.hasVariants ?? false) ...[
                  // A sized item's packs live on its sizes — point there, or
                  // the option just looks missing.
                  const SizedBox(height: AppSpacing.space8),
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.itemsPackPerSizeHint,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
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
                // "Retail & Warranty" shops only — selling this item can
                // auto-create a warranty record (routes/bills.js hook).
                if (widget.isWarrantyShop) ...[
                  const SizedBox(height: AppSpacing.space12),
                  SwitchListTile(
                    value: _warrantyEligible,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _warrantyEligible = v),
                    title: Text(l10n.itemsWarrantyEligible,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_warrantyEligible) ...[
                    const SizedBox(height: AppSpacing.space12),
                    AppTextField(
                      label: l10n.itemsWarrantyDefaultMonths,
                      controller: _warrantyMonthsCtrl,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return (n == null || n <= 0)
                            ? l10n.commonEnterValidNumber
                            : null;
                      },
                    ),
                    if (widget.onManageWarrantyFields != null &&
                        _categoryCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.space8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => widget.onManageWarrantyFields!(
                              _categoryCtrl.text.trim()),
                          icon: const Icon(Icons.tune, size: 16),
                          label: Text(l10n.itemsManageWarrantyFields),
                        ),
                      ),
                    ],
                  ],
                ],
                // A sized item is never scanned directly — each size has its own
                // barcode, so the item-level one would be ambiguous.
                if (!_sizedItem) ...[
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
                if (widget.inventoryEnabled && !_sizedItem) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldStock,
                    controller: _stockCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    // Echoes the unit picked above, so "12" is unambiguously
                    // 12 kg and not 12 pieces.
                    suffixIcon: UnitSuffix(itemUnitLabel(context, _unit)),
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
                    suffixIcon: UnitSuffix(itemUnitLabel(context, _unit)),
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
                const SizedBox(height: AppSpacing.space12),
                _buildPhotoField(l10n),
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
// Warranty field template editor — the custom fields ("KM Reading", "Serial
// Number", ...) every warranty record in one item category asks for. See
// migration 063 / routes/warranty_field_templates.js.
// ---------------------------------------------------------------------------
class _WarrantyFieldTemplateDialog extends ConsumerStatefulWidget {
  final String category;
  const _WarrantyFieldTemplateDialog({required this.category});

  @override
  ConsumerState<_WarrantyFieldTemplateDialog> createState() =>
      _WarrantyFieldTemplateDialogState();
}

class _FieldDraft {
  final TextEditingController labelCtrl;
  String type;
  final String? originalKey;

  _FieldDraft({required this.labelCtrl, required this.type, this.originalKey});
}

class _WarrantyFieldTemplateDialogState
    extends ConsumerState<_WarrantyFieldTemplateDialog> {
  final List<_FieldDraft> _fields = [];
  bool _saving = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final templates = ref.read(warrantyFieldTemplatesProvider).valueOrNull;
    final existing = templates?[widget.category];
    if (existing != null) {
      for (final f in existing.fields) {
        _fields.add(_FieldDraft(
          labelCtrl: TextEditingController(text: f.label),
          type: f.type,
          originalKey: f.key,
        ));
      }
    }
    _loaded = true;
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.labelCtrl.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() => _fields
        .add(_FieldDraft(labelCtrl: TextEditingController(), type: 'text')));
  }

  void _removeField(_FieldDraft f) {
    setState(() => _fields.remove(f));
    f.labelCtrl.dispose();
  }

  /// Derives a stable field key from its label (e.g. "KM Reading" →
  /// "km_reading"), reusing the original key on an edit so renaming a label
  /// doesn't orphan values already saved under the old key.
  String _keyFor(_FieldDraft f) =>
      f.originalKey ??
      f.labelCtrl.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _save() async {
    final nonBlank = _fields.where((f) => f.labelCtrl.text.trim().isNotEmpty).toList();
    setState(() => _saving = true);
    try {
      final notifier = ref.read(warrantyFieldTemplatesProvider.notifier);
      if (nonBlank.isEmpty) {
        await notifier.remove(widget.category);
      } else {
        await notifier.save(
          widget.category,
          [
            for (final f in nonBlank)
              WarrantyTemplateField(
                  key: _keyFor(f), label: f.labelCtrl.text.trim(), type: f.type),
          ],
        );
      }
      rememberWarrantyLabels(
          [for (final f in nonBlank) f.labelCtrl.text.trim()]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sanitizeUiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Other categories' already-defined field labels (e.g. another item's
    // "Vehicle" or "IMEI"), suggested here too so a label predefined for one
    // item is reused instead of retyped.
    final otherLabels = allTemplateLabels(
        ref.watch(warrantyFieldTemplatesProvider).valueOrNull);
    return AlertDialog(
      title: Text(l10n.itemsWarrantyFieldsFor(widget.category)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: WarrantyLabelField(
                        label: l10n.warrantyDetailLabel,
                        controller: f.labelCtrl,
                        extraSuggestions: otherLabels),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  DropdownButton<String>(
                    value: f.type,
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Text')),
                      DropdownMenuItem(value: 'number', child: Text('Number')),
                      DropdownMenuItem(value: 'date', child: Text('Date')),
                    ],
                    onChanged: (v) => setState(() => f.type = v ?? 'text'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeField(f),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: _addField,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.warrantyAddDetail),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.commonSaving : l10n.commonSave),
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

  /// Whether each size gets a recipe button — restaurant + inventory only.
  final bool showRecipe;
  final void Function(List<ItemVariant> variants) onChanged;

  const _VariantManagerDialog({
    required this.item,
    required this.inventoryEnabled,
    this.showRecipe = false,
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
  final _lowStockCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _packSizeCtrl = TextEditingController();
  String? _packUnit;
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
    _lowStockCtrl.dispose();
    _barcodeCtrl.dispose();
    _packSizeCtrl.dispose();
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
        if (widget.inventoryEnabled && _lowStockCtrl.text.trim().isNotEmpty)
          'low_stock_threshold': double.tryParse(_lowStockCtrl.text.trim()),
        if (_packUnit != null) ..._packPayload(_packUnit, _packSizeCtrl),
        'sort_order': _variants.length,
      };
      final created = await createVariant(widget.item.id, data);
      setState(() {
        _variants.add(ItemVariant.fromJson(created));
        _labelCtrl.clear();
        _priceCtrl.clear();
        _stockCtrl.clear();
        _lowStockCtrl.clear();
        _barcodeCtrl.clear();
        _packSizeCtrl.clear();
        _packUnit = null;
      });
      widget.onChanged(List.unmodifiable(_variants));
    } on ApiException catch (e) {
      _snack(sanitizeUiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open the recipe editor for one size.
  ///
  /// If the parent item still carries an item-level recipe from before it had
  /// sizes, offer to copy it down. That recipe is now unreachable — every line
  /// on a sized item names a size, and a sized line never falls back to the
  /// item's rows — so without this the dish would silently stop consuming raw
  /// materials.
  Future<void> _editRecipe(ItemVariant v) async {
    final l10n = context.l10n;
    List<Map<String, dynamic>>? seed;

    try {
      final existing = await getItemRecipe(widget.item.id);
      if (existing.isNotEmpty && mounted) {
        final copy = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.itemsRecipeCopyTitle),
            content: Text(l10n.itemsRecipeCopyBody(widget.item.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.itemsRecipeStartEmpty),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.itemsRecipeCopyConfirm),
              ),
            ],
          ),
        );
        if (copy == true) {
          seed = existing
              .map((j) => {
                    'raw_material_id': j['raw_material_id'],
                    'quantity': j['quantity'],
                  })
              .toList();
        }
      }
    } catch (_) {
      // The prompt is a convenience — a failed lookup just means no seed.
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => RecipeEditorDialog(
        itemId: widget.item.id,
        itemName: widget.item.name,
        variantId: v.id,
        variantLabel: v.label,
        initialRows: seed,
      ),
    );
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

  /// Edit (or clear) an existing size's barcode and pack. Persists the change
  /// and patches the local list so scans/prints use the new value immediately.
  Future<void> _editVariantBarcode(ItemVariant v) async {
    final result = await showDialog<({String barcode, Map<String, dynamic> pack})>(
      context: context,
      builder: (_) => _SizeEditDialog(variant: v, baseUnit: widget.item.unit),
    );
    if (result == null) return;
    final newBarcode = result.barcode;
    final pack = result.pack;

    // No change → skip the round-trip.
    final packChanged =
        pack['pack_unit'] != v.packUnit || pack['pack_size'] != v.packSize;
    if (newBarcode == (v.barcode ?? '') && !packChanged) return;

    setState(() => _busy = true);
    try {
      // Empty string clears the barcode (backend maps '' → null).
      final result = await updateVariant(widget.item.id, v.id, {
        'barcode': newBarcode.isEmpty ? null : newBarcode,
        if (packChanged) ...pack,
      });
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
        // 440 when a recipe icon joins edit/print/delete — four 18px buttons
        // plus the size label and price/stock subtitle crowd 400.
        width: widget.showRecipe ? 440 : 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A size with no recipe consumes nothing — say so, since the
              // symptom otherwise is stock quietly not moving.
              if (widget.showRecipe && _variants.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(l10n.itemsVariantRecipeHint,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
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
                    if (v.packUnit != null && v.packSize != null)
                      '1 ${itemUnitLabel(context, v.packUnit!)} = '
                          '${formatQty(v.packSize!)} '
                          '${itemUnitLabel(context, widget.item.unit)}',
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
                          tooltip: l10n.itemsSizeEditTitle(v.label),
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
                        if (widget.showRecipe)
                          IconButton(
                            tooltip: l10n.itemsVariantRecipeTooltip(v.label),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18, color: AppColors.textSecondary),
                            onPressed: _busy ? null : () => _editRecipe(v),
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
                  // A size has no unit of its own — it is counted in the parent
                  // item's unit, which is what the stock rows below display.
                  suffixIcon:
                      UnitSuffix(itemUnitLabel(context, widget.item.unit)),
                ),
                const SizedBox(height: AppSpacing.space8),
                // Same per-size alert as the create form's size rows — the
                // item's own alert is cleared once it has sizes.
                AppTextField(
                  label: l10n.itemsFieldLowStock,
                  controller: _lowStockCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  suffixIcon:
                      UnitSuffix(itemUnitLabel(context, widget.item.unit)),
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
              const SizedBox(height: AppSpacing.space8),
              _PackRow(
                unit: _packUnit,
                size: _packSizeCtrl,
                baseUnit: widget.item.unit,
                onUnitChanged: _busy ? null : (u) => setState(() => _packUnit = u),
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

/// Barcode + pack editor for one existing size. A widget of its own so its
/// controllers are disposed only once the route is gone — disposing them right
/// after showDialog returned pulled them out from under the closing animation
/// ("_dependents.isEmpty" / "wrong build scope").
class _SizeEditDialog extends StatefulWidget {
  final ItemVariant variant;
  final String baseUnit;
  const _SizeEditDialog({required this.variant, required this.baseUnit});

  @override
  State<_SizeEditDialog> createState() => _SizeEditDialogState();
}

class _SizeEditDialogState extends State<_SizeEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _barcode = TextEditingController(text: widget.variant.barcode ?? '');
  late final _packSize = TextEditingController(
      text: widget.variant.packSize != null ? formatQty(widget.variant.packSize!) : '');
  late String? _packUnit = widget.variant.packUnit;

  @override
  void dispose() {
    _barcode.dispose();
    _packSize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.itemsSizeEditTitle(widget.variant.label)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: l10n.itemsSizeBarcodeOptional,
              controller: _barcode,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: AppSpacing.space12),
            _PackRow(
              unit: _packUnit,
              size: _packSize,
              baseUnit: widget.baseUnit,
              onUnitChanged: (u) => setState(() => _packUnit = u),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel)),
        ElevatedButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, (
                barcode: _barcode.text.trim(),
                pack: _packPayload(_packUnit, _packSize),
              ));
            },
            child: Text(l10n.commonSave)),
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
