import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

// ---------------------------------------------------------------------------
// Connectivity notifier — polls /api/health every 15 seconds.
// Automatically triggers a sync when the device comes back online.
// ---------------------------------------------------------------------------

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

class ConnectivityNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    _startPolling();
    return true; // optimistic default
  }

  void _startPolling() {
    _check(); // immediate first check
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  Future<void> _check() async {
    final ok = await checkHealth();
    if (state == ok) return; // no change — nothing to do

    state = ok;
  }

  /// Called by api.dart safe wrappers when a SocketException is caught.
  void markOffline() {
    if (state) state = false;
  }

  /// Called externally to force an immediate re-check (e.g. pull-to-refresh).
  Future<void> recheck() => _check();
}
