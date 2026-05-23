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

    bool hasSession = false;
    try {
      await ref.read(sessionProvider.future);
      hasSession = true;
    } catch (_) {
      hasSession = false;
    }

    if (!mounted) return;

    // If no session at all, must go to login (can't do anything without auth)
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
