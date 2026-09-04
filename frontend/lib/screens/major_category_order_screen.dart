import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_ext.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/shell_app_bar.dart';

/// Owner-only: drag to arrange the order major categories appear in on the
/// billing screen's chip strip. Saved to THIS device only (see
/// major_category_order_provider.dart) — there is nothing to sync, so no
/// server round trip and no "saving…" state; a drag simply sticks.
class MajorCategoryOrderScreen extends ConsumerWidget {
  const MajorCategoryOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final majorsAsync = ref.watch(majorCategoryOrderProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ShellAppBar(title: Text(l10n.categoryOrderTitle)),
          Expanded(
            child: majorsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorWidget(
                error: e,
                onRetry: () =>
                    ref.read(majorCategoryOrderProvider.notifier).reload(),
              ),
              data: (majors) {
                if (majors.isEmpty) {
                  return EmptyState(
                    icon: Icons.dashboard_customize_outlined,
                    message: l10n.categoryOrderEmpty,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.space16,
                          AppSpacing.space16, AppSpacing.space16, AppSpacing.space8),
                      child: Text(
                        l10n.categoryOrderHint,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space16, vertical: AppSpacing.space8),
                        itemCount: majors.length,
                        onReorder: (oldIndex, newIndex) {
                          final next = List<String>.of(majors);
                          if (newIndex > oldIndex) newIndex -= 1;
                          final moved = next.removeAt(oldIndex);
                          next.insert(newIndex, moved);
                          ref
                              .read(majorCategoryOrderProvider.notifier)
                              .reorder(next);
                        },
                        itemBuilder: (context, index) {
                          final major = majors[index];
                          return Container(
                            key: ValueKey(major),
                            margin: const EdgeInsets.only(bottom: AppSpacing.space8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.medium),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              title: Text(major,
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600)),
                              trailing: const Icon(Icons.drag_handle,
                                  color: AppColors.textSecondary),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
