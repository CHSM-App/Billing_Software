import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

import '../api.dart';

/// Android channel for the ONE visible notification this app sends. Must match
/// `android.notification.channelId` in backend/src/fcm.js — a message naming a
/// channel that does not exist falls back to a silent default on Android 8+.
const String kOnlineOrderChannelId = 'online_orders';

// Top-level handler required by FCM for background messages.
//
// Deliberately a no-op even for an online order: that message carries a real
// `notification` block, so Android itself posts it to the tray while the app is
// backgrounded. Doing anything here would double up.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  final _chime = AudioPlayer();

  /// Ticks whenever a kitchen-order push arrives. The Kitchen screen listens and
  /// refreshes its order list. Polling remains the fallback if push is missed.
  final ValueNotifier<int> kitchenPing = ValueNotifier<int>(0);

  /// Ticks when an online-store order push arrives. The shell listens and
  /// refreshes the queue — a second path to the same refresh the WebSocket
  /// normally drives, for when the socket is down.
  final ValueNotifier<int> onlineOrderPing = ValueNotifier<int>(0);

  /// Ticks when the user TAPS an online-order notification. The shell listens
  /// and jumps to the Online orders queue.
  final ValueNotifier<int> onlineOrderTap = ValueNotifier<int>(0);

  /// A tap that arrived before anything was listening. A COLD launch from the
  /// notification lands here: the tap is handled during init(), long before the
  /// shell exists to hear the notifier, so the shell claims it on mount instead.
  bool _tapPending = false;

  /// Take the pending tap, if there is one. Consuming it means a later re-login
  /// in the same process cannot re-trigger a stale jump.
  bool consumeOnlineOrderTap() {
    final pending = _tapPending;
    _tapPending = false;
    return pending;
  }

  void _onlineOrderTapped() {
    _tapPending = true;
    onlineOrderTap.value++;
  }

  /// Signal the Kitchen screen to refresh from within the app — call this the
  /// moment an order (draft) is created or updated locally, so the kitchen queue
  /// updates instantly without depending on an FCM round-trip (which can be
  /// missed, throttled in foreground, or absent in dev).
  void pingKitchen() => kitchenPing.value++;

  /// Call once from main() after Firebase.initializeApp()
  ///
  /// Visible notifications are shown for exactly ONE thing: a new online-store
  /// order. Everything else (kitchen refreshes, low stock) stays a silent data
  /// channel that only bumps a notifier. The exception exists because an online
  /// order arrives with nobody looking at the app — an unnoticed order is a lost
  /// sale, which is not true of a kitchen ticket the chef is already watching.
  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _initLocalNotifications();

    // Foreground messages: FCM never displays these itself, so the online-order
    // one is posted locally here (with a chime); everything else stays silent.
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      if (type == 'kitchen_order') {
        kitchenPing.value++;
      } else if (type == 'online_order') {
        onlineOrderPing.value++;
        _showOnlineOrder(message);
      }
    });

    // Tapped while the app was BACKGROUNDED — Android/iOS showed the banner
    // themselves from the message's notification block, and hand it back here.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'online_order') _onlineOrderTapped();
    });

    // Tapped while the app was NOT RUNNING: the tap is what launched us, so it
    // is waiting here rather than arriving on a stream.
    try {
      final initial = await _fcm.getInitialMessage();
      if (initial?.data['type'] == 'online_order') _onlineOrderTapped();
    } catch (e) {
      debugPrint('getInitialMessage failed: $e');
    }

    // Upload token to backend and listen for token refresh, so the server can
    // still push to this device.
    await _uploadToken();
    _fcm.onTokenRefresh.listen((_) => _uploadToken());
  }

  Future<void> _initLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // Permission is requested explicitly when the store is switched on, not
        // at app start — a shop with no online store is never asked.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _local.initialize(
        settings,
        // Foreground taps: the banner this app posted itself.
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == 'online_order') _onlineOrderTapped();
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            kOnlineOrderChannelId,
            'Online orders',
            description: 'A customer placed an order on your store link',
            importance: Importance.high,
          ));
    } catch (e) {
      // A device that refuses to set up local notifications must not stop the
      // app from starting — the FCM tray notification still works.
      debugPrint('Local notifications init failed: $e');
    }
  }

  /// Ask for notification permission. Called when the owner switches the online
  /// store ON, which is the only moment the prompt has a reason the user can
  /// connect it to.
  Future<void> requestPermission() async {
    try {
      await _fcm.requestPermission();
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  Future<void> _showOnlineOrder(RemoteMessage message) async {
    final n = message.notification;
    try {
      await _local.show(
        // A stable-ish id from the order number so the same order re-pushed
        // replaces its notification instead of stacking a duplicate.
        (message.data['order_number'] ?? '').hashCode,
        n?.title ?? 'New online order',
        n?.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kOnlineOrderChannelId,
            'Online orders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Read back by onDidReceiveNotificationResponse above to know a tap
        // belongs to an order rather than some future notification type.
        payload: 'online_order',
      );
    } catch (e) {
      debugPrint('Online order notification failed: $e');
    }
    // Sound is a separate nicety — a failure here must not swallow the banner.
    try {
      await _chime.stop();
      await _chime.play(AssetSource('sounds/new_order.mp3'));
    } catch (e) {
      debugPrint('Online order chime failed: $e');
    }
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
