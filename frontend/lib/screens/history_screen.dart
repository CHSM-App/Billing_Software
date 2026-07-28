import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/printer_service.dart';
import '../services/receipt_labels.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// Maps a raw bill status value from the API to a localized display label.
String _billStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'finalized' => l10n.historyStatusFinalized,
    'voided' => l10n.historyStatusVoided,
    'draft' => l10n.historyStatusDraft,
    _ => status,
  };
}

/// Maps a raw payment mode value from the API to a localized display label.
String _paymentModeLabel(AppLocalizations l10n, String mode) {
  return switch (mode) {
    'cash' => l10n.paymentCash,
    'upi' => l10n.paymentUpi,
    'card' => l10n.paymentCard,
    'credit' => l10n.paymentCredit,
    _ => l10n.paymentOther,
  };
}

StatusType _billStatusType(String status) => switch (status) {
      'finalized' => StatusType.success,
      'voided' => StatusType.error,
      _ => StatusType.warning,
    };

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _timeFmt = DateFormat('hh:mm a');

  @override
  void initState() {
    super.initState();
    // Listen for search text changes to debounce-free update
    ref.listenManual(billFilterProvider, (_, __) {});
  }

  Future<void> _pickDateRange() async {
    final filter = ref.read(billFilterProvider);
    final firstDate = DateTime(2020);
    final lastDate = DateTime.now();
    // Clamp the current filter range into [firstDate, lastDate] so the picker
    // never receives an out-of-bounds initialDateRange (which makes it fail
    // silently — this was why "Custom" did nothing after choosing "All").
    DateTime clampD(DateTime d) =>
        d.isBefore(firstDate) ? firstDate : (d.isAfter(lastDate) ? lastDate : d);
    final initStart = clampD(filter.from);
    final initEnd = clampD(filter.to).isBefore(initStart)
        ? initStart
        : clampD(filter.to);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: initStart, end: initEnd),
    );
    if (picked != null) {
      ref
          .read(billFilterProvider.notifier)
          .setDateRange(picked.start, picked.end);
    }
  }

  void _showBillDetail(Bill bill) {
    final userRole = ref.read(userRoleProvider);
    showDialog(
      context: context,
      builder: (_) => _BillDetailDialog(
        bill: bill,
        userRole: userRole,
        onVoided: () => ref.invalidate(billsProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(billFilterProvider);
    final billsAsync = ref.watch(billsProvider);

    return Scaffold(
      body: Column(
        children: [
          ShellAppBar(title: Text(l10n.historyBillHistoryTitle)),
          Expanded(child: _buildBody(l10n, billsAsync, filter)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _presetChipsSliver(
          AppLocalizations l10n, BillFilterState filter) =>
      SliverToBoxAdapter(
        child: SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16, AppSpacing.space12, AppSpacing.space16, 0),
            children: [
              _presetChip(l10n.historyFilterToday, BillDatePreset.today, filter),
              _presetChip(
                  l10n.historyFilterYesterday, BillDatePreset.yesterday, filter),
              _presetChip(
                  l10n.historyFilterThisMonth, BillDatePreset.thisMonth, filter),
              _presetChip(
                  l10n.historyFilterLastMonth, BillDatePreset.lastMonth, filter),
              _presetChip(l10n.historyFilterAll, BillDatePreset.all, filter),
              _presetChip(
                  l10n.historyFilterCustom, BillDatePreset.custom, filter,
                  onCustom: _pickDateRange),
            ],
          ),
        ),
      );

  Widget _presetChip(
      String label, BillDatePreset preset, BillFilterState filter,
      {Future<void> Function()? onCustom}) {
    final selected = filter.preset == preset;
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
        side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border),
        onSelected: (_) {
          if (onCustom != null) {
            onCustom();
          } else {
            ref.read(billFilterProvider.notifier).setPreset(preset);
          }
        },
      ),
    );
  }

  SliverToBoxAdapter _filterRowSliver(
          AppLocalizations l10n, BillFilterState filter) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.space16, AppSpacing.space8,
              AppSpacing.space16, AppSpacing.space8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.historySearchBillOrPhone,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_outlined,
                          size: 18, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space16, vertical: 0),
                    ),
                    onChanged: (v) =>
                        ref.read(billFilterProvider.notifier).setSearch(v),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  filter.from == filter.to ||
                          filter.from.isAtSameMomentAs(filter.to)
                      ? _dateFmt.format(filter.from)
                      : '${_dateFmt.format(filter.from)} – ${_dateFmt.format(filter.to)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space12, vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody(AppLocalizations l10n, AsyncValue<List<Bill>> billsAsync,
      BillFilterState filter) {
    return billsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(billsProvider);
          await ref.read(billsProvider.future);
        },
        child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          _presetChipsSliver(l10n, filter),
          _filterRowSliver(l10n, filter),
          SliverFillRemaining(
            child: AppErrorWidget(
              error: e,
              onRetry: () => ref.invalidate(billsProvider),
            ),
          ),
        ]),
      ),
      data: (bills) {
        if (bills.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(billsProvider);
              await ref.read(billsProvider.future);
            },
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              _presetChipsSliver(l10n, filter),
          _filterRowSliver(l10n, filter),
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: l10n.historyNoBillsForPeriod,
                ),
              ),
            ]),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(billsProvider);
            await ref.read(billsProvider.future);
          },
          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
            _presetChipsSliver(l10n, filter),
          _filterRowSliver(l10n, filter),
            _billsSliver(l10n, bills),
          ]),
        );
      },
    );
  }

  /// Responsive bill list: single column on phones, a grid (2–3 columns) on
  /// wider screens so large displays don't waste horizontal space.
  Widget _billsSliver(AppLocalizations l10n, List<Bill> bills) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space32),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          // Aim for ~360px per card; cap at 3 columns.
          final columns = width >= 1100
              ? 3
              : width >= 720
                  ? 2
                  : 1;
          if (columns == 1) {
            return SliverList.separated(
              itemCount: bills.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.space8),
              itemBuilder: (_, i) => _buildBillCard(l10n, bills[i]),
            );
          }
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.space8,
              crossAxisSpacing: AppSpacing.space8,
              mainAxisExtent: 84,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildBillCard(l10n, bills[i]),
              childCount: bills.length,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBillCard(AppLocalizations l10n, Bill bill) {
    return AppCard(
      onTap: () => _showBillDetail(bill),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bill.billNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(width: AppSpacing.space8),
                    StatusBadge(
                      label: _billStatusLabel(l10n, bill.status),
                      status: _billStatusType(bill.status),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.historyBillMeta(
                    _timeFmt.format(bill.createdAt.toLocal()),
                    _paymentModeLabel(l10n, bill.paymentMode),
                    l10n.historyItemCount(bill.items.length),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                if (bill.customerName != null)
                  Text(bill.customerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${(bill.total - bill.discountAmount).toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (bill.discountAmount > 0)
                Text(
                  '₹${bill.total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill detail dialog
// ---------------------------------------------------------------------------
class _BillDetailDialog extends StatelessWidget {
  final Bill bill;
  final String userRole;
  final VoidCallback onVoided;

  const _BillDetailDialog({
    required this.bill,
    required this.userRole,
    required this.onVoided,
  });

  Future<void> _void(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.historyVoidBill),
        content: Text(l10n.historyVoidConfirmBody(bill.billNumber)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.historyVoid,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await voidBill(bill.id);
      if (!context.mounted) return;
      Navigator.pop(context);
      onVoided();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(bill.billNumber,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          StatusBadge(
            label: _billStatusLabel(l10n, bill.status),
            status: _billStatusType(bill.status),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('dd MMM yyyy, hh:mm a')
                    .format(bill.createdAt.toLocal()),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              if (bill.customerName != null) ...[
                const SizedBox(height: AppSpacing.space4),
                Text(bill.customerName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (bill.customerPhone != null)
                Text(bill.customerPhone!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.space16),
              ...bill.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.itemName} × ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '₹${item.lineTotal.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: AppSpacing.space24),
              if (bill.taxAmount > 0) ...[
                _row(context, l10n.billingSubtotal,
                    '₹${bill.subtotal.toStringAsFixed(2)}'),
                _row(context, l10n.billingTax,
                    '₹${bill.taxAmount.toStringAsFixed(2)}'),
                const SizedBox(height: AppSpacing.space4),
              ],
              _row(context, l10n.billingTotalAmount,
                  '₹${bill.total.toStringAsFixed(2)}',
                  bold: bill.discountAmount == 0),
              if (bill.discountAmount > 0) ...[
                const SizedBox(height: 4),
                _row(context, l10n.billingDiscount,
                    '− ₹${bill.discountAmount.toStringAsFixed(2)}',
                    valueColor: const Color(0xFF16A34A)),
                const Divider(height: AppSpacing.space12),
                _row(context, l10n.billingNetPayable,
                    '₹${(bill.total - bill.discountAmount).toStringAsFixed(2)}',
                    bold: true),
              ],
              const SizedBox(height: AppSpacing.space4),
              _row(context, l10n.historyPayment,
                  _paymentModeLabel(l10n, bill.paymentMode)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose)),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            final labels = ReceiptLabels.from(
                l10n, Localizations.localeOf(context).languageCode);
            try {
              await PrinterService.instance.printBill(bill, labels: labels);
            } on PrinterException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e.message == 'No printer configured'
                    ? l10n.historyNoPrinterConfigured
                    : l10n.billingPrintFailed(e.message)),
                backgroundColor: AppColors.error,
              ));
            }
          },
          child: Text(l10n.historyReprint),
        ),
        if (userRole == 'owner' && bill.status != 'voided')
          TextButton(
            onPressed: () => _void(context),
            child: Text(l10n.historyVoid,
                style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary))),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? (bold ? AppColors.textPrimary : null),
                  )),
        ],
      ),
    );
  }
}
