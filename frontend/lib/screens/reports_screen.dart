import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(reportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.read(reportProvider.notifier).reload(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.wifi_off_outlined,
          message: e.toString(),
          actionLabel: 'Retry',
          onAction: () => ref.read(reportProvider.notifier).reload(),
        ),
        data: (r) => _buildReport(context, ref, r),
      ),
    );
  }

  Widget _buildReport(
      BuildContext context, WidgetRef ref, Map<String, dynamic> r) {
    final date =
        r['date'] as String? ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    final billCount = r['bill_count'] as int? ?? 0;
    final totalRevenue =
        double.tryParse(r['total_revenue'].toString()) ?? 0.0;
    final byMode = r['by_payment_mode'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: () async => ref.read(reportProvider.notifier).reload(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.space24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  DateFormat('EEEE, dd MMMM yyyy')
                      .format(DateTime.parse('${date}T00:00:00')),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space24),

                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Total Bills',
                        value: '$billCount',
                        icon: Icons.receipt_long_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space16),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Total Revenue',
                        value: '₹${totalRevenue.toStringAsFixed(2)}',
                        icon: Icons.currency_rupee_outlined,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space24),

                Text('By Payment Mode',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.space16),

                ...['cash', 'upi', 'card', 'credit', 'other'].map((mode) {
                  final amount =
                      double.tryParse(byMode[mode]?.toString() ?? '0') ?? 0.0;
                  if (amount == 0 && billCount > 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                    child: AppCard(
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.small),
                            ),
                            child: Icon(_modeIcon(mode),
                                size: 18, color: AppColors.primary),
                          ),
                          const SizedBox(width: AppSpacing.space12),
                          Expanded(
                            child: Text(mode.toUpperCase(),
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          Text(
                            '₹${amount.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: amount > 0
                                      ? AppColors.textPrimary
                                      : AppColors.textDisabled,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                if (billCount == 0) ...[
                  const SizedBox(height: AppSpacing.space32),
                  const EmptyState(
                    icon: Icons.bar_chart_outlined,
                    message: 'No finalized bills today yet.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _modeIcon(String mode) {
    return switch (mode) {
      'cash' => Icons.payments_outlined,
      'upi' => Icons.phone_android_outlined,
      'card' => Icons.credit_card_outlined,
      'credit' => Icons.account_balance_outlined,
      _ => Icons.more_horiz_outlined,
    };
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.space8),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
