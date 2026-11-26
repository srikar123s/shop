import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shop/firebase_options.dart';

/// Top-level background message handler for FCM.
/// This runs in an isolated background engine when the app is closed/terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {}
  }
  debugPrint('[FCMService] Background message received: ${message.messageId}');
  debugPrint('[FCMService] Title: ${message.notification?.title}, Body: ${message.notification?.body}');
}

class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  FirebaseMessaging? _fcm;
  final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentSubscribedTopic;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;
  String? get currentSubscribedTopic => _currentSubscribedTopic;

  static const String _channelId = 'shop_alerts_high_priority_v1';
  static const String _channelName = 'Shop Urgent Alerts & Reminders';
  static const String _channelDesc = 'Important business reminders, order updates, and counter notifications';

  /// Initializes FCM listeners, permissions, and background message handling
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Ensure Firebase is initialized
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } catch (_) {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp();
          }
        }
      }

      if (Firebase.apps.isEmpty) {
        debugPrint('[FCMService] Firebase apps empty, skipping FCM initialization.');
        return;
      }

      _fcm = FirebaseMessaging.instance;
      _initialized = true;

      // 1. Register top-level background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Request user notification permissions
      final settings = await _fcm!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('[FCMService] User permission status: ${settings.authorizationStatus}');

      // 3. Configure foreground presentation options (for when app is open)
      await _fcm!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Retrieve and log FCM device token
      try {
        _fcmToken = await _fcm!.getToken();
        debugPrint('[FCMService] FCM Token: $_fcmToken');
      } catch (e) {
        debugPrint('[FCMService] Failed to get FCM token: $e');
      }

      // Listen for token refreshes
      _fcm!.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('[FCMService] FCM Token refreshed: $newToken');
      });

      // 5. Handle foreground push messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCMService] Foreground message received: ${message.notification?.title}');
        _showForegroundNotification(message);
      });

      // 6. Handle notification click when app opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCMService] App opened from notification: ${message.data}');
        _handleNotificationPayload(message.data);
      });

      // 7. Check for initial message (cold-start from killed state)
      final initialMessage = await _fcm!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCMService] Initial message from cold-start: ${initialMessage.data}');
        _handleNotificationPayload(initialMessage.data);
      }
    } catch (e, stack) {
      debugPrint('[FCMService] Init error: $e\n$stack');
    }
  }

  /// Displays high-priority heads-up local notification when message arrives in foreground
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF0F766E),
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(''),
    );

    final notifId = message.hashCode;
    await _localNotifs.show(
      notifId,
      notification.title ?? 'Shop Alert',
      notification.body ?? '',
      const NotificationDetails(android: androidDetails),
      payload: message.data['screen'] ?? 'home',
    );
  }

  /// Handles deep-linking or navigation when a notification is tapped
  void _handleNotificationPayload(Map<String, dynamic> data) {
    final screen = data['screen'];
    debugPrint('[FCMService] Routing payload to screen: $screen');
    // Navigation can be handled via rootNavigatorKey if desired
  }

  /// Sanitizes shop code into a valid FCM topic string: [a-zA-Z0-9-_.~%]+
  static String sanitizeTopic(String shopCode) {
    return shopCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
  }

  /// Subscribes this device to the shop's multi-device broadcast channel
  Future<void> subscribeToShopTopic(String shopCode) async {
    if (shopCode.trim().isEmpty) return;
    final topic = 'shop_${sanitizeTopic(shopCode)}_alerts';
    if (_currentSubscribedTopic == topic) return;

    try {
      final fcm = _fcm ?? (Firebase.apps.isNotEmpty ? FirebaseMessaging.instance : null);
      if (fcm == null) return;
      if (_currentSubscribedTopic != null) {
        await fcm.unsubscribeFromTopic(_currentSubscribedTopic!);
      }
      await fcm.subscribeToTopic(topic);
      _currentSubscribedTopic = topic;
      debugPrint('[FCMService] Successfully subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[FCMService] Error subscribing to topic $topic: $e');
    }
  }

  /// Unsubscribes this device from the shop's multi-device broadcast channel
  Future<void> unsubscribeFromShopTopic(String shopCode) async {
    if (shopCode.trim().isEmpty) return;
    final topic = 'shop_${sanitizeTopic(shopCode)}_alerts';
    try {
      final fcm = _fcm ?? (Firebase.apps.isNotEmpty ? FirebaseMessaging.instance : null);
      if (fcm == null) return;
      await fcm.unsubscribeFromTopic(topic);
      if (_currentSubscribedTopic == topic) {
        _currentSubscribedTopic = null;
      }
      debugPrint('[FCMService] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[FCMService] Error unsubscribing from topic $topic: $e');
    }
  }

  /// Dispatches an outbound notification to Firestore for the Cloud Function to push to all devices
  Future<void> broadcastCloudAlert({
    required String shopCode,
    required String title,
    required String body,
    String? senderDeviceId,
    Map<String, dynamic>? data,
  }) async {
    if (shopCode.trim().isEmpty) return;
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('shops').doc(shopCode).collection('outbound_notifications').add({
        'title': title,
        'body': body,
        'data': data ?? {},
        'target_topic': 'shop_${sanitizeTopic(shopCode)}_alerts',
        'created_at': FieldValue.serverTimestamp(),
        'sender_device_token': _fcmToken,
        'sender_device_id': senderDeviceId,
      });
      debugPrint('[FCMService] Broadcast alert queued in Firestore for topic: shop_${sanitizeTopic(shopCode)}_alerts');
    } catch (e) {
      debugPrint('[FCMService] Failed to broadcast cloud alert: $e');
    }
  }
}
