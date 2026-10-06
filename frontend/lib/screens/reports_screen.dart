import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart' as api;
import '../providers.dart';
import '../services/sales_report_export.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import '../l10n/l10n_ext.dart';
import 'gstr1_screen.dart';
import 'gstr2_screen.dart';
import 'gstr3b_screen.dart';

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
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(reportSummaryFilterProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);
    final summaryForExport = summaryAsync.valueOrNull;

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
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined),
              tooltip: 'Download report',
              onPressed: _downloading || summaryForExport == null
                  ? null
                  : () => _pickDownloadFormat(summaryForExport, filter),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: l10n.commonRefresh,
              // The daily chart now reads the summary's own breakdown, so this
              // one invalidation refreshes the whole screen.
              onPressed: () => ref.invalidate(reportSummaryProvider),
            ),
          ],
        ),
        // The period chips live OUTSIDE the async branch on purpose. Inside it
        // they were replaced by the spinner on every tap and vanished entirely
        // on an error, leaving only the error widget — which is what "the
        // report is not shown by filter" actually looked like. The filter must
        // stay on screen and stay tappable no matter what the fetch is doing.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildPeriodChips(l10n, filter),
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
                  _buildSalesCard(l10n, summary, filter),
                  const SizedBox(height: 16),
                  _buildPeriodSalesSection(l10n, filter),
                  const SizedBox(height: 16),
                  if (summary.topItems.isNotEmpty) ...[
                    _buildTopItems(l10n, summary),
                    const SizedBox(height: 16),
                  ],
                  _buildPaymentSplit(l10n, summary),
                  const SizedBox(height: 16),
                  // GSTR-1 return — only meaningful once GST invoicing is on,
                  // since with the toggle off no bill carries tax.
                  if (ref.watch(gstEnabledProvider)) ...[
                    _buildGstReturns(),
                    const SizedBox(height: 16),
                  ],
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

  // ---------------------------------------------------------------------------
  // Download (CSV / PDF) of the currently selected period
  // ---------------------------------------------------------------------------

  Future<void> _pickDownloadFormat(
      ReportSummary summary, ReportSummaryFilter filter) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          const Text('Download sales report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${_fullDayFmt.format(filter.from)} – ${_fullDayFmt.format(filter.to)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined,
                color: AppColors.primary),
            title: const Text('CSV (Excel)'),
            subtitle: const Text('Totals, daily sales, top items and every bill'),
            onTap: () => Navigator.pop(ctx, 'csv'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined,
                color: AppColors.primary),
            title: const Text('PDF'),
            subtitle: const Text('Print-ready summary with invoice list'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    await _download(summary, filter, pdf: choice == 'pdf');
  }

  Future<void> _download(ReportSummary summary, ReportSummaryFilter filter,
      {required bool pdf}) async {
    setState(() => _downloading = true);
    try {
      // The summary has only the 10 most recent bills; the export lists every
      // bill in the period, so fetch the full list for the same range.
      final bills = await api.getBills(from: filter.fromStr, to: filter.toStr);
      final business = ref.read(businessNameProvider);
      final slug = '${filter.fromStr}_to_${filter.toStr}';
      if (pdf) {
        final bytes = await SalesReportExport.buildPdf(
            summary: summary, bills: bills, businessName: business);
        // Platform print/save-as-PDF sheet, same as invoices and GSTR-1.
        await Printing.layoutPdf(
            onLayout: (_) async => bytes, name: 'Sales-Report-$slug');
      } else {
        final bytes = SalesReportExport.buildCsv(
            summary: summary, bills: bills, businessName: business);
        await Share.shareXFiles(
          [
            XFile.fromData(bytes,
                name: 'Sales-Report-$slug.csv', mimeType: 'text/csv')
          ],
          text: 'Sales report $slug',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not create report: ${api.sanitizeUiErrorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Entry points to the GST returns. All three live in Reports rather than
  /// Settings because they are reports, not settings.
  Widget _buildGstReturns() {
    return _SectionCard(
      title: 'GST returns',
      child: Column(children: [
        _gstRow(
          icon: Icons.description_outlined,
          colour: const Color(0xFF7C3AED),
          title: 'GSTR-1',
          subtitle: 'Sales — outward supplies',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const Gstr1Screen())),
        ),
        const Divider(height: 20),
        _gstRow(
          icon: Icons.shopping_bag_outlined,
          colour: const Color(0xFF0891B2),
          title: 'GSTR-2',
          subtitle: 'Purchase ITC summary and 2B reconciliation',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const Gstr2Screen())),
        ),
        const Divider(height: 20),
        _gstRow(
          icon: Icons.account_balance_outlined,
          colour: const Color(0xFFEA580C),
          title: 'GSTR-3B',
          subtitle: 'Monthly summary — tax payable after credit',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const Gstr3bScreen())),
        ),
      ]),
    );
  }

  Widget _gstRow({
    required IconData icon,
    required Color colour,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 20, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 20, color: AppColors.textSecondary),
        ]),
      ),
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
  /// Which preset (if any) the current filter corresponds to, so the matching
  /// chip can be lit. Without this the chips gave no feedback at all and the
  /// filter looked like it had not applied.
  _Period _activePeriod(ReportSummaryFilter filter) {
    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    if (sameDay(filter.from, DateTime(now.year, now.month, now.day)) &&
        sameDay(filter.to, now)) {
      return _Period.today;
    }
    if (sameDay(filter.from, DateTime(now.year, now.month, 1)) &&
        sameDay(filter.to, DateTime(now.year, now.month + 1, 0))) {
      return _Period.month;
    }
    if (sameDay(filter.from, DateTime(now.year, 1, 1)) &&
        sameDay(filter.to, DateTime(now.year, 12, 31))) {
      return _Period.year;
    }
    return _Period.custom;
  }

  Widget _buildPeriodChips(AppLocalizations l10n, ReportSummaryFilter filter) {
    final active = _activePeriod(filter);
    final fmt = DateFormat('d MMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: _PeriodChip(
                    label: l10n.reportsToday,
                    selected: active == _Period.today,
                    onTap: _setToday)),
            const SizedBox(width: 8),
            Expanded(
                child: _PeriodChip(
                    label: l10n.reportsMonth,
                    selected: active == _Period.month,
                    onTap: _setThisMonth)),
            const SizedBox(width: 8),
            Expanded(
                child: _PeriodChip(
                    label: l10n.reportsYear,
                    selected: active == _Period.year,
                    onTap: _setThisYear)),
          ],
        ),
        const SizedBox(height: 8),
        // Spell out the range being reported on. A custom range picked from the
        // calendar lights no chip, so this is the only confirmation of it.
        Text(
          active == _Period.today
              ? fmt.format(filter.from)
              : '${fmt.format(filter.from)} – ${fmt.format(filter.to)}',
          style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500),
        ),
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

  // ── Daily sales bar chart ──────────────────────────────────────────────────
  //
  // Driven by the SELECTED period's own daily breakdown, which the summary
  // already carries — so picking Month or Year moves this chart along with
  // everything else. It used to watch weeklySalesProvider and show the true
  // last 7 days regardless of the filter, which made the biggest block on the
  // screen look like the filter had done nothing.
  //
  // Long periods are windowed to the last 7 days IN the period rather than
  // drawn as 365 unreadable bars; the title states exactly what is shown.
  Widget _buildPeriodSalesSection(
      AppLocalizations l10n, ReportSummaryFilter filter) {
    final summary = ref.watch(reportSummaryProvider).valueOrNull;
    if (summary == null) return const SizedBox.shrink();
    return _buildDailyChart(l10n, summary.daily, filter);
  }

  Widget _buildDailyChart(AppLocalizations l10n, List<DailyReport> daily,
      ReportSummaryFilter filter) {
    // Window: at most the last 7 days of the selected period, never past today
    // (a month filter's `to` is the last day of the month, i.e. the future).
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    var end = DateTime(filter.to.year, filter.to.month, filter.to.day);
    if (end.isAfter(todayMidnight)) end = todayMidnight;
    final start = DateTime(filter.from.year, filter.from.month, filter.from.day);
    final spanDays = end.difference(start).inDays + 1;
    final barCount = spanDays.clamp(1, 7);

    final byDay = {for (final d in daily) d.day: d.revenue};
    final days = List.generate(barCount, (i) {
      final date = end.subtract(Duration(days: barCount - 1 - i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      return _ChartDay(date: date, revenue: byDay[key] ?? 0.0);
    });

    final maxRev = days.fold(0.0, (m, d) => d.revenue > m ? d.revenue : m);
    // Default selection = the peak day (highlighted), until the user taps one.
    var peakIndex = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i].revenue > days[peakIndex].revenue) peakIndex = i;
    }
    // Clamp: the window shrinks with the period (Today is a single bar), so a
    // selection made under a longer period would index past the end.
    final selectedIndex =
        (_selectedDayIndex ?? peakIndex).clamp(0, days.length - 1);
    final selected = days[selectedIndex];

    // Say what is actually plotted rather than a fixed "Last 7 days" that a
    // Month or Year filter would make untrue.
    final fmt = DateFormat('d MMM');
    final title = days.length == 1
        ? fmt.format(days.first.date)
        : '${fmt.format(days.first.date)} – ${fmt.format(days.last.date)}';

    return _SectionCard(
      title: title,
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

/// The preset the current filter matches, so one chip can be lit. [custom] is a
/// range picked from the calendar, which matches no preset.
enum _Period { today, month, year, custom }

class _PeriodChip extends StatelessWidget {
  final String label;

  /// Fills the chip. Previously every chip rendered identically, so tapping one
  /// gave no feedback and the filter looked inert.
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.primary)),
      ),
    );
  }
}
