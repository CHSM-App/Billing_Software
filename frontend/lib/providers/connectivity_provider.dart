import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

// ---------------------------------------------------------------------------
// Connectivity
//
// [connectivityProvider] is the source-of-truth bool: true = online.
//
// Recovery is driven by TWO signals so "back online" is detected fast and
// reliably (the previous /health-poll-only approach could get stuck):
//   1. The OS network state (connectivity_plus) — fires the instant wifi/mobile
//      connects or drops. This is the primary, immediate signal.
//   2. api.dart's markOnline/markOffline — any real request that reaches (or
//      fails to reach) the server updates the state too.
//   3. A /health backoff poll while offline, as a belt-and-suspenders fallback.
//
// On any "OS says we have a network" event we confirm with a lightweight server
// reachability check before declaring online, so we don't flip online when the
// device joined a wifi that can't actually reach the backend.
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
  StreamSubscription<List<ConnectivityResult>>? _osSub;
  bool _recheckInFlight = false;

  // Backoff schedule for the recovery poll while offline (seconds). Frequent at
  // first (the outage is often momentary), then eased off to spare the battery.
  static const List<int> _backoffSeconds = [2, 3, 5, 8, 13, 20];

  @override
  bool build() {
    ref.onDispose(() {
      _stopPolling();
      _osSub?.cancel();
    });
    _startOsListener();
    return true; // optimistic default
  }

  // ── OS network state (primary, immediate signal) ──────────────────────────

  void _startOsListener() {
    final conn = Connectivity();
    // React to every OS connectivity change (wifi/mobile connect or drop).
    _osSub = conn.onConnectivityChanged.listen(_onOsConnectivity);
    // And check the current state once at startup, so we're correct immediately.
    conn.checkConnectivity().then(_onOsConnectivity).catchError((_) {});
  }

  void _onOsConnectivity(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) {
      // "No network" is a HINT, never a verdict — keep the recovery poll running.
      //
      // On Windows connectivity_plus reports whatever the Network List Manager
      // believes, and NLA decides "connected to the internet" by probing
      // msftconnecttest.com. Plenty of shop routers and ISPs block or hijack
      // that probe, so Windows shows the "no internet" globe while the
      // connection works perfectly — and the app used to take that at face
      // value, stop polling, and sit on "You are offline" forever with no way
      // back. Only the server probe gets to decide; the OS event just makes us
      // check sooner.
      markOffline();
      return;
    }
    // OS says we have a network — but wifi could be captive/unreachable, so
    // confirm the backend is actually reachable before declaring online.
    _recheckReachability();
  }

  /// Confirm server reachability (any response = online). Guarded so overlapping
  /// OS events + poll ticks don't stack requests.
  Future<void> _recheckReachability() async {
    if (_recheckInFlight) return;
    _recheckInFlight = true;
    try {
      final ok = await checkReachable();
      if (ok) {
        markOnline();
      } else {
        markOffline();
      }
    } finally {
      _recheckInFlight = false;
    }
  }

  /// Current known connectivity — true when the app has decided it's offline.
  /// api.dart reads this to FAST-FAIL requests while offline instead of letting
  /// each one block for the full request timeout; the recovery poll is what
  /// re-probes the server and flips us back online.
  bool get isOffline => !state;

  /// Called by api.dart when a request fails to reach the server. Always starts
  /// the recovery poll — nothing else re-probes the server, so skipping it is
  /// how the app got stuck offline permanently.
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
  Future<void> recheck() => _recheckReachability();

  // ── Active recovery polling (fallback while offline) ───────────────────────

  void _startPolling() {
    if (_pollTimer != null) return; // already polling
    _pollAttempt = 0;
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    final delay = _backoffSeconds[
        _pollAttempt.clamp(0, _backoffSeconds.length - 1)];
    _pollTimer = Timer(Duration(seconds: delay), () async {
      _pollTimer = null; // this timer has fired; clear so re-arm is allowed
      if (state) return; // already online (OS event beat us to it)
      final ok = await checkReachable();
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
