import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../services/realtime_service.dart';

// ---------------------------------------------------------------------------
// Connectivity
//
// [connectivityProvider] is the source-of-truth bool: true = online.
//
// It is driven entirely by PUSH signals — nothing polls the server:
//   1. The realtime WebSocket's connection state. The app already holds that
//      socket open for the whole session, and a socket that is up is proof the
//      server is reachable. It reconnects itself every 3s, so it doubles as the
//      retry loop. This is the primary signal.
//   2. api.dart's markOnline/markOffline — any real request that reaches (or
//      fails to reach) the server updates the state too.
//
// There used to be a third signal: a /health backoff poll, plus an OS-level
// connectivity_plus listener that fired an HTTP reachability check on every
// network event. Both are gone. The poll was self-defeating — /health sat
// behind the rate limiter, so once a shop tripped the limit the poll got 429s,
// read them as "offline", and kept polling, spending the budget as fast as the
// window refilled it. The OS listener was worse than useless on Windows, where
// connectivity_plus reports whatever the Network List Manager believes and NLA
// calls a working connection "no internet" whenever its msftconnecttest probe
// is blocked. The socket answers both questions with zero HTTP traffic.
//
// The socket signal is gated on app lifecycle: while the app is backgrounded
// the OS suspends the socket, so its drop carries no information about the
// shop's internet and is ignored. Without that gate every return to the app
// replayed the same false sequence — offline bar, then a green "Back online"
// flash — even though nothing had ever gone down.
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
  StreamSubscription<bool>? _socketSub;
  Timer? _offlineGraceTimer;
  AppLifecycleListener? _lifecycle;
  bool _recheckInFlight = false;

  /// Whether the app is in the foreground. A socket drop only counts as
  /// evidence of an outage while it is.
  bool _foreground = true;

  /// How long a socket drop must persist before the user is told they're
  /// offline. Longer than RealtimeService's 3s reconnect, so a drop that
  /// recovers normally never reaches the UI at all.
  static const Duration _offlineGrace = Duration(seconds: 5);

  @override
  bool build() {
    ref.onDispose(() {
      _socketSub?.cancel();
      _offlineGraceTimer?.cancel();
      _lifecycle?.dispose();
    });
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    _socketSub = RealtimeService.instance.connection.listen((connected) {
      _offlineGraceTimer?.cancel();
      if (connected) {
        // A live socket is proof, so trust it immediately.
        markOnline();
      } else {
        // A dropped socket is NOT proof of an outage, so don't alarm anyone yet.
        // The server closes every socket on each deploy/app-pool recycle, and
        // its 30s ping/pong terminates any client that misses a single pong —
        // neither means the shop lost internet. Reacting instantly would flash
        // "No connection" then "Back online" on every till, every deploy. The
        // socket retries in 3s; only if that fails do we say anything.
        //
        // Backgrounding drops it too — the OS suspends the socket. That says
        // nothing about the shop's internet, so it must not arm the timer:
        // otherwise every return to the app replayed offline → "Back online".
        if (_foreground) {
          _offlineGraceTimer = Timer(_offlineGrace, markOffline);
        }
      }
    });
    return true; // optimistic default
  }

  /// Foreground/background transitions.
  ///
  /// Leaving: cancel any pending offline verdict, because from here on a socket
  /// drop is expected rather than informative.
  ///
  /// Returning: [RealtimeService.connection] only emits on CHANGE, so a socket
  /// that went down while we were away will never re-announce itself. Read the
  /// current state directly and start the grace period now, so a genuine outage
  /// still surfaces a few seconds after the user comes back.
  void _onLifecycleState(AppLifecycleState lifecycleState) {
    final foreground = lifecycleState == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _offlineGraceTimer?.cancel();
    if (foreground && !RealtimeService.instance.isConnected) {
      _offlineGraceTimer = Timer(_offlineGrace, markOffline);
    }
  }

  /// Current known connectivity — true when the app has decided it's offline.
  /// api.dart reads this to throttle requests while offline instead of letting
  /// each one block for the full timeout. It still lets one request through
  /// every few seconds as a probe, so a user action can recover the state even
  /// when the socket never connects (e.g. a proxy that blocks WebSockets, or
  /// before login when there is no socket at all).
  bool get isOffline => !state;

  /// Called by api.dart when a request fails to reach the server, and by the
  /// socket when it drops. No poll is started — the socket's own reconnect is
  /// the retry, and api.dart's probe covers the case where there is no socket.
  void markOffline() {
    if (!state) return;
    state = false;
    ref.read(connectivityBannerProvider.notifier).showOffline();
  }

  /// Called by api.dart whenever any request completes with an HTTP response —
  /// reaching the server at all means we are online again.
  void markOnline() {
    if (state) return;
    state = true;
    ref.read(connectivityBannerProvider.notifier).showBackOnline();
  }

  /// Force an immediate re-check (the "Retry" button on the license screen,
  /// pull-to-refresh). This is the one place that still calls /health, and only
  /// ever in response to a deliberate user action — never on a timer.
  Future<void> recheck() async {
    if (_recheckInFlight) return;
    _recheckInFlight = true;
    try {
      if (await checkReachable()) {
        markOnline();
      } else {
        markOffline();
      }
    } finally {
      _recheckInFlight = false;
    }
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
