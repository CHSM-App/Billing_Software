import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'dart:convert';
import '../api.dart';
import '../storage.dart';

/// Basic WebSocket client for real-time updates. Connects to the backend `/ws`
/// endpoint (authenticated with the JWT access token), and emits the small event
/// types the server broadcasts — 'kitchen', 'tables', 'drafts' — on [events].
///
/// A single listener (in the app shell) subscribes to [events] and refreshes the
/// relevant Riverpod providers. This replaces FCM as the driver of live updates.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _disposed = false;

  final _controller = StreamController<String>.broadcast();

  /// Stream of event type strings ('kitchen' | 'tables' | 'drafts').
  Stream<String> get events => _controller.stream;

  /// Derive ws(s)://host/ws from the http(s) API base URL.
  String _wsBase() {
    // baseUrl looks like http://host:port/api — strip the trailing /api and
    // swap the scheme to ws/wss.
    var b = baseUrl;
    if (b.endsWith('/api')) b = b.substring(0, b.length - 4);
    if (b.startsWith('https://')) return 'wss://${b.substring(8)}/ws';
    if (b.startsWith('http://')) return 'ws://${b.substring(7)}/ws';
    return 'ws://$b/ws';
  }

  /// Open the connection. Safe to call multiple times; only the first starts it.
  /// Always clears the disposed latch so a login after a previous logout (which
  /// called [stop]) reconnects instead of staying permanently dead.
  Future<void> start() async {
    _disposed = false;
    if (_started) return;
    _started = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[realtime] no token yet — retrying in 3s');
        _scheduleReconnect();
        return;
      }
      final uri = Uri.parse('${_wsBase()}?token=$token');
      debugPrint('[realtime] connecting to $uri');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      // ready surfaces the handshake result (incl. a 401) so failures are
      // logged instead of vanishing; the stream listener drives reconnects.
      channel.ready.then((_) {
        debugPrint('[realtime] connected');
      }).catchError((e) {
        debugPrint('[realtime] handshake failed: $e');
      });
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (e) {
          debugPrint('[realtime] socket error: $e');
          _onClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[realtime] connect threw: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      // Server sends text frames, but be defensive: some platforms deliver
      // binary as List<int>. Normalise to a String before decoding.
      final text = data is String ? data : utf8.decode(data as List<int>);
      final msg = jsonDecode(text);
      final type = msg is Map ? msg['type'] as String? : null;
      if (type != null && !_controller.isClosed) {
        _controller.add(type);
      }
    } catch (_) {
      // Ignore malformed frames.
    }
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // Fixed 3s backoff — simple and good enough for a LAN POS app.
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }

  /// Close the connection (call on logout).
  Future<void> stop() async {
    _disposed = true;
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
  }

  @visibleForTesting
  void debugEmit(String type) => _controller.add(type);
}
