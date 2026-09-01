import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/api.dart';

/// With the /health poll gone, this gate is the ONLY thing that reopens the
/// circuit when there is no WebSocket (before login, or behind a proxy that
/// blocks WebSockets). If it can wedge shut, the app is stuck offline forever
/// with a working internet connection — the exact bug this replaced.
void main() {
  final now = DateTime(2026, 1, 1, 12, 0, 0);

  test('the first request after going offline always probes', () {
    expect(shouldProbeWhileOffline(now, null), isTrue);
  });

  test('a request right behind a probe is fast-failed', () {
    final justProbed = now.subtract(const Duration(milliseconds: 500));
    expect(shouldProbeWhileOffline(now, justProbed), isFalse);
  });

  test('a later request probes again', () {
    final stale = now.subtract(const Duration(seconds: 5));
    expect(shouldProbeWhileOffline(now, stale), isTrue);
  });

  test('the gate always reopens — no interval wedges it shut', () {
    var last = now;
    // However long the outage, a request 10s later must get through.
    for (var minute = 0; minute < 60; minute++) {
      final t = now.add(Duration(minutes: minute, seconds: 10));
      expect(shouldProbeWhileOffline(t, last), isTrue,
          reason: 'blocked at minute $minute');
      last = t;
    }
  });
}
