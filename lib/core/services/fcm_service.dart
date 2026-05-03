import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'api_service.dart';

/// Background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');

  // Do not show notifications when no user is logged in on this device.
  final prefs = await SharedPreferences.getInstance();
  final authToken = prefs.getString('auth_token');
  if (authToken == null) {
    debugPrint('[FCM] Background: no logged-in user — skipping notification.');
    return;
  }

  // If the message has no notification payload (data-only), the OS will NOT
  // display anything automatically. We must show a local notification here.
  if (message.notification == null) {
    final title = message.data['title'] as String?;
    final body = message.data['body'] as String?;
    if (title != null || body != null) {
      const channel = AndroidNotificationChannel(
        'mysimtek_high_importance',
        'MySimtek Notifications',
        description: 'Notifikasi penting dari MySimtek Teknisi',
        importance: Importance.high,
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
      );
      if (!kIsWeb && Platform.isAndroid) {
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
      }
      await plugin.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
          ),
        ),
      );
    }
  }
}

class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Cached ApiService used by token-refresh listener and syncToken.
  static ApiService? _apiService;

  /// Stream emitted when a foreground message arrives (for in-app refresh).
  static final _messageStreamController =
      StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get onForegroundMessage =>
      _messageStreamController.stream;

  /// Stream emitted when user taps a notification (background / terminated).
  static final _tapStreamController =
      StreamController<RemoteMessage>.broadcast();
  static Stream<RemoteMessage> get onNotificationTap =>
      _tapStreamController.stream;

  static const _androidChannel = AndroidNotificationChannel(
    'mysimtek_high_importance',
    'MySimtek Notifications',
    description: 'Notifikasi penting dari MySimtek Teknisi',
    importance: Importance.high,
  );

  /// Call once at app startup (before login) to set up listeners and channels.
  static Future<void> initialize(ApiService apiService) async {
    _apiService = apiService;

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Setup local notifications channel (Android)
    await _initLocalNotifications();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((token) {
      if (_apiService != null) {
        _sendTokenToServer(_apiService!, token);
      }
    });

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground: ${message.notification?.title}');
      _showLocalNotification(message);
      _messageStreamController.add(message);
    });

    // Notification tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] Opened from background: ${message.data}');
      _tapStreamController.add(message);
    });

    // Check if app was opened from a terminated state via notification
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM] Opened from terminated: ${initial.data}');
      Future.delayed(const Duration(milliseconds: 500), () {
        _tapStreamController.add(initial);
      });
    }
  }

  /// Call this after the user successfully logs in to sync the FCM token.
  static Future<void> syncToken() async {
    final api = _apiService;
    if (api == null) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[FCM] Syncing token after login: $token');
        await _sendTokenToServer(api, token);
      }
    } catch (e) {
      debugPrint('[FCM] syncToken error: $e');
    }
  }

  /// Call this on user logout to invalidate the device's FCM token.
  static Future<void> clearToken() async {
    try {
      await _messaging.deleteToken();
      debugPrint('[FCM] Token deleted on logout.');
    } catch (e) {
      debugPrint('[FCM] Failed to delete token: $e');
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    // Create high-importance channel on Android
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_androidChannel);
    }
  }

  static Future<void> _sendTokenToServer(
    ApiService apiService,
    String token,
  ) async {
    try {
      await apiService.post(ApiConstants.fcmTokenUpdate, {'fcm_token': token});
      debugPrint('[FCM] Token synced to server.');
    } catch (e) {
      debugPrint('[FCM] Failed to sync token: $e');
    }
  }

  static void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;

    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;

    if (title == null && body == null) return;

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
      ),
    );
  }
}
