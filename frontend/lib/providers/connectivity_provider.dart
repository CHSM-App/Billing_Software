import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

// ---------------------------------------------------------------------------
// Connectivity
//
// [connectivityProvider] is the source-of-truth bool: true = online.
//   • Starts optimistically online.
//   • Flips to offline when api.dart throws a NetworkException (markOffline).
//   • Flips back to online when any request reaches the server (markOnline),
//     OR when the active recovery poll below succeeds.
//
// While offline we actively poll /health on a backoff so recovery is automatic
// and the user never has to pull-to-refresh to clear a stale "No connection".
// Polling only runs while offline, so there is no steady-state server load.
//
// [connectivityBannerProvider] is a separate UI-only signal that drives the
// YouTube-style bar: offline / backOnline (a brief green flash) / online.
// ---------------------------------------------------------------------------

enum ConnectivityBanner {
  /// Fully connected and quiet — no bar shown.
  online,

  /// No connection — persistent dark "No connection" bar.
  offline,

  /// Connection just came back — brief green "Back online" flash that
  /// auto-dismisses back to [online].
  backOnline,
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

/// UI signal for the connectivity bar. Kept separate from the bool so the flash
/// is a pure presentation concern and the rest of the app only reads a bool.
final connectivityBannerProvider =
    NotifierProvider<ConnectivityBannerNotifier, ConnectivityBanner>(
        ConnectivityBannerNotifier.new);

class ConnectivityNotifier extends Notifier<bool> {
  Timer? _pollTimer;
  int _pollAttempt = 0;

  // Backoff schedule for the recovery poll while offline (seconds). Frequent at
  // first (the outage is often momentary), then eased off to spare the battery.
  static const List<int> _backoffSeconds = [3, 5, 8, 13, 20, 30];

  @override
  bool build() {
    ref.onDispose(_stopPolling);
    return true; // optimistic default
  }

  /// Called by api.dart when a request fails to reach the server.
  void markOffline() {
    if (state) {
      state = false;
      ref.read(connectivityBannerProvider.notifier).showOffline();
    }
    _startPolling();
  }

  /// Called by api.dart whenever any request completes with an HTTP response —
  /// reaching the server at all means we are online again.
  void markOnline() {
    _stopPolling();
    if (!state) {
      state = true;
      ref.read(connectivityBannerProvider.notifier).showBackOnline();
    }
  }

  /// Force an immediate re-check (e.g. pull-to-refresh or a "Retry" button).
  Future<void> recheck() async {
    final ok = await checkHealth();
    if (ok) {
      markOnline();
    } else {
      markOffline();
    }
  }

  // ── Active recovery polling (only while offline) ──────────────────────────

  void _startPolling() {
    if (_pollTimer != null) return; // already polling
    _pollAttempt = 0;
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    final delay = _backoffSeconds[
        _pollAttempt.clamp(0, _backoffSeconds.length - 1)];
    _pollTimer = Timer(Duration(seconds: delay), () async {
      if (state) {
        _stopPolling();
        return;
      }
      final ok = await checkHealth();
      if (ok) {
        markOnline(); // stops polling + flashes "Back online"
      } else {
        _pollAttempt++;
        _scheduleNextPoll();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollAttempt = 0;
  }
}

class ConnectivityBannerNotifier extends Notifier<ConnectivityBanner> {
  Timer? _flashTimer;

  /// How long the green "Back online" flash stays before it self-dismisses.
  static const Duration _flashDuration = Duration(seconds: 2);

  @override
  ConnectivityBanner build() {
    ref.onDispose(() => _flashTimer?.cancel());
    return ConnectivityBanner.online;
  }

  void showOffline() {
    _flashTimer?.cancel();
    state = ConnectivityBanner.offline;
  }

  void showBackOnline() {
    // Only flash if we were actually showing the offline bar; a plain online
    // request should never trigger a spurious green pulse.
    if (state != ConnectivityBanner.offline) return;
    state = ConnectivityBanner.backOnline;
    _flashTimer?.cancel();
    _flashTimer = Timer(_flashDuration, () {
      if (state == ConnectivityBanner.backOnline) {
        state = ConnectivityBanner.online;
      }
    });
  }
}
