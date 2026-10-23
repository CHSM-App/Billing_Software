import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../api.dart' show sanitizeUiErrorMessage;
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

enum _WarrantyStatusFilter { all, active, expiringSoon, expired }

extension on _WarrantyStatusFilter {
  String? get apiValue => switch (this) {
        _WarrantyStatusFilter.all => null,
        _WarrantyStatusFilter.active => 'active',
        _WarrantyStatusFilter.expiringSoon => 'expiring_30',
        _WarrantyStatusFilter.expired => 'expired',
      };
}

/// Tyre/battery/electronics shops ("Retail & Warranty" business type): record
/// and look up warranty info for a sold product, by customer phone or serial
/// number. See routes/warranties.js.
class WarrantyScreen extends ConsumerStatefulWidget {
  const WarrantyScreen({super.key});

  @override
  ConsumerState<WarrantyScreen> createState() => _WarrantyScreenState();
}

class _WarrantyScreenState extends ConsumerState<WarrantyScreen> {
  static const _pageSize = 30;

  List<Warranty> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _requestSeq = 0;

  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  _WarrantyStatusFilter _filter = _WarrantyStatusFilter.all;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _params => {
        if (_query.trim().isNotEmpty) 'q': _query.trim(),
        if (_filter.apiValue != null) 'status': _filter.apiValue!,
      };

