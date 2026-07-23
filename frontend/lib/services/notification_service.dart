import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../api.dart';

// Top-level handler required by FCM for background messages. We show NOTHING —
// a backgrounded kitchen_order is simply ignored here; the Kitchen screen
// reconciles from the server when it next resumes.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally a no-op: no visible notifications for any role.
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;

  /// Ticks whenever a kitchen-order push arrives. The Kitchen screen listens and
  /// refreshes its order list. Polling remains the fallback if push is missed.
  final ValueNotifier<int> kitchenPing = ValueNotifier<int>(0);

  /// Signal the Kitchen screen to refresh from within the app — call this the
  /// moment an order (draft) is created or updated locally, so the kitchen queue
  /// updates instantly without depending on an FCM round-trip (which can be
  /// missed, throttled in foreground, or absent in dev).
  void pingKitchen() => kitchenPing.value++;

  /// Call once from main() after Firebase.initializeApp()
  ///
  /// We intentionally show NO visible notifications to any role. FCM is still
  /// used, but only as a silent, real-time data channel: an incoming
  /// `kitchen_order` data message bumps [kitchenPing] so the Kitchen screen
  /// refreshes live. No banners, sounds, badges, or permission prompts.
  Future<void> init() async {
    // Background handler still runs so a kitchen_order arriving while the app is
    // backgrounded is handled silently (no notification is shown — see below).
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Listen for foreground messages — refresh the kitchen queue, show nothing.
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'kitchen_order') {
        kitchenPing.value++;
      }
    });

    // Upload token to backend and listen for token refresh, so the server can
    // still push the silent kitchen_order data message to this device.
    await _uploadToken();
    _fcm.onTokenRefresh.listen((_) => _uploadToken());
  }

  Future<void> _uploadToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await registerFcmToken(token);
      }
    } catch (_) {
      // Non-critical — notifications just won't work on this device
    }
  }

  /// Call on logout to remove this device's token from the backend
  Future<void> removeToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await deleteFcmToken(token);
      }
    } catch (_) {}
  }
}
