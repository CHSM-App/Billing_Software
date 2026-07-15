import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../services/license_service.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Shown when the app is hard-blocked due to:
///   - Offline too long (exceeded offline limit + grace)
///   - Subscription expired / suspended
///   - No subscription yet (pending)
class LicenseBlockedScreen extends ConsumerStatefulWidget {
  final LicenseState reason;
  /// Called when a retry succeeds and the app should proceed
  final VoidCallback onUnblocked;

  const LicenseBlockedScreen({
    super.key,
    required this.reason,
    required this.onUnblocked,
  });

  @override
  ConsumerState<LicenseBlockedScreen> createState() =>
      _LicenseBlockedScreenState();
}

class _LicenseBlockedScreenState extends ConsumerState<LicenseBlockedScreen> {
  bool _checking = false;
  String? _errorMessage;

  Future<void> _logout() async {
    await ref.read(sessionProvider.notifier).clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _retry() async {
    final l10n = context.l10n;
    setState(() {
      _checking = true;
      _errorMessage = null;
    });

    try {
      // Always attempt online check — don't rely on cached connectivity state
      final status = await LicenseService.instance.check(isOnline: true);

      if (!mounted) return;

      if (status.state == LicenseState.allowed ||
          status.state == LicenseState.grace) {
        widget.onUnblocked();
        return;
      }

      final rawError = LicenseService.instance.lastOnlineError;
      final isSessionExpired = rawError != null && rawError.contains('401');
      if (isSessionExpired) {
        await _logout();
        return;
      }
      setState(() {
        _errorMessage = rawError == null
            ? _messageForState(l10n, status.state)
            : sanitizeUiErrorMessage(rawError);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.licenseConnectFailed;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _messageForState(AppLocalizations l10n, LicenseState state) {
    switch (state) {
      case LicenseState.blockedSubscription:
        return l10n.licenseMsgSubscription;
      case LicenseState.blockedPending:
        return l10n.licenseMsgPending;
      case LicenseState.blockedOffline:
        return l10n.licenseMsgStillOffline;
      default:
        return l10n.licenseMsgVerifyFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isOfflineBlock = widget.reason == LicenseState.blockedOffline;
    final isPending = widget.reason == LicenseState.blockedPending;

    final icon = isOfflineBlock
        ? Icons.wifi_off_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : Icons.lock_outline_rounded;

    final title = isOfflineBlock
        ? l10n.licenseTitleOffline
        : isPending
            ? l10n.licenseTitlePending
            : l10n.licenseTitleExpired;

    final subtitle = isOfflineBlock
        ? l10n.licenseSubtitleOffline
        : isPending
            ? l10n.licenseSubtitlePending
            : l10n.licenseSubtitleExpired;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isOfflineBlock
                        ? AppColors.warningLight
                        : AppColors.errorLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 40,
                    color: isOfflineBlock ? AppColors.warning : AppColors.error,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: AppFont.style(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: AppFont.style(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                if (isOfflineBlock)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _checking ? null : _retry,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                          _checking ? l10n.licenseChecking : l10n.commonRetry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_outlined),
                    label: Text(l10n.logout),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.licenseBrandFooter,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
