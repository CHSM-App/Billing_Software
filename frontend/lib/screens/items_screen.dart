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

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState(); 
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    showDialog(
      context: context,
      builder: (_) => _ItemFormDialog(
        item: item,
        inventoryEnabled: inventoryEnabled,
        onSaved: (data) async {
          if (item == null) {
            await ref.read(itemsProvider.notifier).addItem(data);
          } else {
            await ref.read(itemsProvider.notifier).updateItem(item.id, data);
          }
          await ref.read(categoriesProvider.notifier).reload();
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

    return Scaffold(
      body: Column(
        children: [
          ShellAppBar(title: Text(l10n.itemsTitle)),
          Expanded(child: _buildBody(itemsAsync, userRole, inventoryEnabled)),
        ],
      ),
      floatingActionButton: userRole == 'owner'
          ? FloatingActionButton.extended(
              onPressed: () => _showItemForm(),
              icon: const Icon(Icons.add),
              label: Text(l10n.itemsAddItem),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _searchBarSliver() => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.space12, 6, AppSpacing.space12, AppSpacing.space4),
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
              _searchBarSliver(),
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
            _searchBarSliver(),
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
          mainAxisSpacing: 8,
          mainAxisExtent: 62,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            _buildItemCard(items[i], userRole, inventoryEnabled),
      ),
    );
  }

  Widget _buildItemCard(Item item, String userRole, bool inventoryEnabled) {
    final l10n = context.l10n;
    final subtitle = [
      if (item.category != null) item.category!,
      if (inventoryEnabled && item.stockQuantity != null)
        l10n.itemsStockLabel(item.stockQuantity!.toStringAsFixed(0)),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Color dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.border,
                  ),
                ),
                const SizedBox(width: 10),
                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.2,
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
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.2,
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
                                    fontSize: 12,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
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
                    fontSize: 14,
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
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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
                    _current.toStringAsFixed(0),
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
                      _total.toStringAsFixed(0),
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
  final Future<void> Function(Map<String, dynamic> data) onSaved;

  const _ItemFormDialog(
      {this.item, required this.inventoryEnabled, required this.onSaved});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  bool _saving = false;

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
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    _taxCtrl.dispose();
    _barcodeCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
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

    final data = {
      'name': _nameCtrl.text.trim(),
      if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
      'price': double.parse(_priceCtrl.text.trim()),
      if (_taxCtrl.text.trim().isNotEmpty)
        'tax_rate': double.parse(_taxCtrl.text.trim()),
      'barcode': barcodeInput.isNotEmpty ? barcodeInput : autoBarcode,
      if (widget.inventoryEnabled && _stockCtrl.text.trim().isNotEmpty)
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
                AppTextField(
                    label: l10n.itemsFieldCategory,
                    controller: _categoryCtrl,
                    hint: l10n.itemsFieldCategoryHint),
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
                if (widget.inventoryEnabled) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: l10n.itemsFieldStock,
                    controller: _stockCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
