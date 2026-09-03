import 'package:Vittam/providers/connectivity_provider.dart';
import 'package:Vittam/services/realtime_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real notifier through the socket + lifecycle sequences that
/// produced the "Back online" flash on every app resume.
///
/// The notifier listens to RealtimeService.instance.connection, so these tests
/// push through the real singleton's stream via its public start/stop-free
/// surface: _setConnected is private, so we exercise the paths we CAN reach —
/// the lifecycle gate and the banner rules — which is where the bug lived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // RealtimeService is a singleton, so its connection state leaks between
  // tests. Reset before each one — this runs before any container exists, so
  // nothing is listening and the reset itself is not observed.
  setUp(() => RealtimeService.instance.debugSetConnected(false));

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Force the notifier to build so it subscribes and installs its listener.
    c.read(connectivityProvider);
    return c;
  }

  // AppLifecycleListener asserts that transitions are legal, so these walk the
  // real OS sequence rather than jumping straight to paused/resumed.
  void sendLifecycle(AppLifecycleState state) {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
  }

  /// Let the broadcast stream deliver — connection events reach the notifier on
  /// a microtask, so an assertion made immediately after would race it.
  Future<void> pump() => Future<void>.delayed(Duration.zero);

  void background() {
    sendLifecycle(AppLifecycleState.inactive);
    sendLifecycle(AppLifecycleState.hidden);
    sendLifecycle(AppLifecycleState.paused);
  }

  void foreground() {
    sendLifecycle(AppLifecycleState.hidden);
    sendLifecycle(AppLifecycleState.inactive);
    sendLifecycle(AppLifecycleState.resumed);
  }

  group('banner rules', () {
    test('showBackOnline does nothing unless the offline bar was showing', () {
      final c = makeContainer();
      final banner = c.read(connectivityBannerProvider.notifier);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.online);

      // This is the guard that stops a plain successful request from flashing.
      banner.showBackOnline();
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.online);
    });

    test('offline → backOnline flashes, and only then', () {
      final c = makeContainer();
      final banner = c.read(connectivityBannerProvider.notifier);
      banner.showOffline();
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.offline);
      banner.showBackOnline();
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.backOnline);
    });
  });

  group('markOffline / markOnline', () {
    test('markOnline after markOffline flashes Back online', () {
      final c = makeContainer();
      final conn = c.read(connectivityProvider.notifier);

      conn.markOffline();
      expect(c.read(connectivityProvider), isFalse);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.offline);

      conn.markOnline();
      expect(c.read(connectivityProvider), isTrue);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.backOnline);
    });

    test('markOnline while already online never flashes', () {
      // The resume path: app was never actually offline, so coming back must
      // stay silent no matter how many requests succeed.
      final c = makeContainer();
      final conn = c.read(connectivityProvider.notifier);
      expect(c.read(connectivityProvider), isTrue);

      conn.markOnline();
      conn.markOnline();
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.online);
    });
  });

  group('lifecycle gate — the resume-flash regression', () {
    test('a background round trip leaves the app online and quiet', () async {
      // THE reported bug: background the app, come back, and it flashed a green
      // "Back online" every time — because the OS suspending the socket was
      // read as the shop losing internet.
      //
      // Driving the socket explicitly is what makes this test real. Without
      // debugSetConnected nothing ever emits in a test, so the drop below never
      // happened and this passed no matter what the code did.
      final rt = RealtimeService.instance;
      final c = makeContainer();
      rt.debugSetConnected(true);
      await pump();
      expect(c.read(connectivityProvider), isTrue);

      background();
      // The OS suspends the socket shortly after backgrounding.
      rt.debugSetConnected(false);
      await pump();
      // Well past the 5s grace window, nothing may mark us offline.
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(c.read(connectivityProvider), isTrue,
          reason: 'a backgrounded socket drop is not an outage');

      // Coming back: the socket reconnects as the app resumes.
      foreground();
      rt.debugSetConnected(true);
      await pump();

      expect(c.read(connectivityProvider), isTrue);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.online,
          reason: 'never went offline, so there is nothing to flash back from');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a socket drop while IN the foreground still reports offline',
        () async {
      // The gate must not swallow real outages: same drop, app in front.
      final rt = RealtimeService.instance;
      final c = makeContainer();
      rt.debugSetConnected(true);
      await pump();

      rt.debugSetConnected(false);
      await pump();
      expect(c.read(connectivityProvider), isTrue, reason: 'grace not elapsed');

      await Future<void>.delayed(const Duration(seconds: 6));
      expect(c.read(connectivityProvider), isFalse);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.offline);

      // And recovering from a REAL outage should still flash.
      rt.debugSetConnected(true);
      await pump();
      expect(c.read(connectivityProvider), isTrue);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.backOnline);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('resuming with a genuinely dead socket still reports offline', () async {
      final c = makeContainer();
      final conn = c.read(connectivityProvider.notifier);
      // RealtimeService was never started in tests, so isConnected is false —
      // exactly the "no socket on resume" case.
      expect(RealtimeService.instance.isConnected, isFalse);

      background();
      foreground();
      expect(c.read(connectivityProvider), isTrue, reason: 'grace not elapsed');

      // The grace timer is armed on resume; a real outage surfaces once it ends.
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(c.read(connectivityProvider), isFalse);
      expect(c.read(connectivityBannerProvider), ConnectivityBanner.offline);
      conn.markOnline(); // tidy
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
