import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shop/app_keys.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/repositories/customer_repository.dart';
import 'package:shop/repositories/order_repository.dart';
import 'package:shop/repositories/product_repository.dart';
import 'package:shop/screens/history_screen.dart';
import 'package:shop/screens/procurement_screen.dart';
import 'package:shop/screens/simple_product_admin_screen.dart';
import 'package:shop/services/backup_service.dart';

enum NotificationScheduleMode {
  threeTimesDaily, // Legacy
  hourly, // Every 1 hour from 7 AM - 9 PM
  every2Hours, // Every 2 hours from 8 AM - 8 PM
  scheduled, // Custom user-defined times of day
}

class AppNotificationService {
  AppNotificationService._();
  static final AppNotificationService instance = AppNotificationService._();

  static const MethodChannel _nativeChannel =
      MethodChannel('com.example.shop/background_notifications');

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Timer? _periodicTimer;
  bool _initialized = false;
  bool _timezoneConfigured = false;
  bool _isRescheduling = false;
  bool _pendingReschedule = false;
  Completer<void>? _rescheduleCompleter;

  static const String _channelId = 'shop_alerts_high_priority_v1';
  static const String _legacyChannelId = 'shop_order_reminders';
  static const String _channelName = 'Shop Urgent Alerts & Reminders';
  static const String _channelDesc =
      'Important business reminders, order updates, and counter notifications';

  static const String _prefEnabledKey = 'hourly_reminders_enabled';
  static const String _prefLastNotifiedKey = 'last_notified_slot_key';

  // Category specific keys
  static const String _prefPendingEnabledKey = 'notif_pending_orders_enabled';
  static const String _prefPendingModeKey =
      'notif_pending_orders_mode'; // 'scheduled', 'hourly', 'two_hours'
  static const String _prefPendingTimesKey =
      'notif_pending_orders_times'; // string list ["10:00", "14:00", "19:00"]

  static const String _prefProcureEnabledKey = 'notif_procure_enabled';
  static const String _prefProcureTimesKey =
      'notif_procure_times'; // string list ["09:30", "17:30"]

