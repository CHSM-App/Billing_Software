import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// TODO: Uncomment after running `flutterfire configure` to generate this file:
import 'firebase_options.dart';

import 'api.dart';
import 'providers.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/license_screen.dart';
import 'services/offline_service.dart';
import 'services/license_service.dart';
import 'core/services/remote_config_service.dart';
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

  await VittamRemoteConfig.instance.initialize();
  await OfflineService.instance.init();

  runApp(const ProviderScope(child: BillingApp()));
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vittam',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
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

    // Wire connectivity notifier into api.dart
    final notifier = ref.read(connectivityProvider.notifier);
    setConnectivityNotifier(notifier);
    if (!ok) notifier.markOffline();

    // --- License check ---
    final licenseStatus = await LicenseService.instance.check(isOnline: ok);

    if (!mounted) return;

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
