import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/app_keys.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/history_screen.dart';
import 'package:shop/screens/procurement_screen.dart';
import 'package:shop/services/backup_service.dart';

enum NotificationScheduleMode {
  threeTimesDaily, // 8 AM, 2 PM, 8:30 PM (Recommended)
  hourly, // Every 1 hour from 7 AM - 9 PM
}

class AppNotificationService {
  AppNotificationService._();
  static final AppNotificationService instance = AppNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Timer? _periodicTimer;
  bool _initialized = false;

  static const String _channelId = 'shop_order_reminders';
  static const String _channelName = 'Shop Order & Procurement Reminders';
  static const String _channelDesc =
      'Reminders for unclosed bills and items needing procurement';

  static const String _prefEnabledKey = 'hourly_reminders_enabled';
  static const String _prefModeKey = 'reminder_schedule_mode';
  static const String _prefLastNotifiedKey = 'last_notified_slot_key';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    // Create Notification Channel for Android 8.0+
    final androidNotificationDetails =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidNotificationDetails != null) {
      await androidNotificationDetails.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      // Request notification permissions for Android 13+
      await androidNotificationDetails.requestNotificationsPermission();
    }

    // Periodic check every 15 minutes to accurately catch scheduled milestones
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      checkAndNotify();
    });

    // Run check on startup
    unawaited(checkAndNotify());
  }

  void _handlePayload(String? payload) {
    if (payload == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final db = DatabaseHelper.instance;
    final orderRepo = OrderRepository(db);
    final custRepo = CustomerRepository(db);
    final prodRepo = ProductRepository(db);
    final backupSvc = BackupService(db);

    if (payload == 'pending_orders') {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryScreen(
            orderRepository: orderRepo,
            backupService: backupSvc,
            customerRepository: custRepo,
            productRepository: prodRepo,
            initialFilter: HistoryFilter.pending,
          ),
        ),
      );
    } else if (payload == 'procurement') {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ProcurementScreen(
            orderRepository: orderRepo,
            customerRepository: custRepo,
            productRepository: prodRepo,
          ),
        ),
      );
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
    if (enabled) {
      checkAndNotify(force: true);
    } else {
      await _notificationsPlugin.cancelAll();
    }
  }

  Future<NotificationScheduleMode> getScheduleMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_prefModeKey) ?? 'threeTimesDaily';
    return modeStr == 'hourly'
        ? NotificationScheduleMode.hourly
        : NotificationScheduleMode.threeTimesDaily;
  }

  Future<void> setScheduleMode(NotificationScheduleMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefModeKey, mode.name);
  }

  /// Checks order & procurement status and posts notifications according to schedule.
  Future<void> checkAndNotify({bool force = false}) async {
    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      final mode = await getScheduleMode();

      String? currentSlot;

      if (!force) {
        if (mode == NotificationScheduleMode.threeTimesDaily) {
          // 3 Smart Daily Milestones:
          // Slot 1: Morning 08:00 - 08:59 (Godown & Procurement Digest)
          // Slot 2: Midday  14:00 - 14:59 (Fulfillment Check)
          // Slot 3: Evening 20:30 - 21:59 (Day-End Closing Siren)
          if (now.hour == 8) {
            currentSlot = '${now.year}-${now.month}-${now.day}-morning';
          } else if (now.hour == 14) {
            currentSlot = '${now.year}-${now.month}-${now.day}-midday';
          } else if (now.hour == 20 || (now.hour == 21 && now.minute <= 30)) {
            currentSlot = '${now.year}-${now.month}-${now.day}-evening';
          } else {
            // Not a milestone hour, check only if there are critical overdue (>3 days) orders
            final orderRepo = OrderRepository(DatabaseHelper.instance);
            final stats = await orderRepo.getPendingAndProcurementStats();
            if (stats.oldPendingCount > 0) {
              final overdueSlot = '${now.year}-${now.month}-${now.day}-overdue-${now.hour}';
              final prefs = await SharedPreferences.getInstance();
              if (prefs.getString(_prefLastNotifiedKey) != overdueSlot) {
                await _showOverdueNotification(stats.oldPendingCount, stats.pendingCount);
                await prefs.setString(_prefLastNotifiedKey, overdueSlot);
              }
            }
            return;
          }
        } else {
          // Hourly mode: between 7:00 AM and 9:59 PM
          if (now.hour < 7 || now.hour > 21) return;
          currentSlot = '${now.year}-${now.month}-${now.day}-${now.hour}';
        }

        final prefs = await SharedPreferences.getInstance();
        final lastSlot = prefs.getString(_prefLastNotifiedKey);
        if (lastSlot == currentSlot) {
          return; // Already notified in this slot
        }
      }

      final orderRepo = OrderRepository(DatabaseHelper.instance);
      final stats = await orderRepo.getPendingAndProcurementStats();

      // If everything is closed and nothing to procure, skip
      if (stats.pendingCount == 0 && stats.toProcureCount == 0) return;

      // Milestone specific titles & messages
      String pendingTitle;
      String pendingBody;

      if (stats.oldPendingCount > 0) {
        pendingTitle = '⚠️ ${stats.oldPendingCount} Urgent Overdue Order(s)!';
        pendingBody =
            '${stats.pendingCount} total orders open. ${stats.oldPendingCount} order(s) taken >3 days ago are still unclosed! Tap to review.';
      } else if (now.hour <= 10) {
        pendingTitle = '🌅 Morning Status: ${stats.pendingCount} Open Orders';
        pendingBody = stats.toProcureCount > 0
            ? '${stats.toProcureCount} item(s) needed from godown/supplier. ${stats.pendingCount} customer orders pending.'
            : 'You have ${stats.pendingCount} active customer order(s) to fulfill today.';
      } else if (now.hour >= 20) {
        pendingTitle = '🌙 Day-End Closing: ${stats.pendingCount} Unclosed Bills';
        pendingBody =
            'Shop closing time! Close all open bills to update today\'s sales and customer khata balances.';
      } else {
        pendingTitle = '📋 Midday Check: ${stats.pendingCount} Pending Orders';
        pendingBody =
            '${stats.pendingCount} customer order(s) have not been closed yet. Tap to view and close.';
      }

      // 1. Pending orders notification
      if (stats.pendingCount > 0) {
        const androidDetails = AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF0F766E),
          styleInformation: BigTextStyleInformation(''),
        );
        const details = NotificationDetails(android: androidDetails);

        await _notificationsPlugin.show(
          101,
          pendingTitle,
          pendingBody,
          details,
          payload: 'pending_orders',
        );
      }

      // 2. Procurement items notification
      if (stats.toProcureCount > 0) {
        const androidDetails = AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFE11D48),
          styleInformation: BigTextStyleInformation(''),
        );
        const details = NotificationDetails(android: androidDetails);

        await _notificationsPlugin.show(
          102,
          '📦 Procurement: ${stats.toProcureCount} Item(s) Needed',
          'Items are short or not given to customers. Tap here to view the full procurement list.',
          details,
          payload: 'procurement',
        );
      }

      // Record slot
      if (currentSlot != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastNotifiedKey, currentSlot);
      }
    } catch (e) {
      debugPrint('[AppNotificationService] Error checking notifications: $e');
    }
  }

  Future<void> _showOverdueNotification(int oldOrdersCount, int totalPending) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFFDC2626),
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      103,
      '⚠️ URGENT: $oldOrdersCount Order(s) >3 Days Old!',
      '$totalPending total orders pending. $oldOrdersCount order(s) taken over 3 days ago are still not closed! Tap to review.',
      details,
      payload: 'pending_orders',
    );
  }

  void dispose() {
    _periodicTimer?.cancel();
  }
}
