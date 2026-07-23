import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../providers.dart';
import '../providers/open_drafts_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';
import 'home_screen.dart';

/// The "Open Orders" queue: table-less draft bills a server saved from the
/// billing page. Tapping one opens it pre-loaded in the billing screen where a
/// cashier/owner finalizes it (or a server edits and re-saves it).
class OpenDraftsScreen extends ConsumerWidget {
  const OpenDraftsScreen({super.key});

  void _openDraft(BuildContext context, WidgetRef ref, Bill draft) {
    // Start from a clean cart; HomeScreen loads the draft's items itself.
    ref.read(cartProvider.notifier).clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          activeBillId: draft.id,
          activeBillFuture: Future.value(draft),
        ),
      ),
    ).then((_) {
      // Back from the billing screen — reconcile the queue and drop the
      // borrowed cart so a draft's items never leak into a fresh order.
      ref.read(cartProvider.notifier).clear();
      ref.read(openDraftsProvider.notifier).refreshSilently();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final draftsAsync = ref.watch(openDraftsProvider);

    return Scaffold(
      body: Column(children: [
        ShellAppBar(
          // Bottom-bar root tab: never show a back arrow.
          automaticallyImplyLeading: false,
          title: Text(l10n.openOrdersTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () => ref.invalidate(openDraftsProvider),
              tooltip: l10n.commonRefresh,
            ),
          ],
        ),
        Expanded(
          child: draftsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorWidget(
              error: e,
              onRetry: () => ref.invalidate(openDraftsProvider),
            ),
            data: (drafts) {
              if (drafts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 48, color: AppColors.textDisabled),
                      const SizedBox(height: AppSpacing.space16),
                      Text(
                        l10n.openOrdersEmpty,
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
                onRefresh: () =>
                    ref.read(openDraftsProvider.notifier).reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.space12),
                  itemCount: drafts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.space8),
                  itemBuilder: (context, i) =>
                      _DraftCard(draft: drafts[i], onTap: () => _openDraft(context, ref, drafts[i])),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _DraftCard extends StatelessWidget {
  final Bill draft;
  final VoidCallback onTap;

  const _DraftCard({required this.draft, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final itemCount = draft.items.fold<double>(0, (s, it) => s + it.quantity);
    final title = (draft.customerName != null &&
            draft.customerName!.trim().isNotEmpty)
        ? draft.customerName!.trim()
        : l10n.openOrdersBillNumber(draft.billNumber);

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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.openOrdersItemCount(itemCount.toInt()),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Text(
                '₹${(draft.total - draft.discountAmount).toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textDisabled),
            ],
          ),
        ),
      ),
    );
  }
}
