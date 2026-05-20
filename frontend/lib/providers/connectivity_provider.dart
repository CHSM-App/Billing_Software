import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../services/offline_service.dart';

// ---------------------------------------------------------------------------
// Connectivity notifier — polls /api/health every 15 seconds
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
    if (state != ok) state = ok;
  }

  /// Called by api.dart safe wrappers when a SocketException is caught.
  void markOffline() {
    if (state) state = false;
  }

  /// Called externally to force an immediate re-check.
  Future<void> recheck() => _check();
}

// ---------------------------------------------------------------------------
// Pending sync count — how many offline bills are waiting
// ---------------------------------------------------------------------------

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  // Re-read whenever connectivity changes (after a sync)
  ref.watch(connectivityProvider);
  return OfflineService.instance.getPendingCount();
});
