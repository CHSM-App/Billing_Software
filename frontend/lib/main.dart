import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'l10n/l10n_ext.dart';
import 'providers.dart';
import 'theme/app_theme.dart';
import 'services/offline_service.dart';
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

  // Remote Config drives the force-update gate (see VittamSplashScreen). Init
  // is best-effort: a fetch failure just leaves defaults so the app still opens.
  try {
    await VittamRemoteConfig.instance.initialize();
  } catch (_) {}

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
      home: const VittamSplashScreen(),
    );
  }
}

