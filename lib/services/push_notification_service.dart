import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import 'auth_service.dart';

/// Background handler must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background: ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'homeguardian_alerts',
    'HomeGuardian alerts',
    description: 'Security and event notifications',
    importance: Importance.high,
  );

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (!kIsWeb) {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (Platform.isAndroid) {
        await Permission.notification.request();
      }
    }

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerTokenSafe);

    _initialized = true;
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? message.data['title'] ?? 'HomeGuardian';
    final body = n?.body ?? message.data['body'] ?? '';

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['event_id'],
    );
  }

  static Future<void> syncTokenWithBackendIfLoggedIn() async {
    if (kIsWeb) {
      return;
    }
    try {
      final auth = AuthService();
      if (await auth.getToken() == null) {
        return;
      }
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) {
        await _registerTokenSafe(t);
      }
    } catch (e) {
      debugPrint('PushNotificationService: sync token failed: $e');
    }
  }

  static Future<void> _registerTokenSafe(String token) async {
    try {
      final auth = AuthService();
      if (await auth.getToken() == null) {
        return;
      }
      final platform = Platform.isIOS ? 'ios' : 'android';
      await auth.registerFcmToken(token, platform: platform);
    } catch (e) {
      debugPrint('PushNotificationService: register token failed: $e');
    }
  }
}
