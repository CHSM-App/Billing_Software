import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_ext.dart';
import '../providers/locale_provider.dart';
import '../theme/app_theme.dart';

/// Bottom sheet listing every supported language. Selecting one updates
/// [localeProvider], which rebuilds the whole app in that language.
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(
              l10n.languagePickerTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              l10n.languagePickerSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.space16),
            for (final language in AppLanguage.values) ...[
              _LanguageTile(
                language: language,
                selected: language == current,
                onTap: () async {
                  await ref.read(localeProvider.notifier).set(language);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              const SizedBox(height: AppSpacing.space8),
            ],
            const SizedBox(height: AppSpacing.space8),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.nativeLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: selected ? AppColors.primary : null,
                        ),
                  ),
                  Text(
                    language.englishLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Compact `EN | मराठी` toggle for screens with no Settings access —
/// login, register, OTP.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLanguage.values.map((language) {
          final selected = language == current;
          return GestureDetector(
            onTap: () => ref.read(localeProvider.notifier).set(language),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                language.nativeLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
