import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart' as api;
import '../l10n/l10n_ext.dart';
import '../models/models.dart' show formatQty;
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

final _money = NumberFormat('#,##0.00');
String _rs(double v) => '₹${_money.format(v)}';

double _n(Map<String, dynamic> b, String k) => (b[k] as num?)?.toDouble() ?? 0;

/// One batch no. and the items received under it (backend/src/batches.js —
/// every item of a purchase shares its batch no.).
class _Batch {
  final String code;
  final List<Map<String, dynamic>> items;
  _Batch(this.code, this.items);

  /// Open while any of its items still has stock.
  bool get open => items.any((b) => _n(b, 'remaining') > 0);
  double sum(String k) => items.fold(0, (s, b) => s + _n(b, k));
  double get cost => sum('cost_of_sold') + sum('lost_cost');
  bool get anySold => items.any((b) => _n(b, 'sold') > 0 || _n(b, 'lost') > 0);

  /// The purchases its items came from (a typed batch no. can be reused).
  int get purchases => items
      .map((b) => '${b['vendor_name']}|${b['invoice_number']}|${b['received_date']}')
      .toSet()
      .length;
}

/// Stock batches: one card per batch no. with what it cost, sold for and
/// earned; tap for its items. Open = some stock left; Settled = all sold out
/// or written off. Owner only — opened from the Purchases screen.
class StockBatchesScreen extends StatefulWidget {
  const StockBatchesScreen({super.key});

  @override
  State<StockBatchesScreen> createState() => _StockBatchesScreenState();
}

class _StockBatchesScreenState extends State<StockBatchesScreen> {
  late Future<List<_Batch>> _future = _load();

  /// Every batch row, grouped by batch no. in the server's order (newest
  /// purchase first).
  Future<List<_Batch>> _load() async {
    final rows = await api.getStockBatchReport('all');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      groups.putIfAbsent('${r['code']}', () => []).add(r);
    }
    return [for (final e in groups.entries) _Batch(e.key, e.value)];
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(children: [
          ShellAppBar(title: Text(l10n.batchesTitle)),
          TabBar(tabs: [
            Tab(text: l10n.batchesOpen),
            Tab(text: l10n.batchesSettled),
          ]),
          Expanded(
            child: FutureBuilder<List<_Batch>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return AppErrorWidget(error: snap.error!, onRetry: () => _reload());
                }
                final all = snap.data!;
                return TabBarView(children: [
                  _list(all.where((b) => b.open).toList()),
                  _list(all.where((b) => !b.open).toList()),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _list(List<_Batch> batches) {
    if (batches.isEmpty) {
      return EmptyState(
          icon: Icons.layers_outlined, message: context.l10n.batchesNone);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: batches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _batchCard(batches[i]),
      ),
    );
  }

  Widget _batchCard(_Batch b) {
    final l10n = context.l10n;
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _BatchItemsScreen(batch: b)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _BatchIcon(open: b.open),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(b.purchases > 1 ? l10n.batchPurchases('${b.purchases}') : _source(b.items.first),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
        const Divider(height: 20),
        Row(children: [
          _Stat(l10n.batchStatItems, '${b.items.length}'),
          _Stat(l10n.batchStatSales, _rs(b.sum('revenue'))),
          _Stat(l10n.batchStatCost, _rs(b.cost)),
          _profitStat(context, b.sum('profit'), sold: b.anySold),
        ]),
      ]),
    );
  }
}

/// Every item received under one batch no., with its stock and money.
class _BatchItemsScreen extends StatelessWidget {
  final _Batch batch;
  const _BatchItemsScreen({required this.batch});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final first = batch.items.first;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(title: Text(batch.code)),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // The purchase it came from and the batch's totals.
            AppCard(
              color: AppColors.primaryLight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _BatchIcon(open: batch.open),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(batch.purchases > 1
                              ? l10n.batchPurchases('${batch.purchases}')
                              : '${first['vendor_name'] ?? batch.code}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (batch.purchases == 1)
                        Text(
                            [first['invoice_number'], first['received_date']]
                                .where((v) => v != null && '$v'.isNotEmpty)
                                .join(' · '),
                            style: _muted),
                    ]),
                  ),
                ]),
                const Divider(height: 20),
                Row(children: [
                  _Stat(l10n.batchStatItems, '${batch.items.length}'),
                  _Stat(l10n.batchStatSales, _rs(batch.sum('revenue'))),
                  _Stat(l10n.batchStatCost, _rs(batch.cost)),
                  _profitStat(context, batch.sum('profit'), sold: batch.anySold),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            for (final item in batch.items) ...[
              _itemCard(context, item, showSource: batch.purchases > 1),
              const SizedBox(height: 10),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _itemCard(BuildContext context, Map<String, dynamic> b, {bool showSource = false}) {
    final l10n = context.l10n;
    final received = _n(b, 'received');
    final sold = _n(b, 'sold');
    final held = _n(b, 'held');
    final lost = _n(b, 'lost');
    final soldAny = sold > 0 || lost > 0;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('${b['item_name'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 8),
          _ProfitPill(profit: _n(b, 'profit'), sold: soldAny),
        ]),
        // Several purchases share this batch no.: which one this item is from.
        if (showSource) ...[
          const SizedBox(height: 2),
          Text(_source(b), maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _Stat(l10n.batchStatBought, formatQty(received)),
          _Stat(l10n.batchStatSold, formatQty(sold)),
          // On held (unsettled) bills: taken from the batch, not sold yet.
          if (held > 0) _Stat(l10n.batchStatHeld, formatQty(held)),
          _Stat(l10n.batchStatLeft, formatQty(_n(b, 'remaining'))),
        ]),
        const SizedBox(height: 8),
        // How much of what was bought has gone (sold or written off).
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: received > 0 ? ((sold + lost) / received).clamp(0.0, 1.0) : 0,
            minHeight: 6,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Stat(l10n.batchStatCostUnit, _rs(_n(b, 'unit_cost'))),
          _Stat(l10n.batchStatSales, _rs(_n(b, 'revenue'))),
          _Stat(l10n.batchStatCost, _rs(_n(b, 'cost_of_sold') + _n(b, 'lost_cost'))),
        ]),
        if (lost > 0) ...[
          const SizedBox(height: 8),
          Text(l10n.batchCardLost(formatQty(lost)),
              style: const TextStyle(fontSize: 12, color: AppColors.warning)),
        ],
      ]),
    );
  }
}

