import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers/credit_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import 'credit_customer_bills_screen.dart';

/// The Credit (udhaari) tab: a list of customers who owe money on credit bills.
/// Tapping a customer opens their unpaid bills to settle/print/send.
class CreditScreen extends ConsumerWidget {
  /// When true, embedded inside the Orders tab — the parent supplies the app
  /// bar, so render only the debtor list body.
  final bool embedded;

  const CreditScreen({super.key, this.embedded = false});

  void _openCustomer(BuildContext context, CreditCustomer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreditCustomerBillsScreen(customer: customer),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final body = _buildBody(context, ref);

    if (embedded) return body;

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.creditTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.invalidate(creditCustomersProvider),
              tooltip: l10n.commonRefresh,
            ),
          ],
        ),
        Expanded(child: body),
      ]),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final customersAsync = ref.watch(creditCustomersProvider);

    return customersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(
        error: e,
        onRetry: () => ref.invalidate(creditCustomersProvider),
      ),
      data: (customers) {
        if (customers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: AppSpacing.space16),
                Text(
                  l10n.creditEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(creditCustomersProvider.notifier).reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.space12),
            itemCount: customers.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.space8),
            itemBuilder: (context, i) => _CustomerCard(
              customer: customers[i],
              onTap: () => _openCustomer(context, customers[i]),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final CreditCustomer customer;
  final VoidCallback onTap;

  const _CustomerCard({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = (customer.customerName != null &&
            customer.customerName!.trim().isNotEmpty)
        ? customer.customerName!.trim()
        : customer.customerPhone;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(Icons.person_outline, color: AppColors.error),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.creditUnpaidBills(customer.unpaidCount),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${customer.outstanding.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.error),
                  ),
                  Text(
                    l10n.creditOutstanding,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.textDisabled),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right, color: AppColors.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
