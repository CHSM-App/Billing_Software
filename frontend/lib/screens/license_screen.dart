import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/license_service.dart';
import '../providers/connectivity_provider.dart';
import '../theme/app_theme.dart';

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

  Future<void> _retry() async {
    setState(() {
      _checking = true;
      _errorMessage = null;
    });

    final isOnline = ref.read(connectivityProvider);
    if (!isOnline) {
      setState(() {
        _checking = false;
        _errorMessage = 'Still offline. Connect to the internet and try again.';
      });
      return;
    }

    final status = await LicenseService.instance.check(isOnline: true);

    if (!mounted) return;

    if (status.state == LicenseState.allowed ||
        status.state == LicenseState.grace) {
      widget.onUnblocked();
    } else {
      setState(() {
        _checking = false;
        _errorMessage = _messageForState(status.state);
      });
    }
  }

  String _messageForState(LicenseState state) {
    switch (state) {
      case LicenseState.blockedSubscription:
        return 'Your subscription has expired or been suspended. Please contact support.';
      case LicenseState.blockedPending:
        return 'Your account is pending activation. Please contact support.';
      case LicenseState.blockedOffline:
        return 'Still offline. Connect to the internet and try again.';
      default:
        return 'Could not verify subscription. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOfflineBlock = widget.reason == LicenseState.blockedOffline;
    final isPending = widget.reason == LicenseState.blockedPending;

    final icon = isOfflineBlock
        ? Icons.wifi_off_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : Icons.lock_outline_rounded;

    final title = isOfflineBlock
        ? 'Go Online to Continue'
        : isPending
            ? 'Account Pending Activation'
            : 'Subscription Expired';

    final subtitle = isOfflineBlock
        ? "You've been offline too long.\nConnect to the internet to verify your subscription."
        : isPending
            ? "Your account is under review.\nContact support to activate your subscription."
            : "Your subscription has expired or been suspended.\nContact support to renew.";

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
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
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
                      label: Text(_checking ? 'Checking…' : 'Retry'),
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
                const SizedBox(height: 16),
                Text(
                  'VengurlaTech Billing',
                  style: TextStyle(
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
