import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// The cashier's pick from [showBatchPicker]. [batch] null = opening stock, so
/// a pick is wrapped to tell it apart from a dismissed sheet.
typedef BatchChoice = ({StockBatch? batch});

/// "12 Sep 2026" from the server's YYYY-MM-DD; the raw text if it won't parse.
String formatBatchDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('d MMM yyyy').format(d);
}

/// Ask which stock batch [title] is sold from. [options] come from
/// [StockBatch.options]; [openingQty] is shown on the opening-stock row.
/// Purchase cost appears only when the server sent it — owners only.
/// Returns null when the sheet is dismissed.
Future<BatchChoice?> showBatchPicker(
  BuildContext context, {
  required String title,
  required List<StockBatch?> options,
  required double? openingQty,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<BatchChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.batchPickerTitle,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  Text(title,
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in options)
                    ListTile(
                      title: Text(b == null
                          ? l10n.batchOpeningStock
                          : (b.batchNo?.isNotEmpty ?? false)
                              ? l10n.batchLabel(b.batchNo!)
                              : formatBatchDate(b.receivedDate)),
                      subtitle: Text([
                        if (b != null) l10n.batchPurchased(formatBatchDate(b.receivedDate)),
                        l10n.batchQtyLeft(
                            formatQty(b?.qtyRemaining ?? openingQty ?? 0)),
                        if (b?.unitCost != null)
                          l10n.batchCost(b!.unitCost!.toStringAsFixed(2)),
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(ctx, (batch: b)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
