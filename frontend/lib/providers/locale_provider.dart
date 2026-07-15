import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages the app ships with. Add a new entry here plus an
/// `app_<code>.arb` file to support another language.
enum AppLanguage {
  english('en', 'English', 'English'),
  marathi('mr', 'मराठी', 'Marathi');

  const AppLanguage(this.code, this.nativeLabel, this.englishLabel);

  /// Locale code, e.g. 'en'.
  final String code;

  /// Name written in the language itself — what the picker shows.
  final String nativeLabel;

  /// Name in English, shown as a secondary line in the picker.
  final String englishLabel;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.english,
      );
}

/// Persisted app language.
///
/// Stored in SharedPreferences under [prefsKey]. Note that
/// `AuthStorage.clearSession()` wipes SharedPreferences on logout — it
/// re-writes this key afterwards so the language choice outlives a logout.
class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier() : super(AppLanguage.english) {
    _load();
  }

  static const prefsKey = 'app_language';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKey);
    if (saved != null) {
      state = AppLanguage.fromCode(saved);
      return;
    }
    // No stored choice yet — follow the device language if we support it,
    // so a Marathi phone opens the app in Marathi on first launch.
    final deviceCode = PlatformDispatcher.instance.locale.languageCode;
    final matched = AppLanguage.values
        .where((l) => l.code == deviceCode)
        .firstOrNull;
    if (matched != null) {
      state = matched;
      await prefs.setString(prefsKey, matched.code);
    }
  }

  Future<void> set(AppLanguage language) async {
    if (state == language) return;
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, language.code);
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) => LocaleNotifier());
