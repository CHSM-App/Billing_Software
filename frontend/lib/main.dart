import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'api.dart';
import 'providers.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/offline_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await OfflineService.instance.init();
  runApp(const ProviderScope(child: BillingApp()));
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billing App',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const _Splash(),
    );
  }
}

class _Splash extends ConsumerStatefulWidget {
  const _Splash();

  @override
  ConsumerState<_Splash> createState() => _SplashState();
}

class _SplashState extends ConsumerState<_Splash> {
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
          // Invalidate so the next read re-fetches from SharedPreferences.
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

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
