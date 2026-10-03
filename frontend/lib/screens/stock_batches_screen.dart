import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/batch_picker.dart' show formatBatchDate;

/// Stock batches still on the shelf, oldest first — so the owner can see what
/// has been sitting longest and discount it before it goes stale. Owner only.
class StockBatchesScreen extends StatefulWidget {
  const StockBatchesScreen({super.key});

  @override
  State<StockBatchesScreen> createState() => _StockBatchesScreenState();
}

class _StockBatchesScreenState extends State<StockBatchesScreen> {
  /// Batches this old are flagged as stock to clear.
  static const _oldAfterDays = 90;

  late Future<List<dynamic>> _future = getStockBatches();

  Future<void> _refresh() async {
    setState(() => _future = getStockBatches());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.stockBatchesTitle)),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(snap.error.toString()));
          }
          final rows = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: rows.isEmpty
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.space24),
                      child: Text(l10n.stockBatchesEmpty,
                          textAlign: TextAlign.center),
                    ),
                  ])
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _row(context,
                        Map<String, dynamic>.from(rows[i] as Map)),
                  ),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> b) {
    final l10n = context.l10n;
    final days = (b['days_old'] as num?)?.toInt() ?? 0;
    final old = days >= _oldAfterDays;
    double n(Object? v) => double.tryParse('$v') ?? 0;
    final batchNo = b['batch_no']?.toString();
    return ListTile(
      tileColor: old ? AppColors.warningLight : null,
      title: Text(b['item_name']?.toString() ?? ''),
      subtitle: Text([
        if (batchNo != null && batchNo.isNotEmpty) l10n.batchLabel(batchNo),
        l10n.batchPurchased(formatBatchDate(b['received_date'].toString())),
        if (b['vendor_name'] != null) b['vendor_name'].toString(),
        l10n.stockBatchesRow(
          formatQty(n(b['qty_remaining'])),
          formatQty(n(b['qty_received'])),
          n(b['unit_cost']).toStringAsFixed(2),
        ),
      ].join(' · ')),
      trailing: Text(
        l10n.stockBatchesDaysOld(days),
        style: TextStyle(
          color: old ? AppColors.warning : AppColors.textSecondary,
          fontWeight: old ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
