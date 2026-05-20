import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../api.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item'),
        content: Text('Delete "${item.name}"? It will no longer appear in billing.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Items / Menu')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search items…',
                prefixIcon: Icon(Icons.search_outlined, size: 20),
              ),
            ),
          ),
          Expanded(child: _buildBody(itemsAsync, userRole, inventoryEnabled)),
        ],
      ),
      floatingActionButton: userRole == 'owner'
          ? FloatingActionButton.extended(
              onPressed: () => _showItemForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildBody(
      AsyncValue<List<Item>> itemsAsync, String userRole, bool inventoryEnabled) {
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(itemsProvider);
          await ref.read(itemsProvider.future);
        },
        child: ListView(children: [
          EmptyState(
            icon: Icons.wifi_off_outlined,
            message: e.toString(),
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(itemsProvider),
          ),
        ]),
      ),
      data: (allItems) {
        final items = _filtered(allItems);
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(itemsProvider);
              await ref.read(itemsProvider.future);
            },
            child: ListView(children: [
              EmptyState(
                icon: Icons.inventory_2_outlined,
                message: userRole == 'owner'
                    ? 'No items yet. Tap + to add your first item.'
                    : 'No items found.',
                actionLabel: userRole == 'owner' ? 'Add Item' : null,
                onAction: userRole == 'owner' ? () => _showItemForm() : null,
              ),
            ]),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(itemsProvider);
            await ref.read(itemsProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
            itemBuilder: (_, i) {
              final item = items[i];
              return AppCard(
                onTap: userRole == 'owner' ? () => _showItemForm(item: item) : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (item.category != null)
                                Text(item.category!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.textSecondary)),
                              if (item.category != null && item.taxRate != null)
                                Text('  ·  ',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.textDisabled)),
                              if (item.taxRate != null)
                                Text('${item.taxRate!.toStringAsFixed(0)}% tax',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.textSecondary)),
                            ],
                          ),
                          if (inventoryEnabled && item.stockQuantity != null)
                            Text(
                                'Stock: ${item.stockQuantity!.toStringAsFixed(0)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      '₹${item.price.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (userRole == 'owner') ...[
                      const SizedBox(width: AppSpacing.space8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error, size: 20),
                        onPressed: () => _deleteItem(item),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
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

    final data = {
      'name': _nameCtrl.text.trim(),
      if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
      'price': double.parse(_priceCtrl.text.trim()),
      if (_taxCtrl.text.trim().isNotEmpty)
        'tax_rate': double.parse(_taxCtrl.text.trim()),
      if (_barcodeCtrl.text.trim().isNotEmpty) 'barcode': _barcodeCtrl.text.trim(),
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
    return AlertDialog(
      title: Text(widget.item == null ? 'Add Item' : 'Edit Item'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: _nameCtrl,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                    label: 'Category',
                    controller: _categoryCtrl,
                    hint: 'e.g. Beverages'),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: 'Price (₹)',
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Enter a valid number';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: 'Tax rate % (optional)',
                  controller: _taxCtrl,
                  hint: 'e.g. 5, 12, 18',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space12),
                AppTextField(
                  label: 'Barcode (optional)',
                  controller: _barcodeCtrl,
                  keyboardType: TextInputType.number,
                ),
                if (widget.inventoryEnabled) ...[
                  const SizedBox(height: AppSpacing.space12),
                  AppTextField(
                    label: 'Stock quantity',
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
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.item == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
