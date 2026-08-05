import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_state.dart';
import '../../l10n/l10n_ext.dart';
import '../../theme/app_theme.dart';

/// Update prompt styled to match the app's design system (indigo primary,
/// gradient icon badge, app radii/spacing). Non-dismissible when the update
/// is forced.
class VittamUpdateDialog extends StatelessWidget {
  // Must match android/app applicationId EXACTLY — Play Store package IDs are
  // case-sensitive, so a lowercase 'vittam' returns "item not found".
  static const _packageId = 'com.vengurlatech.Vittam';

  final UpdateState state;

  const VittamUpdateDialog({super.key, required this.state});

  static Future<bool?> showIfNeeded(
    BuildContext context,
    UpdateState state,
  ) {
    if (!state.updateAvailable) return Future.value(null);
    return showDialog<bool>(
      context: context,
      barrierDismissible: !state.forceUpdate,
      builder: (_) => VittamUpdateDialog(state: state),
    );
  }

  Future<void> _openPlayStore() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageId',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // dialogTitle/dialogMessage are optional remote-config overrides; when the
    // server does not supply them fall back to the localized defaults.
    final title =
        state.dialogTitle.isEmpty ? l10n.updateTitle : state.dialogTitle;
    final message =
        state.dialogMessage.isEmpty ? l10n.updateBody : state.dialogMessage;

    return PopScope(
      canPop: !state.forceUpdate,
      child: Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vittam logo badge — matches the splash's logo card.
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  boxShadow: AppShadow.medium,
                  border: Border.all(color: AppColors.border),
                ),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
              ),
              const SizedBox(height: AppSpacing.space16),

              Text(
                title,
                textAlign: TextAlign.center,
                style: AppFont.style(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.space8),

              Text(
                message,
                textAlign: TextAlign.center,
                style: AppFont.style(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              if (state.forceUpdate) ...[
                const SizedBox(height: AppSpacing.space16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space8),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: AppSpacing.space8),
                      Expanded(
                        child: Text(
                          l10n.updateForceNote,
                          style: AppFont.style(
                              fontSize: 12,
                              color: const Color(0xFF92400E),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.space24),

              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _openPlayStore();
                    if (context.mounted && !state.forceUpdate) {
                      Navigator.pop(context, true);
                    }
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l10n.updateNow),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.space12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                ),
              ),
              if (!state.forceUpdate) ...[
                const SizedBox(height: AppSpacing.space8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.space12),
                    ),
                    child: Text(l10n.updateLater),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
