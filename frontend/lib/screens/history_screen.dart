import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../models/models.dart';
import '../providers.dart';
import '../services/printer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

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
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: filter.from, end: filter.to),
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
    final filter = ref.watch(billFilterProvider);
    final billsAsync = ref.watch(billsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bill History')),
      body: Column(
        children: [
          // Filters row
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16,
                AppSpacing.space16,
                AppSpacing.space16,
                AppSpacing.space8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search bill no. or phone…',
                      prefixIcon: Icon(Icons.search_outlined, size: 20),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.space16, vertical: 12),
                    ),
                    onChanged: (v) =>
                        ref.read(billFilterProvider.notifier).setSearch(v),
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
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space12, vertical: 0),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(billsAsync)),
        ],
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<Bill>> billsAsync) {
    return billsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(billsProvider);
          await ref.read(billsProvider.future);
        },
        child: ListView(children: [
          AppErrorWidget(
            error: e,
            onRetry: () => ref.invalidate(billsProvider),
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
            child: ListView(children: const [
              EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'No bills found for this period.',
              ),
            ]),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(billsProvider);
            await ref.read(billsProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space32),
            itemCount: bills.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space8),
            itemBuilder: (_, i) {
              final bill = bills[i];
              return AppCard(
                onTap: () => _showBillDetail(bill),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(bill.billNumber,
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(width: AppSpacing.space8),
                              StatusBadge(
                                label: bill.status,
                                status: bill.status == 'finalized'
                                    ? StatusType.success
                                    : bill.status == 'voided'
                                        ? StatusType.error
                                        : StatusType.warning,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_timeFmt.format(bill.createdAt.toLocal())}  ·  ${bill.paymentMode.toUpperCase()}  ·  ${bill.items.length} item${bill.items.length == 1 ? '' : 's'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          if (bill.customerName != null)
                            Text(bill.customerName!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
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
            },
          ),
        );
      },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Bill'),
        content: Text('Void bill ${bill.billNumber}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Void', style: TextStyle(color: AppColors.error)),
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
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(bill.billNumber)),
          StatusBadge(
            label: bill.status,
            status: bill.status == 'finalized'
                ? StatusType.success
                : bill.status == 'voided'
                    ? StatusType.error
                    : StatusType.warning,
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
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (bill.customerPhone != null)
                Text(bill.customerPhone!,
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
                _row(context, 'Subtotal', '₹${bill.subtotal.toStringAsFixed(2)}'),
                _row(context, 'Tax', '₹${bill.taxAmount.toStringAsFixed(2)}'),
                const SizedBox(height: AppSpacing.space4),
              ],
              _row(context, 'Total Amount', '₹${bill.total.toStringAsFixed(2)}',
                  bold: bill.discountAmount == 0),
              if (bill.discountAmount > 0) ...[
                const SizedBox(height: 4),
                _row(context, 'Discount',
                    '− ₹${bill.discountAmount.toStringAsFixed(2)}',
                    valueColor: const Color(0xFF16A34A)),
                const Divider(height: AppSpacing.space12),
                _row(context, 'Net Payable',
                    '₹${(bill.total - bill.discountAmount).toStringAsFixed(2)}',
                    bold: true),
              ],
              const SizedBox(height: AppSpacing.space4),
              _row(context, 'Payment', bill.paymentMode.toUpperCase()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close')),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await PrinterService.instance.printBill(bill);
            } on PrinterException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e.message == 'No printer configured'
                    ? 'No printer configured. Set one up in Settings.'
                    : 'Print failed: ${e.message}'),
                backgroundColor: AppColors.error,
              ));
            }
          },
          child: const Text('Reprint'),
        ),
        if (userRole == 'owner' && bill.status != 'voided')
          TextButton(
            onPressed: () => _void(context),
            child: Text('Void', style: TextStyle(color: AppColors.error)),
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