const _muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);

/// Supplier · invoice · date — whichever the purchase has.
String _source(Map<String, dynamic> b) =>
    [b['vendor_name'], b['invoice_number'], b['received_date']]
        .where((v) => v != null && '$v'.isNotEmpty)
        .join(' · ');

/// A labelled figure in a row of equal columns; long amounts shrink to fit.
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color ?? AppColors.textPrimary)),
          ),
        ]),
      );
}

/// Profit (green) or loss (red); a dash while nothing has sold.
Widget _profitStat(BuildContext context, double profit, {required bool sold}) {
  final l10n = context.l10n;
  if (!sold) return _Stat(l10n.batchStatProfit, '—', color: AppColors.textSecondary);
  final loss = profit < 0;
  return _Stat(loss ? l10n.batchStatLoss : l10n.batchStatProfit, _rs(profit.abs()),
      color: loss ? AppColors.error : AppColors.success);
}

/// "Profit ₹1,365.42" / "Loss ₹…" pill, or "Not sold yet" before any sale.
class _ProfitPill extends StatelessWidget {
  final double profit;
  final bool sold;
  const _ProfitPill({required this.profit, required this.sold});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loss = profit < 0;
    final (bg, fg, text) = !sold
        ? (AppColors.surfaceVariant, AppColors.textSecondary, l10n.batchNotSold)
        : loss
            ? (AppColors.errorLight, AppColors.error, l10n.batchLoss(_money.format(-profit)))
            : (AppColors.successLight, AppColors.success, l10n.batchProfit(_money.format(profit)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// The batch's icon: tinted while it still has stock.
class _BatchIcon extends StatelessWidget {
  final bool open;
  const _BatchIcon({required this.open});

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: open ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Icon(open ? Icons.layers_outlined : Icons.task_alt,
            size: 20, color: open ? AppColors.primary : AppColors.textSecondary),
      );
}