  static const String _prefDailyReportEnabledKey =
      'notif_daily_report_enabled';
  static const String _prefDailyReportTimeKey =
      'notif_daily_report_time'; // string "21:00"

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          handlePayload(response.payload);
        },
      );

      // Listen for warm-start taps coming from native Android notifications
      if (_isAndroid) {
        _nativeChannel.setMethodCallHandler((call) async {
          if (call.method == 'onNotificationTap') {
            final payload = call.arguments?.toString();
            handlePayload(payload);
          }
        });
      }

      // Create high-priority Notification Channels for Android 8.0+ (do NOT prompt runtime dialogs here).
      final androidNotificationDetails =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidNotificationDetails != null) {
        await androidNotificationDetails.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
        await androidNotificationDetails.createNotificationChannel(
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
      _initialized = true;
    } catch (e) {
      debugPrint('[AppNotificationService] Plugin init error: $e');
    }

    await _configureLocalTimeZone();

    // Schedule native OS alarms + JobScheduler watchdog
    await rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling background notifications: $e');
    });

    // Periodic foreground check every 5 minutes
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      checkAndNotify();
    });

    // Check startup notification status
    unawaited(checkAndNotify().catchError((e) {
      debugPrint('Error running startup notification check: $e');
    }));
  }

  /// Checks whether the app was cold-started by tapping a native background notification.
  Future<void> checkAndConsumeInitialPayload() async {
    if (!_isAndroid) return;
    try {
      final payload =
          await _nativeChannel.invokeMethod<String>('getInitialPayload');
      if (payload != null && payload.isNotEmpty) {
        handlePayload(payload);
      }
    } catch (_) {}

    try {
      final launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      final payload = launchDetails?.notificationResponse?.payload;
      if ((launchDetails?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        handlePayload(payload);
      }
    } catch (_) {}
  }

  /// Configures the native local timezone so that alarms match the phone's wall-clock time.
  Future<void> _configureLocalTimeZone() async {
    if (_timezoneConfigured) return;
    try {
      tz.initializeTimeZones();
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      String timeZoneName;
      if (info is String) {
        timeZoneName = info;
      } else {
        try {
          timeZoneName = info.identifier as String;
        } catch (_) {
          timeZoneName = info.toString();
        }
      }
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      _timezoneConfigured = true;
      debugPrint(
          '[AppNotificationService] Local timezone configured: $timeZoneName');
    } catch (e) {
      debugPrint('[AppNotificationService] FlutterTimezone lookup error: $e');
      try {
        tz.initializeTimeZones();
        final offset = DateTime.now().timeZoneOffset;
        for (final loc in tz.timeZoneDatabase.locations.values) {
          if (loc.currentTimeZone.offset == offset.inMilliseconds) {
            tz.setLocalLocation(loc);
            _timezoneConfigured = true;
            debugPrint(
                '[AppNotificationService] Matched fallback timezone: ${loc.name}');
            break;
          }
        }
        if (!_timezoneConfigured) {
          tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
          _timezoneConfigured = true;
        }
      } catch (_) {}
    }
  }

  /// Calculates the next occurrence of a given hour and minute in the device's local timezone.
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// Safe zonedSchedule fallback when native Android MethodChannel is unavailable.
  Future<void> _safeZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required String payload,
    DateTimeComponents? matchDateTimeComponents,
    bool useAlarmClock = true,
  }) async {
    if (useAlarmClock) {
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
          payload: payload,
        );
        return;
      } catch (_) {}
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
      return;
    } catch (_) {}

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    } catch (err) {
      debugPrint(
          '[AppNotificationService] Fallback zonedSchedule error: $err');
    }
  }

  /// Schedules a 30-second test alarm to verify background alarm delivery when app is closed.
  Future<void> scheduleTestBackgroundAlarm({int delaySeconds = 30}) async {
    if (_isAndroid) {
      try {
        await _nativeChannel.invokeMethod<bool>(
          'scheduleTestAlarm',
          {'delaySeconds': delaySeconds},
        );
        return;
      } catch (e) {
        debugPrint(
            '[AppNotificationService] Native test alarm unavailable, using plugin fallback: $e');
      }
    }

    await _configureLocalTimeZone();
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(Duration(seconds: delaySeconds));

    const testDetails = AndroidNotificationDetails(
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

    await _safeZonedSchedule(
      id: 999,
      title: '⏰ Closed-App Alarm Test SUCCESS!',
      body:
          'Exact native alarm fired on schedule ($delaySeconds s)! Your notifications will ring on time even when the app is closed.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(android: testDetails),
      payload: 'test_alarm',
      useAlarmClock: true,
    );
  }

  /// Returns real-time Android system health diagnostics for background notification delivery.
  Future<Map<String, dynamic>> getNotificationDiagnostics() async {
    if (_isAndroid) {
      try {
        final raw = await _nativeChannel
            .invokeMapMethod<String, dynamic>('getNotificationDiagnostics');
        if (raw != null) return raw;
      } catch (_) {}
    }
    return <String, dynamic>{
      'notificationsEnabled': await areNotificationsEnabled(),
      'exactAlarmsAllowed': await canScheduleExactAlarms(),
      'ignoringBatteryOptimizations': true,
      'activeNativeAlarmsCount': 0,
      'periodicJobScheduled': false,
      'dbExists': false,
      'manufacturer': '',
      'sdkInt': 34,
    };
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return (await _nativeChannel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openExactAlarmSettings() async {
    if (!_isAndroid) return true;
    try {
      return (await _nativeChannel
              .invokeMethod<bool>('openExactAlarmSettings')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    if (!_isAndroid) return true;
    try {
      return (await _nativeChannel
              .invokeMethod<bool>('openNotificationSettings')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAutostartSettings() async {
    if (!_isAndroid) return true;
    try {
      return (await _nativeChannel
              .invokeMethod<bool>('openAutostartSettings')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Check if exact alarms can be scheduled on this device (Android 12+).
  Future<bool> canScheduleExactAlarms() async {
    if (_isAndroid) {
      try {
        final diag = await _nativeChannel
            .invokeMapMethod<String, dynamic>('getNotificationDiagnostics');
        if (diag != null && diag.containsKey('exactAlarmsAllowed')) {
          return diag['exactAlarmsAllowed'] == true;
        }
      } catch (_) {}
    }
    try {
      final androidDetails =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return (await androidDetails?.canScheduleExactNotifications()) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Prompts Android system settings to grant exact alarm scheduling if needed.
  Future<void> requestExactAlarmsPermission() async {
    if (_isAndroid) {
      final opened = await openExactAlarmSettings();
      if (opened) return;
    }
    try {
      final androidDetails =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidDetails?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Check if the user has enabled notifications in Android system settings.
  Future<bool> areNotificationsEnabled() async {
    if (_isAndroid) {
      try {
        final diag = await _nativeChannel
            .invokeMapMethod<String, dynamic>('getNotificationDiagnostics');
        if (diag != null && diag.containsKey('notificationsEnabled')) {
          return diag['notificationsEnabled'] == true;
        }
      } catch (_) {}
    }
    try {
      final androidDetails =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return (await androidDetails?.areNotificationsEnabled()) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Explicitly requests system notification permission on Android 13+.
  Future<bool?> requestNotificationsPermission() async {
    try {
      final androidDetails =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidDetails?.requestNotificationsPermission();
    } catch (e) {
      debugPrint(
          '[AppNotificationService] requestNotificationsPermission error: $e');
      return null;
    }
  }

  /// Fires an instant 1-second heads-up test notification to verify sound & banner.
  Future<bool> showInstantTestNotification() async {
    final androidDetails =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final areEnabled = (await androidDetails?.areNotificationsEnabled()) ?? true;
    if (!areEnabled) {
      await requestNotificationsPermission();
    }

    const testDetails = AndroidNotificationDetails(
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

    await _notificationsPlugin.show(
      888,
      '🔔 Notification Test SUCCESS!',
      'Sound, vibration, and banner are working on this phone!',
      const NotificationDetails(android: testDetails),
      payload: 'test_instant',
    );
    return areEnabled;
  }

  /// Shows immediate heads-up notification when an order or broadcast arrives from another device.
  Future<void> showLiveOrderNotification({
    required String title,
    required String body,
    String payload = 'pending_orders',
  }) async {
    const details = AndroidNotificationDetails(
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

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: details),
      payload: payload,
    );
  }

  /// Exports the complete active notification schedule to a map for cloud sync and native Android scheduler.
  Future<Map<String, dynamic>> exportNotificationSettingsMap() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': await isEnabled(),
      'pending_enabled': await isPendingOrdersEnabled(),
      'pending_mode': await getPendingOrdersMode(),
      'pending_times': prefs.getStringList(_prefPendingTimesKey) ??
          ['10:00', '14:00', '19:00'],
      'procure_enabled': await isProcurementEnabled(),
      'procure_times':
          prefs.getStringList(_prefProcureTimesKey) ?? ['09:30', '17:30'],
      'daily_report_enabled': await isDailyReportEnabled(),
      'daily_report_time':
          prefs.getString(_prefDailyReportTimeKey) ?? '21:00',
      'price_caution_enabled': await isPriceCautionEnabled(),
      'price_caution_days': await getPriceCautionDays(),
    };
  }

  /// Applies notification schedule received from the cloud (Firestore) and reschedules native alarms.
  Future<void> applyCloudNotificationSettings(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    if (map.containsKey('enabled')) {
      await prefs.setBool(_prefEnabledKey, map['enabled'] == true);
    }
    if (map.containsKey('pending_enabled')) {
      await prefs.setBool(
          _prefPendingEnabledKey, map['pending_enabled'] == true);
    }
    if (map.containsKey('pending_mode') && map['pending_mode'] is String) {
      await prefs.setString(
          _prefPendingModeKey, map['pending_mode'] as String);
    }
    if (map.containsKey('pending_times') && map['pending_times'] is List) {
      final list =
          (map['pending_times'] as List).map((e) => e.toString()).toList();
      await prefs.setStringList(_prefPendingTimesKey, list);
    }
    if (map.containsKey('procure_enabled')) {
      await prefs.setBool(
          _prefProcureEnabledKey, map['procure_enabled'] == true);
    }
    if (map.containsKey('procure_times') && map['procure_times'] is List) {
      final list =
          (map['procure_times'] as List).map((e) => e.toString()).toList();
      await prefs.setStringList(_prefProcureTimesKey, list);
    }
    if (map.containsKey('daily_report_enabled')) {
      await prefs.setBool(
          _prefDailyReportEnabledKey, map['daily_report_enabled'] == true);
    }
    if (map.containsKey('daily_report_time') &&
        map['daily_report_time'] is String) {
      await prefs.setString(
          _prefDailyReportTimeKey, map['daily_report_time'] as String);
    }
    if (map.containsKey('price_caution_enabled')) {
      await prefs.setBool(
          'price_caution_enabled', map['price_caution_enabled'] == true);
    }
    if (map.containsKey('price_caution_days') &&
        map['price_caution_days'] is num) {
      await prefs.setInt(
          'price_caution_days', (map['price_caution_days'] as num).toInt());
    }
    await rescheduleBackgroundNotifications();
    debugPrint(
        '[AppNotificationService] Applied cloud notification settings & rescheduled alarms.');
  }

  /// Registers native Android AlarmManager exact background alarms + persisted JobScheduler watchdog.
  /// Serialized with an internal queue lock so overlapping callers never cancel each other's alarms.
  Future<void> rescheduleBackgroundNotifications() async {
    if (_isRescheduling) {
      _pendingReschedule = true;
      return _rescheduleCompleter?.future ?? Future<void>.value();
    }

    _isRescheduling = true;
    _rescheduleCompleter = Completer<void>();

    try {
      do {
        _pendingReschedule = false;
        await _executeReschedulePass();
      } while (_pendingReschedule);
    } finally {
      _isRescheduling = false;
      final done = _rescheduleCompleter;
      _rescheduleCompleter = null;
      if (done != null && !done.isCompleted) {
        done.complete();
      }
    }
  }

  Future<void> _executeReschedulePass() async {
    // 1. Clean up any legacy plugin alarm IDs (200..299) once so they never duplicate native alarms
    try {
      final pending =
          await _notificationsPlugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= 200 && p.id <= 299) {
          await _notificationsPlugin.cancel(p.id);
        }
      }
    } catch (_) {}

    // 2. Primary on Android: sync config to native ShopAlarmScheduler (reads live SQLite in background)
    if (_isAndroid) {
      try {
        final configMap = await exportNotificationSettingsMap();
        final scheduledCount = await _nativeChannel.invokeMethod<int>(
          'saveAndScheduleAlarms',
          {'config': jsonEncode(configMap)},
        );
        debugPrint(
            '[AppNotificationService] Native ShopAlarmScheduler armed $scheduledCount exact alarms.');
        return;
      } catch (e) {
        debugPrint(
            '[AppNotificationService] Native alarm channel unavailable ($e); using plugin fallback.');
      }
    }

    // 3. Fallback when running outside native Android host (or MethodChannel absent in unit tests)
    try {
      final overallEnabled = await isEnabled();
      if (!overallEnabled) {
        await _notificationsPlugin.cancelAll();
        return;
      }

      await _configureLocalTimeZone();

      const androidPendingDetails = AndroidNotificationDetails(
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

      const androidProcureDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFFE11D48),
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(''),
      );

      const androidReportDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFF3B82F6),
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(''),
      );

      int notifIdCounter = 200;

      final pendingEnabled = await isPendingOrdersEnabled();
      if (pendingEnabled) {
        final mode = await getPendingOrdersMode();
        if (mode == 'hourly') {
          for (int h = 7; h <= 21; h++) {
            await _safeZonedSchedule(
              id: notifIdCounter++,
              title: '📋 Hourly Pending Orders Check',
              body: 'Check unfulfilled orders and update counter bills.',
              scheduledDate: _nextInstanceOfTime(h, 0),
              notificationDetails:
                  const NotificationDetails(android: androidPendingDetails),
              matchDateTimeComponents: DateTimeComponents.time,
              payload: 'pending_orders',
            );
          }
        } else if (_isTwoHourMode(mode)) {
          for (int h = 8; h <= 20; h += 2) {
            await _safeZonedSchedule(
              id: notifIdCounter++,
              title: '📋 Pending Orders Check',
              body: 'Check unfulfilled orders and update counter bills.',
              scheduledDate: _nextInstanceOfTime(h, 0),
              notificationDetails:
                  const NotificationDetails(android: androidPendingDetails),
              matchDateTimeComponents: DateTimeComponents.time,
              payload: 'pending_orders',
            );
          }
        } else {
          final times = await getPendingOrdersTimes();
          for (final t in times) {
            await _safeZonedSchedule(
              id: notifIdCounter++,
              title: '📋 Pending Orders Reminder',
              body: 'You have open orders to fulfill and close. Tap to view.',
              scheduledDate: _nextInstanceOfTime(t.hour, t.minute),
              notificationDetails:
                  const NotificationDetails(android: androidPendingDetails),
              matchDateTimeComponents: DateTimeComponents.time,
              payload: 'pending_orders',
            );
          }
        }
      }

      final procureEnabled = await isProcurementEnabled();
      if (procureEnabled) {
        final times = await getProcurementTimes();
        for (final t in times) {
          await _safeZonedSchedule(
            id: notifIdCounter++,
            title: '📦 Procurement List Reminder',
            body:
                'Items needed for customer orders. Tap to view procurement list.',
            scheduledDate: _nextInstanceOfTime(t.hour, t.minute),
            notificationDetails:
                const NotificationDetails(android: androidProcureDetails),
            matchDateTimeComponents: DateTimeComponents.time,
            payload: 'procurement',
          );
        }
      }

      final reportEnabled = await isDailyReportEnabled();
      if (reportEnabled) {
        final t = await getDailyReportTime();
        await _safeZonedSchedule(
          id: notifIdCounter++,
          title: '📊 Daily Shop Sales Summary',
          body:
              'Review today\'s completed orders, collections, and daily revenue.',
          scheduledDate: _nextInstanceOfTime(t.hour, t.minute),
          notificationDetails:
              const NotificationDetails(android: androidReportDetails),
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'daily_report',
        );
      }
    } catch (e) {
      debugPrint(
          '[AppNotificationService] Background notification fallback error: $e');
    }
  }

  static bool _isTwoHourMode(String mode) =>
      mode == 'two_hours' || mode == 'every2hours';

  void handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final db = DatabaseHelper.instance;
    final orderRepo = OrderRepository(db);
    final custRepo = CustomerRepository(db);
    final prodRepo = ProductRepository(db);
    final backupSvc = BackupService(db);

    if (payload == 'pending_orders' || payload == 'orders') {
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
    } else if (payload == 'stale_prices' || payload == 'manage_products') {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => SimpleProductAdminScreen(
            productRepository: prodRepo,
            initialOnlyStalePrices: true,
          ),
        ),
      );
    } else if (payload == 'daily_report') {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryScreen(
            orderRepository: orderRepo,
            backupService: backupSvc,
            customerRepository: custRepo,
            productRepository: prodRepo,
            initialFilter: HistoryFilter.today,
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
      await rescheduleBackgroundNotifications();
      unawaited(checkAndNotify(force: true));
    } else {
      await rescheduleBackgroundNotifications();
      try {
        await _notificationsPlugin.cancelAll();
      } catch (_) {}
    }
  }

  // --- Pending Orders Reminder Preferences ---
  Future<bool> isPendingOrdersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPendingEnabledKey) ?? true;
  }

  Future<void> setPendingOrdersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPendingEnabledKey, enabled);
    await rescheduleBackgroundNotifications();
  }

  Future<String> getPendingOrdersMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPendingModeKey) ?? 'scheduled';
  }

  Future<void> setPendingOrdersMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPendingModeKey, mode);
    await rescheduleBackgroundNotifications();
  }

  Future<List<TimeOfDay>> getPendingOrdersTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefPendingTimesKey);
    if (raw == null || raw.isEmpty) {
      return [
        const TimeOfDay(hour: 10, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 19, minute: 0),
      ];
    }
    return raw.map(_parseTimeOfDay).toList();
  }

  Future<void> setPendingOrdersTimes(List<TimeOfDay> times) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefPendingTimesKey, times.map(_formatTimeOfDay).toList());
    await rescheduleBackgroundNotifications();
  }

  // --- Procurement List Reminder Preferences ---
  Future<bool> isProcurementEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefProcureEnabledKey) ?? true;
  }

  Future<void> setProcurementEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefProcureEnabledKey, enabled);
    await rescheduleBackgroundNotifications();
  }

  Future<List<TimeOfDay>> getProcurementTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefProcureTimesKey);
    if (raw == null || raw.isEmpty) {
      return [
        const TimeOfDay(hour: 9, minute: 30),
        const TimeOfDay(hour: 17, minute: 30),
      ];
    }
    return raw.map(_parseTimeOfDay).toList();
  }

  Future<void> setProcurementTimes(List<TimeOfDay> times) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefProcureTimesKey, times.map(_formatTimeOfDay).toList());
    await rescheduleBackgroundNotifications();
  }

  // --- Daily Report Preferences ---
  Future<bool> isDailyReportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDailyReportEnabledKey) ?? true;
  }

  Future<void> setDailyReportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDailyReportEnabledKey, enabled);
    await rescheduleBackgroundNotifications();
  }

  Future<TimeOfDay> getDailyReportTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefDailyReportTimeKey);
    if (raw == null || raw.isEmpty) {
      return const TimeOfDay(hour: 21, minute: 0); // 9:00 PM
    }
    return _parseTimeOfDay(raw);
  }

  Future<void> setDailyReportTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDailyReportTimeKey, _formatTimeOfDay(time));
    await rescheduleBackgroundNotifications();
  }

  // --- Legacy Compatibility ---
  Future<NotificationScheduleMode> getScheduleMode() async {
    final mode = await getPendingOrdersMode();
    if (mode == 'hourly') return NotificationScheduleMode.hourly;
    if (_isTwoHourMode(mode)) return NotificationScheduleMode.every2Hours;
    return NotificationScheduleMode.scheduled;
  }

  Future<void> setScheduleMode(NotificationScheduleMode mode) async {
    if (mode == NotificationScheduleMode.hourly) {
      await setPendingOrdersMode('hourly');
    } else if (mode == NotificationScheduleMode.every2Hours) {
      await setPendingOrdersMode('two_hours');
    } else {
      await setPendingOrdersMode('scheduled');
    }
  }

  Future<TimeOfDay> getMorningTime() async {
    final times = await getPendingOrdersTimes();
    return times.isNotEmpty ? times.first : const TimeOfDay(hour: 10, minute: 0);
  }

  Future<void> setMorningTime(TimeOfDay time) async {
    final times = await getPendingOrdersTimes();
    if (times.isNotEmpty) {
      times[0] = time;
    } else {
      times.add(time);
    }
    await setPendingOrdersTimes(times);
  }

  Future<TimeOfDay> getMiddayTime() async {
    final times = await getPendingOrdersTimes();
    return times.length > 1 ? times[1] : const TimeOfDay(hour: 14, minute: 0);
  }

  Future<void> setMiddayTime(TimeOfDay time) async {
    final times = await getPendingOrdersTimes();
    if (times.length > 1) {
      times[1] = time;
    } else {
      times.add(time);
    }
    await setPendingOrdersTimes(times);
  }

  Future<TimeOfDay> getEveningTime() async {
    final times = await getPendingOrdersTimes();
    return times.length > 2 ? times[2] : const TimeOfDay(hour: 19, minute: 0);
  }

  Future<void> setEveningTime(TimeOfDay time) async {
    final times = await getPendingOrdersTimes();
    if (times.length > 2) {
      times[2] = time;
    } else {
      times.add(time);
    }
    await setPendingOrdersTimes(times);
  }

  // Price caution threshold days (default 30 days)
  Future<int> getPriceCautionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('price_caution_days') ?? 30;
  }

  Future<void> setPriceCautionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('price_caution_days', days);
    await rescheduleBackgroundNotifications();
  }

  Future<bool> isPriceCautionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('price_caution_enabled') ?? true;
  }

  Future<void> setPriceCautionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('price_caution_enabled', enabled);
    await rescheduleBackgroundNotifications();
  }

  // --- String Time Converters ---
  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTimeOfDay(String s) {
    try {
      final parts = s.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (_) {}
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _syncDedupeSlot(String key, String slot) async {
    if (!_isAndroid) return;
    try {
      await _nativeChannel.invokeMethod<bool>(
        'syncDedupeSlot',
        {'key': key, 'slot': slot},
      );
    } catch (_) {}
  }

  /// Checks order, procurement, daily report, and price caution according to user schedule.
  Future<void> checkAndNotify({bool force = false}) async {
    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final dayPrefix = '${now.year}-${now.month}-${now.day}';

      final orderRepo = OrderRepository(DatabaseHelper.instance);
      final stats = await orderRepo.getPendingAndProcurementStats();

      // 1. URGENT OVERDUE ORDERS CHECK (>3 days old)
      if (stats.oldPendingCount > 0) {
        final overdueSlot = '$dayPrefix-overdue-${now.hour}';
        if (force ||
            prefs.getString('${_prefLastNotifiedKey}_overdue') !=
                overdueSlot) {
          await _showOverdueNotification(
              stats.oldPendingCount, stats.pendingCount);
          await prefs.setString(
              '${_prefLastNotifiedKey}_overdue', overdueSlot);
          await _syncDedupeSlot('notif_overdue', overdueSlot);
        }
      }

      // 2. PENDING ORDERS REMINDERS (Custom times / hourly / 2-hourly)
      final pendingOn = await isPendingOrdersEnabled();
      if (pendingOn && stats.pendingCount > 0) {
        final mode = await getPendingOrdersMode();
        bool shouldNotifyPending = force;
        String pendingSlot = '$dayPrefix-pending';

        if (!force) {
          if (mode == 'hourly') {
            if (now.hour >= 7 && now.hour <= 21) {
              pendingSlot = '$dayPrefix-pending-hourly-${now.hour}';
              shouldNotifyPending = prefs.getString(
                      '${_prefLastNotifiedKey}_pending_$pendingSlot') !=
                  pendingSlot;
            }
          } else if (_isTwoHourMode(mode)) {
            if (now.hour >= 8 && now.hour <= 20 && now.hour % 2 == 0) {
              pendingSlot = '$dayPrefix-pending-2hr-${now.hour}';
              shouldNotifyPending = prefs.getString(
                      '${_prefLastNotifiedKey}_pending_$pendingSlot') !=
                  pendingSlot;
            }
          } else {
            final times = await getPendingOrdersTimes();
            for (final t in times) {
              final nowTotal = now.hour * 60 + now.minute;
              final targetTotal = t.hour * 60 + t.minute;
              if ((nowTotal - targetTotal).abs() <= 15 &&
                  nowTotal >= targetTotal - 1) {
                pendingSlot = '$dayPrefix-pending-${t.hour}:${t.minute}';
                shouldNotifyPending = prefs.getString(
                        '${_prefLastNotifiedKey}_pending_$pendingSlot') !=
                    pendingSlot;
                break;
              }
            }
          }
        }

        if (shouldNotifyPending) {
          String pendingTitle =
              '📋 ${stats.pendingCount} Pending Counter Orders';
          String pendingBody =
              'You have ${stats.pendingCount} unclosed customer order(s). Tap here to review and finalize.';
          if (now.hour <= 10) {
            pendingTitle =
                '🌅 Morning Status: ${stats.pendingCount} Open Orders';
          } else if (now.hour >= 20) {
            pendingTitle =
                '🌙 Closing Reminder: ${stats.pendingCount} Unclosed Bills';
            pendingBody =
                'Day-end closing! Close counter orders to update daily sales & khata balances.';
          }

          const androidDetails = AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            color: Color(0xFF0F766E),
            styleInformation: BigTextStyleInformation(''),
          );
          await _notificationsPlugin.show(
            101,
            pendingTitle,
            pendingBody,
            const NotificationDetails(android: androidDetails),
            payload: 'pending_orders',
          );
          await prefs.setString(
              '${_prefLastNotifiedKey}_pending_$pendingSlot', pendingSlot);
          await _syncDedupeSlot('notif_pending_$pendingSlot', pendingSlot);
        }
      }

      // 3. PROCUREMENT LIST REMINDERS
      final procureOn = await isProcurementEnabled();
      if (procureOn && stats.toProcureCount > 0) {
        bool shouldNotifyProcure = force;
        String procureSlot = '$dayPrefix-procure';

        if (!force) {
          final times = await getProcurementTimes();
          for (final t in times) {
            final nowTotal = now.hour * 60 + now.minute;
            final targetTotal = t.hour * 60 + t.minute;
            if ((nowTotal - targetTotal).abs() <= 15 &&
                nowTotal >= targetTotal - 1) {
              procureSlot = '$dayPrefix-procure-${t.hour}:${t.minute}';
              shouldNotifyProcure = prefs.getString(
                      '${_prefLastNotifiedKey}_procure_$procureSlot') !=
                  procureSlot;
              break;
            }
          }
        }

        if (shouldNotifyProcure) {
          const androidDetails = AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            color: Color(0xFFE11D48),
            styleInformation: BigTextStyleInformation(''),
          );
          await _notificationsPlugin.show(
            102,
            '📦 Procurement: ${stats.toProcureCount} Item(s) Short / Needed',
            'Items are short or out of stock for customer orders. Tap to view procurement list.',
            const NotificationDetails(android: androidDetails),
            payload: 'procurement',
          );
          await prefs.setString(
              '${_prefLastNotifiedKey}_procure_$procureSlot', procureSlot);
          await _syncDedupeSlot('notif_procure_$procureSlot', procureSlot);
        }
      }

      // 4. DAILY SHOP SUMMARY REPORT
      final dailyReportOn = await isDailyReportEnabled();
      if (dailyReportOn) {
        final reportTime = await getDailyReportTime();
        final reportSlot = '$dayPrefix-daily-report';
        final nowTotal = now.hour * 60 + now.minute;
        final targetTotal = reportTime.hour * 60 + reportTime.minute;
        bool shouldNotifyReport = force ||
            ((nowTotal - targetTotal).abs() <= 15 &&
                nowTotal >= targetTotal - 1 &&
                prefs.getString('${_prefLastNotifiedKey}_report') !=
                    reportSlot);

        if (shouldNotifyReport) {
          final db = await DatabaseHelper.instance.database;
          final todayIso = DateFormat('yyyy-MM-dd').format(now);
          final todayOrders = await db.rawQuery('''
            SELECT COUNT(*) as count, COALESCE(SUM(estimate_total), 0.0) as total_sales
            FROM orders
            WHERE date(created_at) = ? AND LOWER(status) IN ('completed', 'closed')
          ''', [todayIso]);
          final totalSales =
              (todayOrders.first['total_sales'] as num?)?.toDouble() ?? 0.0;
          final completedCount =
              (todayOrders.first['count'] as num?)?.toInt() ?? 0;

          final todayPayments = await db.rawQuery('''
            SELECT COALESCE(SUM(amount), 0.0) as total_collected
            FROM customer_payments
            WHERE date(created_at) = ?
          ''', [todayIso]);
          final totalCollected =
              (todayPayments.first['total_collected'] as num?)?.toDouble() ??
                  0.0;

          await _showDailyReportNotification(
            totalSales: totalSales,
            completedCount: completedCount,
            totalCollected: totalCollected,
            pendingCount: stats.pendingCount,
          );
          await prefs.setString('${_prefLastNotifiedKey}_report', reportSlot);
          await _syncDedupeSlot('notif_report', reportSlot);
        }
      }

      // 5. MARKET PRICE CAUTION CHECK
      if (force || (now.hour >= 8 && now.hour <= 11)) {
        final priceCautionOn = await isPriceCautionEnabled();
        if (priceCautionOn) {
          final cautionDays = await getPriceCautionDays();
          final prodRepo = ProductRepository(DatabaseHelper.instance);
          final staleCount =
              await prodRepo.getStalePriceCount(thresholdDays: cautionDays);
          final priceCautionSlot = '$dayPrefix-price-caution';
          if (staleCount > 0 &&
              (force ||
                  prefs.getString('${_prefLastNotifiedKey}_price_caution') !=
                      priceCautionSlot)) {
            await _showStalePriceNotification(staleCount, cautionDays);
            await prefs.setString(
                '${_prefLastNotifiedKey}_price_caution', priceCautionSlot);
            await _syncDedupeSlot('notif_price_caution', priceCautionSlot);
          } else if (staleCount == 0) {
            await _notificationsPlugin.cancel(104);
          }
        }
      }
    } catch (e) {
      debugPrint('[AppNotificationService] Error checking notifications: $e');
    }
  }

  Future<void> _showDailyReportNotification({
    required double totalSales,
    required int completedCount,
    required double totalCollected,
    required int pendingCount,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF0F766E),
      styleInformation: BigTextStyleInformation(''),
    );
    final title = '📊 Daily Shop Report: ₹${totalSales.toStringAsFixed(0)} Sales';
    final body =
        'Completed $completedCount orders today. Collected: ₹${totalCollected.toStringAsFixed(0)}. Open pending orders: $pendingCount. Tap for details.';

    await _notificationsPlugin.show(
      105,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: 'daily_report',
    );
  }

  Future<void> _showOverdueNotification(
      int oldOrdersCount, int totalPending) async {
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

  Future<void> _showStalePriceNotification(int count, int days) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFFD97706),
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      104,
      '🏷️ Market Price Check: $count Product(s) Outdated',
      '$count item rate(s) have not been updated for >$days days. Market rates may have changed. Tap to review.',
      details,
      payload: 'stale_prices',
    );
  }

  void dispose() {
    _periodicTimer?.cancel();
  }
}