  Future<void> _reload() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await api.getWarranties(
          {..._params, 'offset': '0', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _total = (r['total'] as num?)?.toInt() ?? 0;
        _items = _parse(r);
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final r = await api.getWarranties(
          {..._params, 'offset': '${_items.length}', 'limit': '$_pageSize'});
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _total = (r['total'] as num?)?.toInt() ?? 0;
        final seen = _items.map((w) => w.id).toSet();
        _items = [..._items, ..._parse(r).where((w) => !seen.contains(w.id))];
      });
    } catch (_) {
      // Keep the current page; the next scroll/retry tries again.
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loadingMore = false);
    }
  }

  static List<Warranty> _parse(Map<String, dynamic> r) => (r['items'] as List)
      .map((j) => Warranty.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();

  void _onSearchChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _setFilter(_WarrantyStatusFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    _reload();
  }

  Future<void> _openForm({Warranty? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WarrantyFormScreen(existing: existing)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Column(children: [
        ShellAppBar(title: Text(l10n.warrantyTitle)),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.warrantySearchHint,
                isDense: true,
                prefixIcon: const Icon(Icons.search_outlined,
                    size: 18, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space16, vertical: 0),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16),
            children: [
              _FilterChip(
                label: l10n.warrantyFilterAll,
                selected: _filter == _WarrantyStatusFilter.all,
                onTap: () => _setFilter(_WarrantyStatusFilter.all),
              ),
              _FilterChip(
                label: l10n.warrantyFilterActive,
                selected: _filter == _WarrantyStatusFilter.active,
                onTap: () => _setFilter(_WarrantyStatusFilter.active),
              ),
              _FilterChip(
                label: l10n.warrantyFilterExpiringSoon,
                selected: _filter == _WarrantyStatusFilter.expiringSoon,
                onTap: () => _setFilter(_WarrantyStatusFilter.expiringSoon),
              ),
              _FilterChip(
                label: l10n.warrantyFilterExpired,
                selected: _filter == _WarrantyStatusFilter.expired,
                onTap: () => _setFilter(_WarrantyStatusFilter.expired),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Expanded(child: _buildBody(l10n)),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(dynamic l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(sanitizeUiErrorMessage(_error)),
          const SizedBox(height: AppSpacing.space8),
          OutlinedButton(
            onPressed: _reload,
            // Theme default minimumSize is full-width (double.infinity);
            // inside a Center/Column it only gets loose width constraints,
            // which crashes layout unless overridden — see the "Pick item"
            // button above for the same fix.
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(l10n.commonRetry),
          ),
        ]),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Text(l10n.warrantyEmptyState, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(AppSpacing.space16, 0,
          AppSpacing.space16, AppSpacing.space16),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.space16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final w = _items[i];
        return _WarrantyRow(
          warranty: w,
          onTap: () => _openForm(existing: w),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.space8),
      child: ChoiceChip(
        label: Text(
          label,
          style: AppFont.style(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _WarrantyRow extends StatelessWidget {
  final Warranty warranty;
  final VoidCallback onTap;
  const _WarrantyRow({required this.warranty, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final w = warranty;
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, statusColor) = w.isExpired
        ? (l10n.warrantyFilterExpired, AppColors.error)
        : w.isExpiringSoon
            ? (l10n.warrantyFilterExpiringSoon, AppColors.warning)
            : (l10n.warrantyFilterActive, AppColors.success);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      w.displayName,
                      if (w.serialNumber?.isNotEmpty ?? false) w.serialNumber!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.warrantyExpiresOn(_dateFmt.format(w.expiryDate)),
                    style: textTheme.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(statusLabel,
                  style: textTheme.labelSmall
                      ?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit form
// ---------------------------------------------------------------------------

class _ExtraRow {
  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  /// null for an ad-hoc row the staff added themselves; set for a row that
  /// came from the category template, so its label stays read-only.
  final String? templateKey;

  _ExtraRow({required this.labelCtrl, required this.valueCtrl, this.templateKey});
}

class WarrantyFormScreen extends ConsumerStatefulWidget {
  final Warranty? existing;
  const WarrantyFormScreen({super.key, this.existing});

  @override
  ConsumerState<WarrantyFormScreen> createState() => _WarrantyFormScreenState();
}

class _WarrantyFormScreenState extends ConsumerState<WarrantyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _monthsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _itemId;
  String? _category;
  DateTime _purchaseDate = DateTime.now();
  final List<_ExtraRow> _extraRows = [];
  bool _saving = false;
  bool _deleting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    if (w != null) {
      _nameCtrl.text = w.customerName ?? '';
      _phoneCtrl.text = w.customerPhone;
      _productCtrl.text = w.itemName;
      _serialCtrl.text = w.serialNumber ?? '';
      _monthsCtrl.text = '${w.warrantyMonths}';
      _notesCtrl.text = w.notes ?? '';
      _itemId = w.itemId;
      _category = w.category;
      _purchaseDate = w.purchaseDate;
      for (final e in w.extraData) {
        _extraRows.add(_ExtraRow(
          labelCtrl: TextEditingController(text: e.label),
          valueCtrl: TextEditingController(text: e.value),
        ));
      }
    } else {
      _monthsCtrl.text = '12';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _productCtrl.dispose();
    _serialCtrl.dispose();
    _monthsCtrl.dispose();
    _notesCtrl.dispose();
    for (final r in _extraRows) {
      r.labelCtrl.dispose();
      r.valueCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _pickItem() async {
    final items = await ref.read(itemsProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemPickerSheet(items: items),
    );
    if (picked == null) return;
    setState(() {
      _itemId = picked.id;
      _productCtrl.text = picked.name;
      _category = picked.category;
      if (picked.defaultWarrantyMonths != null) {
        _monthsCtrl.text = '${picked.defaultWarrantyMonths}';
      }
    });
    _applyTemplateForCategory();
  }

  /// Adds a row for every template field of [_category] that isn't already
  /// present (by templateKey), so switching products doesn't wipe values the
  /// staff already typed for fields the two products happen to share.
  void _applyTemplateForCategory() {
    final category = _category;
    if (category == null || category.trim().isEmpty) return;
    final templates = ref.read(warrantyFieldTemplatesProvider).valueOrNull;
    final template = templates?[category];
    if (template == null) return;
    final existingKeys = _extraRows.map((r) => r.templateKey).toSet();
    setState(() {
      for (final f in template.fields) {
        if (existingKeys.contains(f.key)) continue;
        _extraRows.add(_ExtraRow(
          labelCtrl: TextEditingController(text: f.label),
          valueCtrl: TextEditingController(),
          templateKey: f.key,
        ));
      }
    });
  }

  void _addAdHocRow() {
    setState(() => _extraRows.add(_ExtraRow(
          labelCtrl: TextEditingController(),
          valueCtrl: TextEditingController(),
        )));
  }

  void _removeRow(_ExtraRow row) {
    setState(() => _extraRows.remove(row));
    row.labelCtrl.dispose();
    row.valueCtrl.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = {
      'customer_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      'customer_phone': _phoneCtrl.text.trim(),
      'item_id': _itemId,
      'item_name': _productCtrl.text.trim(),
      'category': _category,
      'serial_number': _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
      'purchase_date': _purchaseDate.toIso8601String().split('T').first,
      'warranty_months': int.tryParse(_monthsCtrl.text.trim()) ?? 0,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'extra_data': [
        for (final r in _extraRows)
          if (r.labelCtrl.text.trim().isNotEmpty)
            {'label': r.labelCtrl.text.trim(), 'value': r.valueCtrl.text.trim()},
      ],
    };
    try {
      if (_isEdit) {
        await api.updateWarranty(widget.existing!.id, body);
      } else {
        await api.createWarranty(body);
      }
      if (mounted) Navigator.pop(context, true);
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

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.warrantyDeleteConfirmTitle),
        content: Text(l10n.warrantyDeleteConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await api.deleteWarranty(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sanitizeUiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isOwner = ref.watch(userRoleProvider) == 'owner';
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.warrantyEditTitle : l10n.warrantyAddTitle),
        actions: [
          if (_isEdit && isOwner)
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space16),
          children: [
            AppTextField(
              label: l10n.warrantyCustomerName,
              controller: _nameCtrl,
              capitalizeWords: true,
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyCustomerPhone,
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.warrantyCustomerPhoneRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.space16),
            Row(children: [
              Expanded(
                child: AppTextField(
                  label: l10n.warrantyProduct,
                  controller: _productCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.warrantyProductRequired
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              OutlinedButton(
                onPressed: _pickItem,
                // The app-wide OutlinedButton theme defaults to a
                // full-width minimumSize (for buttons meant to fill their
                // parent); a compact inline button next to a text field
                // must override it, or the Row gives it loose width while
                // its minWidth constraint demands infinity — an invalid
                // combination that crashes layout (same pattern as the
                // Cancel/Confirm buttons in home_screen.dart's dialogs).
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(l10n.warrantyPickItem),
              ),
            ]),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantySerialNumber,
              controller: _serialCtrl,
            ),
            const SizedBox(height: AppSpacing.space16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(labelText: l10n.warrantyPurchaseDate),
                child: Text(_dateFmt.format(_purchaseDate)),
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyPeriodMonths,
              controller: _monthsCtrl,
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? l10n.warrantyPeriodInvalid : null;
              },
            ),
            const SizedBox(height: AppSpacing.space24),
            Text(l10n.warrantyExtraDetails,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.space8),
            for (final row in _extraRows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: AppTextField(
                      label: l10n.warrantyDetailLabel,
                      controller: row.labelCtrl,
                      enabled: row.templateKey == null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      label: l10n.warrantyDetailValue,
                      controller: row.valueCtrl,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeRow(row),
                  ),
                ]),
              ),
            OutlinedButton.icon(
              onPressed: _addAdHocRow,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.warrantyAddDetail),
            ),
            const SizedBox(height: AppSpacing.space16),
            AppTextField(
              label: l10n.warrantyNotes,
              controller: _notesCtrl,
            ),
            const SizedBox(height: AppSpacing.space24),
            PrimaryButton(
              text: _saving ? l10n.commonSaving : l10n.commonSave,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemPickerSheet extends StatefulWidget {
  final List<Item> items;
  const _ItemPickerSheet({required this.items});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = widget.items
        .where((i) =>
            _query.trim().isEmpty ||
            i.name.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l10n.warrantyPickItem,
              isDense: true,
              prefixIcon: const Icon(Icons.search_outlined, size: 18),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpacing.space8),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final item = filtered[i];
                return ListTile(
                  title: Text(item.name),
                  subtitle: item.category != null ? Text(item.category!) : null,
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
