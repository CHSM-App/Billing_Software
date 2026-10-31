import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

import '../api.dart';

/// Android channel for the ONE visible notification this app sends. Must match
/// `android.notification.channelId` in backend/src/fcm.js — a message naming a
/// channel that does not exist falls back to a silent default on Android 8+.
const String kOnlineOrderChannelId = 'online_orders';

/// Quiet channel for the owner's low-stock alert — same rule, must match
/// fcm.js sendLowStockNotification.
const String kLowStockChannelId = 'low_stock';

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

  /// Ticks when a QR table-order push arrives. The shell listens and refreshes
  /// the tables + open-drafts views.
  ///
  /// The WebSocket already broadcasts the same change, but only reaches a
  /// device whose app is open — the OS suspends the socket on backgrounding, so
  /// an order placed at a table while the counter phone was locked used to
  /// surface only when somebody next opened the app. This push is the path that
  /// works when the socket cannot.
  final ValueNotifier<int> tableOrderPing = ValueNotifier<int>(0);

  /// Ticks when the owner TAPS the low-stock notification. The shell listens
  /// and jumps to Items, where low-stock items sort to the top.
  final ValueNotifier<int> lowStockTap = ValueNotifier<int>(0);

  /// Ticks when a QR table-order notification is TAPPED. The shell listens and
  /// jumps to Orders, where that table's running order is.
  final ValueNotifier<int> tableOrderTap = ValueNotifier<int>(0);

  /// init() runs on every login as well as at startup; the stream listeners
  /// must be added once, or each re-login doubled every banner and chime.
  bool _listening = false;

  /// The type ('online_order' / 'table_order' / 'low_stock') of a tap that arrived before
  /// anything was listening. A COLD launch from the notification lands here:
  /// the tap is handled during init(), long before the shell exists to hear the
  /// notifier, so the shell claims it on mount instead.
  String? _pendingTap;

  /// Take the pending tap if it is of [type]. Consuming it means a later
  /// re-login in the same process cannot re-trigger a stale jump.
  bool consumeTap(String type) {
    if (_pendingTap != type) return false;
    _pendingTap = null;
    return true;
  }

  void _tapped(String? type) {
    if (type == 'online_order') {
      _pendingTap = type;
      onlineOrderTap.value++;
    } else if (type == 'table_order') {
      _pendingTap = type;
      tableOrderTap.value++;
    } else if (type == 'low_stock') {
      _pendingTap = type;
      lowStockTap.value++;
    }
  }

  /// Signal the Kitchen screen to refresh from within the app — call this the
  /// moment an order (draft) is created or updated locally, so the kitchen queue
  /// updates instantly without depending on an FCM round-trip (which can be
  /// missed, throttled in foreground, or absent in dev).
  void pingKitchen() => kitchenPing.value++;

  /// Call once from main() after Firebase.initializeApp()
  ///
  /// Visible notifications are shown for two things: a new online/table order
  /// (loud — an unnoticed order is a lost sale) and the owner's low-stock alert
  /// (quiet, one replacing slot). Kitchen refreshes stay a silent data channel
  /// that only bumps a notifier — the chef is already watching that screen.
  /// Each person can switch the visible ones off in Settings (server-side).
  Future<void> init() async {
    if (!_listening) {
      _listening = true;
      await _listen();
    }

    // Upload token to backend and listen for token refresh, so the server can
    // still push to this device. Every call: a re-login is a new user.
    await _uploadToken();
  }

  Future<void> _listen() async {
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
        _showOnlineOrder(message, 'online_order');
      } else if (type == 'table_order') {
        tableOrderPing.value++;
        _showOnlineOrder(message, 'table_order');
      } else if (type == 'low_stock') {
        _showLowStock(message);
      }
    });

    // Tapped while the app was BACKGROUNDED — Android/iOS showed the banner
    // themselves from the message's notification block, and hand it back here.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _tapped(message.data['type']);
    });

    // Tapped while the app was NOT RUNNING: the tap is what launched us, so it
    // is waiting here rather than arriving on a stream.
    try {
      final initial = await _fcm.getInitialMessage();
      _tapped(initial?.data['type']);
    } catch (e) {
      debugPrint('getInitialMessage failed: $e');
    }

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
        onDidReceiveNotificationResponse: (response) =>
            _tapped(response.payload),
      );
      // App was killed and then launched by tapping a banner THIS app posted
      // (a foreground order) — that tap arrives here, not on any stream.
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _tapped(launch!.notificationResponse?.payload);
      }
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        kOnlineOrderChannelId,
        'Online orders',
        description: 'A customer placed an order on your store link',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        kLowStockChannelId,
        'Low stock',
        description: 'Items that dropped below their low-stock limit',
        playSound: false,
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

  Future<void> _showOnlineOrder(RemoteMessage message, String type) async {
    final n = message.notification;
    try {
      await _local.show(
        // A stable-ish id from the order number so the same order re-pushed
        // replaces its notification instead of stacking a duplicate. A table
        // order has no order number — it merges into the table's running
        // draft — so its table is what identifies it, and a second round from
        // the same table replaces the first rather than stacking.
        (message.data['order_number'] ?? message.data['table'] ?? '').hashCode,
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
        // Read back by onDidReceiveNotificationResponse above, so the tap
        // opens the right queue: a table order is not in the Online tab.
        payload: type,
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

  /// Foreground low-stock alert. Quiet, and posted as id 0 + tag 'low_stock' —
  /// the same key Android gives the FCM tray notification (tag set in fcm.js) —
  /// so every low-stock alert, foreground or not, replaces the last one.
  Future<void> _showLowStock(RemoteMessage message) async {
    final n = message.notification;
    try {
      await _local.show(
        0,
        n?.title ?? 'Low stock',
        n?.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kLowStockChannelId,
            'Low stock',
            tag: 'low_stock',
            playSound: false,
          ),
          iOS: DarwinNotificationDetails(presentSound: false),
        ),
        payload: 'low_stock',
      );
    } catch (e) {
      debugPrint('Low stock notification failed: $e');
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
