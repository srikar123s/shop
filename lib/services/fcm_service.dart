import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/firebase_options.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/shop_sync_service.dart';

/// Top-level background message handler for FCM.
/// Runs in an isolated background engine when the app is closed or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
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
  try {
    final prefs = await SharedPreferences.getInstance();
    final myDeviceId = prefs.getString('shop_sync_device_id');
    final senderId = message.data['sender_device_id']?.toString();
    if (myDeviceId != null && senderId != null && senderId == myDeviceId) {
      debugPrint('[FCMService] Skipping self-originated background FCM message.');
      return;
    }
  } catch (_) {}

  // Ensure notification channel and plugin exist in this isolate, and render
  // high-priority heads-up banner whenever message is data-only (no notification block).
  if (message.notification == null) {
    final title = message.data['title']?.toString();
    final body = message.data['body']?.toString();
    if (title != null && title.isNotEmpty) {
      await FCMService.showBackgroundDataNotification(
        id: message.messageId?.hashCode ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
        title: title,
        body: body ?? '',
        payload: message.data['screen']?.toString() ?? 'home',
      );
    }
  }
}

class FCMService {
  FCMService._();
  static final FCMService instance = FCMService._();

  FirebaseMessaging? _fcm;
  final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _localNotifsReady = false;
  String? _currentSubscribedTopic;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;
  String? get currentSubscribedTopic => _currentSubscribedTopic;

  static const String _channelId = 'shop_alerts_high_priority_v1';
  static const String _legacyChannelId = 'shop_order_reminders';
  static const String _channelName = 'Shop Urgent Alerts & Reminders';
  static const String _channelDesc =
      'Important business reminders, order updates, and counter notifications';

  static Future<void> _ensureLocalPluginChannels(
    FlutterLocalNotificationsPlugin plugin, {
    void Function(NotificationResponse)? onTap,
  }) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onTap,
    );

    final androidImpl = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _legacyChannelId,
          'Shop Order & Cloud Reminders',
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
  }

  /// Displays a heads-up local notification from the headless FCM background isolate.
  static Future<void> showBackgroundDataNotification({
    required int id,
    required String title,
    required String body,
    String payload = 'home',
  }) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await _ensureLocalPluginChannels(plugin);
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
      await plugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[FCMService] Background local notification error: $e');
    }
  }

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

      await _ensureLocalPluginChannels(
        _localNotifs,
        onTap: (response) {
          AppNotificationService.instance.handlePayload(response.payload);
        },
      );
      _localNotifsReady = true;

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

      // 3. Configure foreground presentation options
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
        debugPrint('[FCMService] Foreground message received: ${message.notification?.title ?? message.data['title']}');
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationPayload(initialMessage.data);
        });
      }
    } catch (e, stack) {
      debugPrint('[FCMService] Init error: $e\n$stack');
    }
  }

  /// Displays high-priority heads-up local notification when message arrives in foreground
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final senderId = message.data['sender_device_id']?.toString();
    if (senderId != null && senderId == ShopSyncService.instance.deviceId) {
      return;
    }

    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString() ?? '';
    if (title == null || title.isEmpty) return;

    if (!_localNotifsReady) {
      await _ensureLocalPluginChannels(_localNotifs);
      _localNotifsReady = true;
    }

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

    final notifId = message.messageId?.hashCode ?? message.hashCode;
    await _localNotifs.show(
      notifId,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: message.data['screen']?.toString() ?? 'home',
    );
  }

  /// Handles deep-linking or navigation when a notification is tapped
  void _handleNotificationPayload(Map<String, dynamic> data) {
    final screen = data['screen']?.toString();
    debugPrint('[FCMService] Routing payload to screen: $screen');
    if (screen == null || screen.isEmpty) return;
    if (screen == 'report' || screen == 'daily_report') {
      AppNotificationService.instance.handlePayload('daily_report');
    } else if (screen == 'pending' || screen == 'pending_orders' || screen == 'orders') {
      AppNotificationService.instance.handlePayload('pending_orders');
    } else if (screen == 'procurement') {
      AppNotificationService.instance.handlePayload('procurement');
    } else if (screen == 'stale_prices') {
      AppNotificationService.instance.handlePayload('stale_prices');
    }
  }

  /// Sanitizes shop code into a valid FCM topic string: `[a-zA-Z0-9-_.~%]+`
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

  /// Dispatches an outbound notification to Firestore for the Cloud Function to push to all devices.
  Future<({bool ok, String? docId, String? error})> broadcastCloudAlert({
    required String shopCode,
    required String title,
    required String body,
    String? senderDeviceId,
    Map<String, dynamic>? data,
  }) async {
    if (shopCode.trim().isEmpty) {
      return (ok: false, docId: null, error: 'Shop code is empty');
    }
    if (Firebase.apps.isEmpty) {
      return (ok: false, docId: null, error: 'Firebase not initialized');
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final docRef = await firestore
          .collection('shops')
          .doc(shopCode)
          .collection('outbound_notifications')
          .add({
        'title': title,
        'body': body,
        'data': data ?? <String, dynamic>{},
        'target_topic': 'shop_${sanitizeTopic(shopCode)}_alerts',
        'created_at': FieldValue.serverTimestamp(),
        'sender_device_token': _fcmToken,
        'sender_device_id': senderDeviceId,
      });
      debugPrint('[FCMService] Broadcast alert queued in Firestore (${docRef.id}) for topic: shop_${sanitizeTopic(shopCode)}_alerts');
      return (ok: true, docId: docRef.id, error: null);
    } catch (e) {
      debugPrint('[FCMService] Failed to broadcast cloud alert: $e');
      return (ok: false, docId: null, error: e.toString());
    }
  }

  /// Waits briefly to verify if a deployed Cloud Function dispatched the outbound alert to FCM.
  Future<({bool dispatched, String? error})> waitForBroadcastDispatch({
    required String shopCode,
    required String docId,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (Firebase.apps.isEmpty || shopCode.isEmpty || docId.isEmpty) {
      return (dispatched: false, error: 'Unavailable');
    }
    try {
      final docRef = FirebaseFirestore.instance
          .collection('shops')
          .doc(shopCode)
          .collection('outbound_notifications')
          .doc(docId);

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final snap = await docRef.get();
        final data = snap.data();
        if (data != null) {
          if (data['dispatched'] == true) {
            return (dispatched: true, error: null);
          }
          if (data['error'] != null) {
            return (dispatched: false, error: data['error'].toString());
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return (dispatched: false, error: null);
    } catch (e) {
      return (dispatched: false, error: e.toString());
    }
  }
}
