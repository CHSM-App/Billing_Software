import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart' as api;
import '../models/models.dart';
import '../providers/items_provider.dart';
import '../providers/raw_materials_provider.dart';
import '../providers/session_provider.dart';
import '../services/purchase_list_pdf.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../widgets/stock_target_picker.dart';

/// One editable row in the purchase list: an item plus how much of it to buy.
class _PurchaseListRow {
  final String name;
  final String unit;
  final double? currentStock;
  final double? lowStockThreshold;
  final TextEditingController qty;

  _PurchaseListRow({
    required this.name,
    required this.unit,
    this.currentStock,
    this.lowStockThreshold,
    String initialQty = '',
  }) : qty = TextEditingController(text: initialQty);

  void dispose() => qty.dispose();
}

/// Builds a purchase (reorder) list starting from whatever is currently low on
/// stock, lets the user add or remove items freely, then exports it as a PDF
/// to hand to a vendor. This is a planning list — it does not create a vendor
/// bill or touch stock; "Add purchase" remains the record of an actual buy.
class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() =>
      _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  final List<_PurchaseListRow> _rows = [];
  final Set<String> _addedNames = {};
  bool _exporting = false;
  bool _sharing = false;

  bool get _isRestaurantBiz =>
      isRestaurantBusiness(ref.read(businessTypeProvider));

  @override
  void initState() {
    super.initState();
    if (_isRestaurantBiz) {
      final materials = ref.read(rawMaterialsProvider).valueOrNull ?? [];
      for (final m in materials) {
        if (m.isLowStock) {
          _addRow(
            name: m.name,
            unit: m.unit,
            currentStock: m.stockQuantity,
            lowStockThreshold: m.lowStockThreshold,
          );
        }
      }
    } else {
      final items = ref.read(itemsProvider).valueOrNull ?? [];
      for (final item in items) {
        if (item.hasVariants) {
          for (final v in item.variants) {
            if (v.isLowStock) {
              _addRow(
                name: '${item.name} (${v.label})',
                unit: item.unit,
                currentStock: v.stockQuantity,
                lowStockThreshold: v.lowStockThreshold,
              );
            }
          }
        } else if (item.isLowStock) {
          _addRow(
            name: item.name,
            unit: item.unit,
            currentStock: item.stockQuantity,
            lowStockThreshold: item.lowStockThreshold,
          );
        }
      }
    }
  }

  void _addRow({
    required String name,
    required String unit,
    double? currentStock,
    double? lowStockThreshold,
  }) {
    if (!_addedNames.add(name)) return;
    // Quantity always starts empty — whether the row came from the low-stock
    // auto-populate or was added manually via the picker — so the user has to
    // type the amount to reorder rather than trust a guessed default.
    _rows.add(_PurchaseListRow(
      name: name,
      unit: unit,
      currentStock: currentStock,
      lowStockThreshold: lowStockThreshold,
    ));
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRestaurant = isRestaurantBusiness(ref.watch(businessTypeProvider));
    final addLabel = isRestaurant ? 'Add raw material' : 'Add item';
    final emptyMessage = isRestaurant
        ? 'No low-stock raw materials right now. Tap "Add raw material" to build a list manually.'
        : 'No low-stock items right now. Tap "Add item" to build a list manually.';

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'purchaseListShareFab',
            onPressed: _sharing || _rows.isEmpty ? null : _sharePdf,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share_outlined),
            label: Text(_sharing ? 'Preparing…' : 'Share PDF'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'purchaseListPdfFab',
            onPressed: _exporting || _rows.isEmpty ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exporting ? 'Preparing…' : 'Create PDF'),
          ),
        ],
      ),
      body: Column(children: [
        const ShellAppBar(title: Text('Create Purchase List')),
        Expanded(
          child: isRestaurant
              ? _buildBody(
                  ref.watch(rawMaterialsProvider),
                  () => ref.invalidate(rawMaterialsProvider),
                  addLabel,
                  emptyMessage,
                  (materials) => _pickMaterialToAdd(context, materials),
                )
              : _buildBody(
                  ref.watch(itemsProvider),
                  () => ref.invalidate(itemsProvider),
                  addLabel,
                  emptyMessage,
                  (items) => _pickItemToAdd(context, items),
                ),
        ),
      ]),
    );
  }

  Widget _buildBody<T>(
    AsyncValue<List<T>> async,
    VoidCallback onRetry,
    String addLabel,
    String emptyMessage,
    void Function(List<T>) onAdd,
  ) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e, onRetry: onRetry),
      data: (source) {
        final addButton = SizedBox(
          width: double.infinity,
          child: SecondaryButton(
            text: addLabel,
            icon: Icons.add,
            onPressed: () => onAdd(source),
          ),
        );
        return _rows.isEmpty
          ? Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: addButton,
              ),
              Expanded(
                child: EmptyState(
                    icon: Icons.checklist_outlined, message: emptyMessage),
              ),
            ])
          // The add button sits after the last row, inside the same scroll
          // view, so it's reachable without scrolling back to the top when
          // the list is long.
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _rows.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => i < _rows.length ? _rowCard(i) : addButton,
            );
      },
    );
  }

  Widget _rowCard(int i) {
    final r = _rows[i];
    final lowStockNote = (r.currentStock != null && r.lowStockThreshold != null)
        ? 'In stock: ${_fmt(r.currentStock!)} ${r.unit} · Reorder level: ${_fmt(r.lowStockThreshold!)} ${r.unit}'
        : null;
    return AppCard(
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              if (lowStockNote != null) ...[
                const SizedBox(height: 2),
                Text(lowStockNote,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: AppTextField(
            label: 'Qty',
            controller: r.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                widthFactor: 1,
                child: Text(r.unit,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: AppColors.error),
          onPressed: () => setState(() {
            _addedNames.remove(r.name);
            _rows.removeAt(i).dispose();
          }),
        ),
      ]),
    );
  }

  String _fmt(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  Future<void> _pickItemToAdd(BuildContext context, List<Item> items) =>
      _showPicker(
          context,
          buildStockTargets(
              isRestaurant: false,
              items: items,
              materials: const [],
              exclude: _addedNames));

  Future<void> _pickMaterialToAdd(
          BuildContext context, List<RawMaterial> materials) =>
      _showPicker(
          context,
          buildStockTargets(
              isRestaurant: true,
              items: const [],
              materials: materials,
              exclude: _addedNames));

  Future<void> _showPicker(
      BuildContext context, List<StockTarget> candidates) async {
    final selected = await showStockTargetPicker(context, candidates);
    if (selected == null || !mounted) return;
    setState(() {
      _addRow(
        name: selected.name,
        unit: selected.unit,
        currentStock: selected.currentStock,
        lowStockThreshold: selected.lowStockThreshold,
      );
    });
  }

  Future<Uint8List> _buildPdfBytes() {
    final lines = _rows
        .map((r) => PurchaseListLine(
              name: r.name,
              quantity: double.tryParse(r.qty.text.trim()) ?? 0,
              unit: r.unit,
            ))
        .where((l) => l.quantity > 0)
        .toList();
    return PurchaseListPdf.build(lines);
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Purchase-list');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(api.sanitizeUiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _buildPdfBytes();
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: 'Purchase-list.pdf', mimeType: 'application/pdf')],
        text: 'Purchase list',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(api.sanitizeUiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

