import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../l10n/l10n_ext.dart';

final _amt = NumberFormat('#,##0');
final _timeFmt = DateFormat('h:mm a');
final _weekdayFmt = DateFormat('EEE'); // Mon, Tue, …
final _fullDayFmt = DateFormat('EEE, dd MMM yyyy');

/// One bar in the last-7-days chart (a calendar day + its net sales).
class _ChartDay {
  final DateTime date;
  final double revenue;
  const _ChartDay({required this.date, required this.revenue});
}

/// Sales-only report page. Shows total sales, orders, average bill, a last-7-days
/// bar chart, top-selling items, the cash/UPI split and recent bills.
/// (No net-revenue or expenses — sales figures only.)
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  // Tapped day in the 7-day chart; null = show the peak day by default.
  int? _selectedDayIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(reportSummaryFilterProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        ShellAppBar(
          title: Text(l10n.reportsTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: l10n.reportsChangePeriod,
              onPressed: () => _showPeriodPicker(context, filter),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: l10n.commonRefresh,
              onPressed: () {
                ref.invalidate(reportSummaryProvider);
                ref.invalidate(weeklySalesProvider);
              },
            ),
          ],
        ),
        Expanded(
          child: summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorWidget(
              error: e,
              onRetry: () => ref.invalidate(reportSummaryProvider),
            ),
            data: (summary) => RefreshIndicator(
              onRefresh: () async => ref.invalidate(reportSummaryProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildPeriodChips(l10n, filter),
                  const SizedBox(height: 12),
                  _buildSalesCard(l10n, summary, filter),
                  const SizedBox(height: 16),
                  // Last-7-days chart uses its OWN provider (not the period
                  // filter), so it always shows the real last week.
                  _buildLast7DaysSection(l10n),
                  const SizedBox(height: 16),
                  if (summary.topItems.isNotEmpty) ...[
                    _buildTopItems(l10n, summary),
                    const SizedBox(height: 16),
                  ],
                  _buildPaymentSplit(l10n, summary),
                  const SizedBox(height: 16),
                  if (summary.recentBills.isNotEmpty)
                    _buildRecentBills(l10n, summary),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  bool _isToday(ReportSummaryFilter f) {
    final now = DateTime.now();
    return f.from.year == now.year &&
        f.from.month == now.month &&
        f.from.day == now.day &&
        f.to.year == now.year &&
        f.to.month == now.month &&
        f.to.day == now.day;
  }

  // ── Period quick-chips ──────────────────────────────────────────────────────
  Widget _buildPeriodChips(AppLocalizations l10n, ReportSummaryFilter filter) {
    return Row(
      children: [
        Expanded(child: _PeriodChip(label: l10n.reportsToday, onTap: _setToday)),
        const SizedBox(width: 8),
        Expanded(
            child: _PeriodChip(label: l10n.reportsMonth, onTap: _setThisMonth)),
        const SizedBox(width: 8),
        Expanded(child: _PeriodChip(label: l10n.reportsYear, onTap: _setThisYear)),
      ],
    );
  }

  void _setToday() {
    final now = DateTime.now();
    ref.read(reportSummaryFilterProvider.notifier).state = ReportSummaryFilter(
        from: DateTime(now.year, now.month, now.day), to: now);
  }

  void _setThisMonth() {
    final now = DateTime.now();
    ref.read(reportSummaryFilterProvider.notifier).state = ReportSummaryFilter(
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month + 1, 0));
  }

  void _setThisYear() {
    final now = DateTime.now();
    ref.read(reportSummaryFilterProvider.notifier).state = ReportSummaryFilter(
        from: DateTime(now.year, 1, 1), to: DateTime(now.year, 12, 31));
  }

  Future<void> _showPeriodPicker(
      BuildContext context, ReportSummaryFilter current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(reportSummaryFilterProvider.notifier).state =
          ReportSummaryFilter(from: picked.start, to: picked.end);
    }
  }

  // ── Sales header card ───────────────────────────────────────────────────────
  Widget _buildSalesCard(
      AppLocalizations l10n, ReportSummary s, ReportSummaryFilter filter) {
    final title = _isToday(filter)
        ? l10n.reportsTotalSalesToday
        : l10n.reportsTotalSalesPeriod;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadow.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white70,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('₹${_amt.format(s.netSales)}',
              style: const TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 16),
          Row(
            children: [
              _headerStat(l10n.reportsOrders, '${s.billCount}'),
              const SizedBox(width: 28),
              _headerStat(l10n.reportsAvgBill, '₹${_amt.format(s.avgBill)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }

  // ── Last 7 days bar chart ───────────────────────────────────────────────────
  // Watches its own weeklySalesProvider so the chart is unaffected by the date
  // filter — it always shows the true last 7 days.
  Widget _buildLast7DaysSection(AppLocalizations l10n) {
    final weeklyAsync = ref.watch(weeklySalesProvider);
    return weeklyAsync.when(
      loading: () => _SectionCard(
        title: l10n.reportsLast7Days,
        child: const SizedBox(
            height: 120, child: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (weekly) => _buildLast7DaysChart(l10n, weekly),
    );
  }

  Widget _buildLast7DaysChart(AppLocalizations l10n, List<DailyReport> weekly) {
    // Build a fixed 7-day window ending today. Days with no bills get ₹0 bars,
    // so the chart always shows all 7 weekdays. Data comes from the weekly
    // provider (independent of the report period).
    final today = DateTime.now();
    final byDay = {for (final d in weekly) d.day: d.revenue};
    final days = List.generate(7, (i) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      return _ChartDay(date: date, revenue: byDay[key] ?? 0.0);
    });

    final maxRev = days.fold(0.0, (m, d) => d.revenue > m ? d.revenue : m);
    // Default selection = the peak day (highlighted), until the user taps one.
    var peakIndex = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i].revenue > days[peakIndex].revenue) peakIndex = i;
    }
    final selectedIndex = _selectedDayIndex ?? peakIndex;
    final selected = days[selectedIndex];

    return _SectionCard(
      title: l10n.reportsLast7Days,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (i) {
                final d = days[i];
                final frac = maxRev > 0 ? d.revenue / maxRev : 0.0;
                final isSelected = i == selectedIndex;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedDayIndex = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FractionallySizedBox(
                              alignment: Alignment.bottomCenter,
                              // Min 6% so a ₹0 day still shows a visible stub.
                              heightFactor: frac == 0 ? 0.06 : frac,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _weekdayFmt.format(d.date),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          // Selected-day detail strip.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fullDayFmt.format(selected.date),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
                Text('₹${_amt.format(selected.revenue)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top selling items ───────────────────────────────────────────────────────
  Widget _buildTopItems(AppLocalizations l10n, ReportSummary s) {
    final items = s.topItems.length > 5 ? s.topItems.sublist(0, 5) : s.topItems;
    return _SectionCard(
      title: l10n.reportsTopSellingItems,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(l10n.reportsSoldCount(items[i].qtySold.toInt()),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('₹${_amt.format(items[i].revenue)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Payment split ───────────────────────────────────────────────────────────
  // Shows every payment mode that has sales, so the tiles sum exactly to Total
  // Sales. Cash + UPI always shown (even at ₹0); card/credit/other only when > 0.
  Widget _buildPaymentSplit(AppLocalizations l10n, ReportSummary s) {
    final order = ['cash', 'upi', 'card', 'credit', 'other'];
    final present = order.where((m) {
      final v = s.byPaymentMode[m] ?? 0;
      return m == 'cash' || m == 'upi' || v > 0;
    }).toList();

    Widget tile(String mode) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadow.small,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_paymentLabel(l10n, mode),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text('₹${_amt.format(s.byPaymentMode[mode] ?? 0)}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
        );

    // Lay out two per row so it stays tidy with 2–5 modes.
    final rows = <Widget>[];
    for (var i = 0; i < present.length; i += 2) {
      final left = present[i];
      final right = i + 1 < present.length ? present[i + 1] : null;
      rows.add(Row(
        children: [
          Expanded(child: tile(left)),
          const SizedBox(width: 12),
          Expanded(child: right != null ? tile(right) : const SizedBox()),
        ],
      ));
      if (i + 2 < present.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  String _paymentLabel(AppLocalizations l10n, String mode) {
    switch (mode) {
      case 'cash':
        return l10n.paymentCash;
      case 'upi':
        return l10n.paymentUpi;
      case 'card':
        return l10n.paymentCard;
      case 'credit':
        return l10n.paymentCredit;
      case 'other':
        return l10n.paymentOther;
      default:
        return mode;
    }
  }

  // ── Recent bills ────────────────────────────────────────────────────────────
  Widget _buildRecentBills(AppLocalizations l10n, ReportSummary s) {
    return _SectionCard(
      title: l10n.reportsRecentBills,
      child: Column(
        children: [
          for (var i = 0; i < s.recentBills.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            _recentBillRow(l10n, s.recentBills[i]),
          ],
        ],
      ),
    );
  }

  Widget _recentBillRow(AppLocalizations l10n, RecentBill b) {
    final where = (b.tableNumber != null && b.tableNumber!.isNotEmpty)
        ? l10n.reportsTableLabel(b.tableNumber!)
        : ((b.customerName != null && b.customerName!.trim().isNotEmpty)
            ? b.customerName!.trim()
            : l10n.reportsParcel);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text('#${b.billNumber.split('-').last}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ),
        Expanded(
          child: Text(where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
        ),
        Text(_timeFmt.format(b.createdAt.toLocal()),
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Text('₹${_amt.format(b.net)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PeriodChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
      ),
    );
  }
}
