import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A per-device on/off billing preference, on by default. Logout wipes prefs,
/// so it falls back to on.
class PrefFlagNotifier extends StateNotifier<bool> {
  PrefFlagNotifier(this._key) : super(true) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// Whether Settle asks "are you sure?" first.
final settleConfirmProvider = StateNotifierProvider<PrefFlagNotifier, bool>(
    (ref) => PrefFlagNotifier('confirm_settle'));

/// Whether billing shows the whole-bill discount (% / ₹). Per-item discounts
/// are unaffected.
final billDiscountProvider = StateNotifierProvider<PrefFlagNotifier, bool>(
    (ref) => PrefFlagNotifier('bill_discount'));
