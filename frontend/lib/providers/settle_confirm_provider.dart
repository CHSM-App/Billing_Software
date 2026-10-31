import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Settle asks "are you sure?" first. Per device, on by default.
/// Logout wipes prefs, so it falls back to on — the safe side.
class SettleConfirmNotifier extends StateNotifier<bool> {
  SettleConfirmNotifier() : super(true) {
    _load();
  }

  static const _key = 'confirm_settle';

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

final settleConfirmProvider =
    StateNotifierProvider<SettleConfirmNotifier, bool>((ref) => SettleConfirmNotifier());
