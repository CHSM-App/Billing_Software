import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';

// ---------------------------------------------------------------------------
// Connectivity notifier — starts optimistically online.
// Goes offline when api.dart catches a SocketException (markOffline).
// Comes back online on an explicit recheck (e.g. pull-to-refresh).
// No background polling — reduces server load.
// ---------------------------------------------------------------------------

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

class ConnectivityNotifier extends Notifier<bool> {
  @override
  bool build() => true; // optimistic default

  /// Called by api.dart safe wrappers when a SocketException is caught.
  void markOffline() {
    if (state) state = false;
  }

  /// Called by api.dart whenever any request completes with an HTTP response —
  /// reaching the server at all means we are online again. Without this, a
  /// single transient failure left the app stuck showing "No Internet" until a
  /// manual pull-to-refresh, even after connectivity was restored.
  void markOnline() {
    if (!state) state = true;
  }

  /// Called externally to force an immediate re-check (e.g. pull-to-refresh).
  Future<void> recheck() async {
    final ok = await checkHealth();
    if (state != ok) state = ok;
  }
}
