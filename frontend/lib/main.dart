import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'api.dart';
import 'l10n/l10n_ext.dart';
import 'providers.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/license_screen.dart';
import 'services/offline_service.dart';
import 'services/license_service.dart';
import 'services/notification_service.dart';
// import 'core/services/remote_config_service.dart';  // TODO: enable when Firebase is needed
import 'features/splash/vittam_splash_screen.dart';

// Desktop-only SQLite FFI init — imported only on non-web builds.
import 'services/ffi_init_stub.dart'
    if (dart.library.io) 'services/ffi_init_native.dart' as ffi;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    ffi.initFfi();
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await OfflineService.instance.init();

  runApp(const ProviderScope(child: BillingApp()));
}

/// App-wide messenger key so background tasks can surface a SnackBar even after
/// the originating screen has been popped (e.g. optimistic draft-save failures).
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class BillingApp extends ConsumerWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(localeProvider);

    return MaterialApp(
      title: 'Vittam',
      scaffoldMessengerKey: rootMessengerKey,
      debugShowCheckedModeBanner: false,
      // Rebuilt on language change — Marathi swaps the type scale to a
      // Devanagari-capable font.
      theme: buildAppTheme(language.code),
      locale: language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      initialRoute: '/',
      routes: {
        '/': (_) => const VittamSplashScreen(),
        '/home': (_) => const _AppEntry(),
      },
    );
  }
}

/// Runs the real app startup after the update splash clears.
/// Handles session validation, connectivity, and license checks.
class _AppEntry extends ConsumerStatefulWidget {
  const _AppEntry();

  @override
  ConsumerState<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<_AppEntry> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    // Reset any bills stuck in 'syncing' from a previous crash
    await OfflineService.instance.resetStaleSyncing();

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

    if (!mounted) return;

    if (!hasSession) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    // Init notifications now that we have an authenticated session
    NotificationService.instance.init();

    // Wire connectivity notifier into api.dart
    final notifier = ref.read(connectivityProvider.notifier);
    setConnectivityNotifier(notifier);
    if (!ok) notifier.markOffline();

    // --- License check ---
    final licenseStatus = await LicenseService.instance.check(isOnline: ok);

    if (!mounted) return;

    if (licenseStatus.sessionInvalid) {
      // Local session (access/refresh token) is invalid or unreadable —
      // reconnecting won't fix this, so send the user straight to login
      // instead of showing a misleading "go online" screen.
      await ref.read(sessionProvider.notifier).clear();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    if (licenseStatus.state == LicenseState.blockedOffline ||
        licenseStatus.state == LicenseState.blockedSubscription ||
        licenseStatus.state == LicenseState.blockedPending) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LicenseBlockedScreen(
            reason: licenseStatus.state,
            onUnblocked: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MainShell(licenseStatus: licenseStatus),
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainShell(licenseStatus: licenseStatus),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
