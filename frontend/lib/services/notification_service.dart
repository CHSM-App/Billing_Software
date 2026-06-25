import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api.dart';

// Top-level handler required by FCM for background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No Firebase.initializeApp needed here — it was already called in main()
  await NotificationService.instance.showLocalNotification(message);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'low_stock';
  static const _channelName = 'Low Stock Alerts';

  /// Call once from main() after Firebase.initializeApp()
  Future<void> init() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Alerts when item stock falls below threshold',
      importance: Importance.high,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    // Initialise local notifications plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);

    // Request permission (iOS + Android 13+)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      showLocalNotification(message);
    });

    // Upload token to backend and listen for token refresh
    await _uploadToken();
    _fcm.onTokenRefresh.listen((_) => _uploadToken());
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when item stock falls below threshold',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
    );
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
