import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A per-device on/off billing preference, on by default unless [_default]
/// says otherwise. Logout wipes prefs, so it falls back to the default.
class PrefFlagNotifier extends StateNotifier<bool> {
  PrefFlagNotifier(this._key, [this._default = true]) : super(_default) {
    _load();
  }

  final String _key;
  final bool _default;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? _default;
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

/// Whether billing rows show each item's photo (the one set in Menu Photos).
/// Off by default — photos cost data and screen width.
final billingImagesProvider = StateNotifierProvider<PrefFlagNotifier, bool>(
    (ref) => PrefFlagNotifier('billing_images', false));
