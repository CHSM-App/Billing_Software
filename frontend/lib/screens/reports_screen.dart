import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

final _amt = NumberFormat('#,##0.00');
final _dateFmt = DateFormat('dd MMM yyyy');
final _dayFmt = DateFormat('dd MMM');

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reportSummaryFilterProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return FadeTransition(
      opacity: _fade,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Reports'),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Change period',
              onPressed: () => _showPeriodPicker(context, filter),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(reportSummaryProvider),
            ),
          ],
        ),
        body: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorWidget(
            error: e,
            onRetry: () => ref.invalidate(reportSummaryProvider),
          ),
          data: (summary) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _buildPeriodBar(filter),
              const SizedBox(height: 12),
              _buildSummaryCards(summary, isWide),
              const SizedBox(height: 20),
              _buildPaymentBreakdown(summary),
              const SizedBox(height: 20),
              if (summary.expensesByCategory.isNotEmpty) ...[
                _buildExpenseByCategory(summary),
                const SizedBox(height: 20),
              ],
              if (summary.daily.isNotEmpty) ...[
                _buildDailyBreakdown(summary),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Period bar ─────────────────────────────────────────────────────────────
  Widget _buildPeriodBar(ReportSummaryFilter filter) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_dateFmt.format(filter.from)}  –  ${_dateFmt.format(filter.to)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _PeriodChip(label: 'Today', onTap: () => _setToday()),
              const SizedBox(width: 6),
              _PeriodChip(label: 'Month', onTap: () => _setThisMonth()),
              const SizedBox(width: 6),
              _PeriodChip(label: 'Year', onTap: () => _setThisYear()),
            ],
          ),
        ],
      ),
    );
  }

  void _setToday() {
    final now = DateTime.now();
    ref.read(reportSummaryFilterProvider.notifier).state =
        ReportSummaryFilter(from: DateTime(now.year, now.month, now.day), to: now);
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

  Future<void> _showPeriodPicker(BuildContext context, ReportSummaryFilter current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(reportSummaryFilterProvider.notifier).state =
          ReportSummaryFilter(from: picked.start, to: picked.end);
    }
  }

  // ── Summary cards ──────────────────────────────────────────────────────────
  Widget _buildSummaryCards(ReportSummary s, bool isWide) {
    final cards = [
      _StatCard(
        label: 'Revenue',
        value: 'Rs. ${_amt.format(s.totalRevenue)}',
        icon: Icons.trending_up_rounded,
        gradient: AppColors.primaryGradient,
        sub: '${s.billCount} bills',
      ),
      _StatCard(
        label: 'Expenses',
        value: 'Rs. ${_amt.format(s.totalExpenses)}',
        icon: Icons.trending_down_rounded,
        gradient: LinearGradient(colors: [AppColors.error, const Color(0xFFFF6B6B)]),
        sub: s.expensesByCategory.isNotEmpty
            ? '${s.expensesByCategory.length} categories'
            : 'No expenses',
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map((c) => Expanded(child: Padding(
                padding: const EdgeInsets.only(right: 12), child: c)))
            .toList(),
      );
    }
    return Column(
      children: cards.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
    );
  }

  // ── Payment mode breakdown ─────────────────────────────────────────────────
  Widget _buildPaymentBreakdown(ReportSummary s) {
    final modes = s.byPaymentMode.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = modes.fold(0.0, (sum, e) => sum + e.value);

    return _SectionCard(
      title: 'Revenue by Payment Mode',
      icon: Icons.payments_outlined,
      child: Column(
        children: modes.map((e) {
          final pct = total > 0 ? e.value / total : 0.0;
          return _BarRow(
            label: e.key.toUpperCase(),
            value: 'Rs. ${_amt.format(e.value)}',
            percent: pct,
            color: _paymentColor(e.key),
          );
        }).toList(),
      ),
    );
  }

  // ── Expense by category ────────────────────────────────────────────────────
  Widget _buildExpenseByCategory(ReportSummary s) {
    final total = s.expensesByCategory.fold(0.0, (sum, e) => sum + e.value);
    return _SectionCard(
      title: 'Expenses by Category',
      icon: Icons.pie_chart_outline_rounded,
      child: Column(
        children: s.expensesByCategory.map((e) {
          final pct = total > 0 ? e.value / total : 0.0;
          return _BarRow(
            label: e.key,
            value: 'Rs. ${_amt.format(e.value)}',
            percent: pct,
            color: _categoryColor(e.key),
            subtitle: '${(pct * 100).toStringAsFixed(1)}%',
          );
        }).toList(),
      ),
    );
  }

  // ── Daily breakdown ────────────────────────────────────────────────────────
  Widget _buildDailyBreakdown(ReportSummary s) {
    final maxRevenue = s.daily.fold(0.0, (m, d) => d.revenue > m ? d.revenue : m);
    return _SectionCard(
      title: 'Daily Breakdown',
      icon: Icons.calendar_view_week_outlined,
      child: Column(
        children: s.daily.map((d) {
          final isProfit = d.profit >= 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(_dayFmt.format(DateTime.parse(d.day)),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Revenue bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxRevenue > 0 ? d.revenue / maxRevenue : 0,
                              minHeight: 8,
                              backgroundColor: AppColors.surfaceVariant,
                              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: 3),
                          // Expense bar
                          if (d.expenses > 0)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxRevenue > 0 ? d.expenses / maxRevenue : 0,
                                minHeight: 5,
                                backgroundColor: AppColors.surfaceVariant,
                                valueColor: const AlwaysStoppedAnimation(AppColors.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Rs. ${_amt.format(d.revenue)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: AppColors.success)),
                        Text(
                          isProfit
                              ? '+${_amt.format(d.profit)}'
                              : '-${_amt.format(d.profit.abs())}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isProfit ? AppColors.success : AppColors.error),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 12),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _paymentColor(String mode) {
    switch (mode) {
      case 'cash': return AppColors.success;
      case 'upi': return AppColors.primary;
      case 'card': return AppColors.accent;
      case 'credit': return AppColors.warning;
      default: return AppColors.textSecondary;
    }
  }

  Color _categoryColor(String cat) {
    const colors = [
      Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFDB2777),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF059669),
      Color(0xFF0891B2), Color(0xFF7C3AED),
    ];
    return colors[cat.hashCode.abs() % colors.length];
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final LinearGradient gradient;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadow.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

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
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String value;
  final double percent;
  final Color color;
  final String? subtitle;

  const _BarRow({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
              if (subtitle != null)
                Text(subtitle!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 7,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.primary)),
      ),
    );
  }
}
