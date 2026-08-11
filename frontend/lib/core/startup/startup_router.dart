import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api.dart';
import '../../providers.dart';
import '../../screens/login_screen.dart';
import '../../screens/main_shell.dart';
import '../../screens/license_screen.dart';
import '../../services/offline_service.dart';
import '../../services/license_service.dart';
import '../../services/notification_service.dart';
import '../../services/realtime_service.dart';

/// Runs the real app startup — offline cleanup, connectivity, session
/// validation and the license check — and RETURNS the screen the app should
/// land on. It never navigates itself; the caller (the splash) navigates once
/// the minimum splash time has also elapsed, so the splash is shown exactly
/// once with no intermediate loader.
///
/// Side effects that must run before entering the app (notification init,
/// realtime socket, connectivity wiring, clearing an invalid session) still
/// happen here.
///
/// [onLicenseUnblocked] is invoked from the license-blocked screen once the
/// user resolves the block, and should navigate to the app shell.
Future<Widget> resolveStartupDestination(
  WidgetRef ref, {
  required void Function(LicenseStatus licenseStatus) onLicenseUnblocked,
}) async {
  // Reset any bills/drafts stuck in 'syncing' from a previous crash
  await OfflineService.instance.resetStaleSyncing();
  await OfflineService.instance.resetStaleSyncingDrafts();

  final ok = await checkHealth();

  // Retry reading the session up to 3 times — SharedPreferences can return
  // empty on the first read after a cold boot or system-level app kill.
  bool hasSession = false;
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      await ref.read(sessionProvider.future);
      hasSession = true;
      break;
    } catch (_) {
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 300));
        ref.invalidate(sessionProvider);
      }
    }
  }

  if (!hasSession) {
    return const LoginScreen();
  }

  // Init notifications now that we have an authenticated session
  NotificationService.instance.init();

  // Open the real-time WebSocket for live cross-device updates
  // (kitchen / tables / open-orders).
  RealtimeService.instance.start();

  // Wire connectivity notifier into api.dart
  final notifier = ref.read(connectivityProvider.notifier);
  setConnectivityNotifier(notifier);
  if (!ok) notifier.markOffline();

  // --- License check ---
  final licenseStatus = await LicenseService.instance.check(isOnline: ok);

  if (licenseStatus.sessionInvalid) {
    // Local session (access/refresh token) is invalid or unreadable —
    // reconnecting won't fix this, so send the user straight to login
    // instead of showing a misleading "go online" screen.
    await ref.read(sessionProvider.notifier).clear();
    return const LoginScreen();
  }

  if (licenseStatus.state == LicenseState.blockedOffline ||
      licenseStatus.state == LicenseState.blockedSubscription ||
      licenseStatus.state == LicenseState.blockedPending ||
      licenseStatus.state == LicenseState.blockedDevice) {
    return LicenseBlockedScreen(
      reason: licenseStatus.state,
      onUnblocked: () => onLicenseUnblocked(licenseStatus),
    );
  }

  return MainShell(licenseStatus: licenseStatus);
}
