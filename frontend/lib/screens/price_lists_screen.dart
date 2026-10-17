import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Owner screen: the shop's price lists (Party, Wholesale, ...). Billing picks
/// one on the order card; see [PriceList].
class PriceListsScreen extends ConsumerWidget {
  const PriceListsScreen({super.key});

  String _pct(double p) => '${p > 0 ? '+' : ''}${p.toStringAsFixed(p % 1 == 0 ? 0 : 2)}%';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lists = ref.watch(priceListsProvider);
    void open([PriceList? list]) => Navigator.push(context,
        MaterialPageRoute(builder: (_) => _PriceListEditScreen(list: list)));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPriceLists)),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.errorSomethingWentWrong)),
        data: (lists) => lists.isEmpty
            ? EmptyState(
                icon: Icons.sell_outlined,
                message: l10n.priceListsEmpty,
                actionLabel: l10n.priceListNew,
                onAction: open,
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final l in lists)
                    ListTile(
                      leading: const Icon(Icons.sell_outlined, color: AppColors.primary),
                      title: Text(l.name),
                      subtitle: Text([
                        if (l.adjustPct != null) _pct(l.adjustPct!),
                        if (l.prices.isNotEmpty) '${l.prices.length} ₹',
                      ].join('  ·  ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(l),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_price_list',
        onPressed: open,
        icon: const Icon(Icons.add),
        label: Text(l10n.priceListNew),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// One row of the editor: an item, or one size of a sized item.
class _Row {
  final Item item;
  final ItemVariant? variant;
  _Row(this.item, this.variant);
  String get key => variant == null ? item.id : '${item.id}:${variant!.id}';
  String get label => variant == null ? item.name : '${item.name} (${variant!.label})';
  double? get basePrice => variant != null ? (variant!.price ?? item.price) : item.price;
}

class _PriceListEditScreen extends ConsumerStatefulWidget {
  final PriceList? list;
  const _PriceListEditScreen({this.list});

  @override
  ConsumerState<_PriceListEditScreen> createState() => _PriceListEditScreenState();
}

class _PriceListEditScreenState extends ConsumerState<_PriceListEditScreen> {
  late final _name = TextEditingController(text: widget.list?.name ?? '');
  late final _pct = TextEditingController(
      text: widget.list?.adjustPct == null ? '' : _fmt(widget.list!.adjustPct!));
  // Fixed prices by row key. Controllers are made lazily as rows scroll in.
  late final Map<String, String> _prices = {
    for (final e in (widget.list?.prices ?? const <String, double>{}).entries)
      e.key: _fmt(e.value),
  };
  final _controllers = <String, TextEditingController>{};
  String _search = '';
  bool _saving = false;

  static String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  @override
  void dispose() {
    _name.dispose();
    _pct.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key) => _controllers.putIfAbsent(
      key, () => TextEditingController(text: _prices[key] ?? ''));

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : null,
      ));

  Future<void> _save(List<_Row> rows) async {
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(l10n.priceListNameRequired, isError: true);
    final pctText = _pct.text.trim();
    final pct = pctText.isEmpty ? null : double.tryParse(pctText);
    if (pctText.isNotEmpty && pct == null) {
      return _snack(l10n.priceListBadNumber, isError: true);
    }
    final byKey = {for (final r in rows) r.key: r};
    final items = <Map<String, dynamic>>[];
    for (final e in _prices.entries) {
      final text = e.value.trim();
      final row = byKey[e.key];
      if (text.isEmpty || row == null) continue; // blank, or item since deleted
      final p = double.tryParse(text);
      if (p == null || p < 0) return _snack(l10n.priceListBadNumber, isError: true);
      items.add({
        'item_id': row.item.id,
        if (row.variant != null) 'variant_id': row.variant!.id,
        'price': p,
      });
    }
    final body = {'name': name, 'adjust_pct': pct, 'items': items};
    setState(() => _saving = true);
    try {
      if (widget.list == null) {
        await createPriceList(body);
      } else {
        await updatePriceList(widget.list!.id, body);
      }
      await ref.read(priceListsProvider.notifier).reload();
      if (!mounted) return;
      _snack(l10n.priceListSaved);
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.priceListDeleteConfirm(widget.list!.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonDelete,
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deletePriceList(widget.list!.id);
      await ref.read(priceListsProvider.notifier).reload();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) _snack(sanitizeUiErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = ref.watch(itemsProvider).valueOrNull ?? const <Item>[];
    final rows = [
      for (final i in items)
        if (i.hasVariants) ...[for (final v in i.variants) _Row(i, v)] else _Row(i, null),
    ];
    final q = _search.trim().toLowerCase();
    final shown = q.isEmpty ? rows : rows.where((r) => r.label.toLowerCase().contains(q)).toList();
    final pct = double.tryParse(_pct.text.trim());
    final numbers = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.list?.name ?? l10n.priceListNew),
        actions: [
          if (widget.list != null)
            IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _saving ? null : _delete,
            ),
          TextButton(
            onPressed: _saving ? null : () => _save(rows),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: shown.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _name,
                  maxLength: 60,
                  decoration: InputDecoration(labelText: l10n.priceListName),
                ),
                TextField(
                  controller: _pct,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.priceListAdjust,
                    helperText: l10n.priceListAdjustHint,
                    helperMaxLines: 2,
                    suffixText: '%',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.space16),
                Text(l10n.priceListItemsHint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.space8),
                TextField(
                  decoration: InputDecoration(
                    hintText: l10n.commonSearch,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_outlined, size: 18),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ]),
            );
          }
          final r = shown[i - 1];
          final base = r.basePrice;
          // What a blank field bills at: the % rule on the default price.
          final ruled = base == null || pct == null || pct == 0
              ? base
              : double.parse((base * (1 + pct / 100)).toStringAsFixed(2));
          return ListTile(
            title: Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(l10n.priceListDefaultPrice(
                base == null ? '–' : base.toStringAsFixed(2))),
            trailing: SizedBox(
              width: 110,
              child: TextField(
                controller: _ctrl(r.key),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numbers,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '₹ ',
                  hintText: ruled?.toStringAsFixed(2),
                ),
                onChanged: (v) => _prices[r.key] = v,
              ),
            ),
          );
        },
      ),
    );
  }
}
