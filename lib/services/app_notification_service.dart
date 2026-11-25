import 'dart:async';
import 'package:flutter/material.dart';
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

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Timer? _periodicTimer;
  bool _initialized = false;

  static const String _channelId = 'shop_order_reminders';
  static const String _channelName = 'Shop Order & Procurement Reminders';
  static const String _channelDesc =
      'Reminders for unclosed bills and items needing procurement';

  static const String _prefEnabledKey = 'hourly_reminders_enabled';
  static const String _prefLastNotifiedKey = 'last_notified_slot_key';

  // Category specific keys
  static const String _prefPendingEnabledKey = 'notif_pending_orders_enabled';
  static const String _prefPendingModeKey = 'notif_pending_orders_mode'; // 'scheduled', 'hourly', 'every2hours'
  static const String _prefPendingTimesKey = 'notif_pending_orders_times'; // string list ["10:00", "14:00", "19:00"]

  static const String _prefProcureEnabledKey = 'notif_procure_enabled';
  static const String _prefProcureTimesKey = 'notif_procure_times'; // string list ["09:30", "17:30"]

  static const String _prefDailyReportEnabledKey = 'notif_daily_report_enabled';
  static const String _prefDailyReportTimeKey = 'notif_daily_report_time'; // string "21:00"

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
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      // Request notification permissions for Android 13+
      await androidNotificationDetails.requestNotificationsPermission();
      try {
        await androidNotificationDetails.requestExactAlarmsPermission();
      } catch (_) {}
    }

    await _configureLocalTimeZone();

    // Schedule Android OS background alarms for all active reminder times
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling background notifications: $e');
    }));

    // Periodic check every 5 minutes to accurately catch scheduled milestones while foregrounded
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      checkAndNotify();
    });

    // Run check on startup
    unawaited(checkAndNotify().catchError((e) {
      debugPrint('Error running startup notification check: $e');
    }));
  }

  /// Configures the native local timezone so that alarms match the phone's wall-clock time
  Future<void> _configureLocalTimeZone() async {
    try {
      tz.initializeTimeZones();
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = info is String
          ? info
          : (info?.identifier?.toString() ?? info.toString());
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('[AppNotificationService] Local timezone configured: $timeZoneName');
    } catch (e) {
      debugPrint('[AppNotificationService] FlutterTimezone lookup error: $e');
      try {
        final offset = DateTime.now().timeZoneOffset;
        for (final loc in tz.timeZoneDatabase.locations.values) {
          if (loc.currentTimeZone.offset == offset.inMilliseconds) {
            tz.setLocalLocation(loc);
            debugPrint('[AppNotificationService] Matched fallback timezone: ${loc.name}');
            break;
          }
        }
      } catch (_) {}
    }
  }

  /// Calculates the next occurrence of a given hour and minute in the device's local timezone
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

  /// Safely registers an alarm with Android AlarmManager.
  /// Uses AndroidScheduleMode.alarmClock as primary (highest OS priority, fires even in Doze/sleep),
  /// falling back to exactAllowWhileIdle and inexactAllowWhileIdle.
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
    // 1. Primary: AndroidScheduleMode.alarmClock (Highest priority in Android OS, wakes device from Doze mode)
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
        debugPrint('[AppNotificationService] Scheduled #$id at $scheduledDate via alarmClock mode.');
        return;
      } catch (e) {
        debugPrint('[AppNotificationService] alarmClock schedule failed: $e. Falling back to exactAllowWhileIdle...');
      }
    }

    // 2. Secondary: AndroidScheduleMode.exactAllowWhileIdle
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
      debugPrint('[AppNotificationService] Scheduled #$id at $scheduledDate via exactAllowWhileIdle.');
      return;
    } catch (e) {
      debugPrint('[AppNotificationService] exactAllowWhileIdle schedule failed: $e. Falling back to inexactAllowWhileIdle...');
    }

    // 3. Tertiary fallback: AndroidScheduleMode.inexactAllowWhileIdle
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
      debugPrint('[AppNotificationService] Scheduled #$id at $scheduledDate via inexactAllowWhileIdle.');
    } catch (err) {
      debugPrint('[AppNotificationService] All zonedSchedule attempts failed: $err');
    }
  }

  /// Schedule a 30-second test alarm to verify background alarm delivery when app is closed
  Future<void> scheduleTestBackgroundAlarm({int delaySeconds = 30}) async {
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
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(''),
    );

    await _safeZonedSchedule(
      id: 999,
      title: '⏰ Closed-App Alarm Test SUCCESS!',
      body: 'Exact native alarm fired on schedule ($delaySeconds s)! Your notifications will ring on time even when the app is closed.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(android: testDetails),
      payload: 'test_alarm',
      useAlarmClock: true,
    );
  }

  /// Check if exact alarms can be scheduled on this device (Android 12+)
  Future<bool> canScheduleExactAlarms() async {
    final androidDetails =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return (await androidDetails?.canScheduleExactNotifications()) ?? true;
  }

  /// Prompts Android system settings to grant exact alarm scheduling if needed
  Future<void> requestExactAlarmsPermission() async {
    final androidDetails =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidDetails?.requestExactAlarmsPermission();
  }

  /// Exports the complete active notification schedule to a map for cloud sync
  Future<Map<String, dynamic>> exportNotificationSettingsMap() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': await isEnabled(),
      'pending_enabled': await isPendingOrdersEnabled(),
      'pending_mode': await getPendingOrdersMode(),
      'pending_times': prefs.getStringList(_prefPendingTimesKey) ?? ['10:00', '14:00', '19:00'],
      'procure_enabled': await isProcurementEnabled(),
      'procure_times': prefs.getStringList(_prefProcureTimesKey) ?? ['09:30', '17:30'],
      'daily_report_enabled': await isDailyReportEnabled(),
      'daily_report_time': prefs.getString(_prefDailyReportTimeKey) ?? '21:00',
      'price_caution_enabled': await isPriceCautionEnabled(),
      'price_caution_days': await getPriceCautionDays(),
    };
  }

  /// Applies notification schedule received from the cloud (Firestore) and reschedules native alarms
  Future<void> applyCloudNotificationSettings(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    if (map.containsKey('enabled')) {
      await prefs.setBool(_prefEnabledKey, map['enabled'] == true);
    }
    if (map.containsKey('pending_enabled')) {
      await prefs.setBool(_prefPendingEnabledKey, map['pending_enabled'] == true);
    }
    if (map.containsKey('pending_mode') && map['pending_mode'] is String) {
      await prefs.setString(_prefPendingModeKey, map['pending_mode'] as String);
    }
    if (map.containsKey('pending_times') && map['pending_times'] is List) {
      final list = (map['pending_times'] as List).map((e) => e.toString()).toList();
      await prefs.setStringList(_prefPendingTimesKey, list);
    }
    if (map.containsKey('procure_enabled')) {
      await prefs.setBool(_prefProcureEnabledKey, map['procure_enabled'] == true);
    }
    if (map.containsKey('procure_times') && map['procure_times'] is List) {
      final list = (map['procure_times'] as List).map((e) => e.toString()).toList();
      await prefs.setStringList(_prefProcureTimesKey, list);
    }
    if (map.containsKey('daily_report_enabled')) {
      await prefs.setBool(_prefDailyReportEnabledKey, map['daily_report_enabled'] == true);
    }
    if (map.containsKey('daily_report_time') && map['daily_report_time'] is String) {
      await prefs.setString(_prefDailyReportTimeKey, map['daily_report_time'] as String);
    }
    if (map.containsKey('price_caution_enabled')) {
      await prefs.setBool('price_caution_enabled', map['price_caution_enabled'] == true);
    }
    if (map.containsKey('price_caution_days') && map['price_caution_days'] is num) {
      await prefs.setInt('price_caution_days', (map['price_caution_days'] as num).toInt());
    }
    await rescheduleBackgroundNotifications();
    debugPrint('[AppNotificationService] Applied cloud notification settings & rescheduled alarms.');
  }

  /// Registers native Android AlarmManager exact background alarms that fire
  /// even when the phone is locked or the app process is terminated.
  Future<void> rescheduleBackgroundNotifications() async {
    final overallEnabled = await isEnabled();
    if (!overallEnabled) {
      for (int id = 200; id <= 299; id++) {
        await _notificationsPlugin.cancel(id);
      }
      return;
    }

    await _configureLocalTimeZone();

    // Cancel previously scheduled background alarm IDs (200..299)
    for (int id = 200; id <= 299; id++) {
      await _notificationsPlugin.cancel(id);
    }

    const androidPendingDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF0F766E),
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
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
      fullScreenIntent: true,
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
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(''),
    );

    int notifIdCounter = 200;

    try {
      // 1. Pending Orders Alarms
      final pendingEnabled = await isPendingOrdersEnabled();
      if (pendingEnabled) {
        final mode = await getPendingOrdersMode();
        if (mode == 'hourly') {
          await _notificationsPlugin.periodicallyShow(
            notifIdCounter++,
            '📋 Hourly Pending Orders Check',
            'Check unfulfilled orders and update counter bills.',
            RepeatInterval.hourly,
            const NotificationDetails(android: androidPendingDetails),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: 'pending_orders',
          );
        } else {
          final times = await getPendingOrdersTimes();
          for (final t in times) {
            final tzDt = _nextInstanceOfTime(t.hour, t.minute);
            await _safeZonedSchedule(
              id: notifIdCounter++,
              title: '📋 Pending Orders Reminder',
              body: 'You have open orders to fulfill and close. Tap to view.',
              scheduledDate: tzDt,
              notificationDetails: const NotificationDetails(android: androidPendingDetails),
              matchDateTimeComponents: DateTimeComponents.time,
              payload: 'pending_orders',
            );
          }
        }
      }

      // 2. Procurement List Alarms
      final procureEnabled = await isProcurementEnabled();
      if (procureEnabled) {
        final times = await getProcurementTimes();
        for (final t in times) {
          final tzDt = _nextInstanceOfTime(t.hour, t.minute);
          await _safeZonedSchedule(
            id: notifIdCounter++,
            title: '📦 Procurement List Reminder',
            body: 'Items needed for customer orders. Tap to view procurement list.',
            scheduledDate: tzDt,
            notificationDetails: const NotificationDetails(android: androidProcureDetails),
            matchDateTimeComponents: DateTimeComponents.time,
            payload: 'procurement',
          );
        }
      }

      // 3. Daily Sales Report Alarm
      final reportEnabled = await isDailyReportEnabled();
      if (reportEnabled) {
        final t = await getDailyReportTime();
        final tzDt = _nextInstanceOfTime(t.hour, t.minute);
        await _safeZonedSchedule(
          id: notifIdCounter++,
          title: '📊 Daily Shop Sales Summary',
          body: 'Review today\'s completed orders, collections, and daily revenue.',
          scheduledDate: tzDt,
          notificationDetails: const NotificationDetails(android: androidReportDetails),
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'daily_report',
        );
      }
    } catch (e) {
      debugPrint('[AppNotificationService] Background notification scheduling error: $e');
    }
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
      unawaited(rescheduleBackgroundNotifications().catchError((e) {
        debugPrint('Error rescheduling notifications: $e');
      }));
      checkAndNotify(force: true);
    } else {
      await _notificationsPlugin.cancelAll();
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
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
  }

  Future<String> getPendingOrdersMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPendingModeKey) ?? 'scheduled';
  }

  Future<void> setPendingOrdersMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPendingModeKey, mode);
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
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
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
  }

  // --- Procurement List Reminder Preferences ---
  Future<bool> isProcurementEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefProcureEnabledKey) ?? true;
  }

  Future<void> setProcurementEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefProcureEnabledKey, enabled);
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
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
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
  }

  // --- Daily Report Preferences ---
  Future<bool> isDailyReportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDailyReportEnabledKey) ?? true;
  }

  Future<void> setDailyReportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDailyReportEnabledKey, enabled);
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
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
    unawaited(rescheduleBackgroundNotifications().catchError((e) {
      debugPrint('Error rescheduling notifications: $e');
    }));
  }

  // --- Legacy Compatibility ---
  Future<NotificationScheduleMode> getScheduleMode() async {
    final mode = await getPendingOrdersMode();
    if (mode == 'hourly') return NotificationScheduleMode.hourly;
    if (mode == 'every2hours') return NotificationScheduleMode.every2Hours;
    return NotificationScheduleMode.scheduled;
  }

  Future<void> setScheduleMode(NotificationScheduleMode mode) async {
    if (mode == NotificationScheduleMode.hourly) {
      await setPendingOrdersMode('hourly');
    } else if (mode == NotificationScheduleMode.every2Hours) {
      await setPendingOrdersMode('every2hours');
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
  }

  Future<bool> isPriceCautionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('price_caution_enabled') ?? true;
  }

  Future<void> setPriceCautionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('price_caution_enabled', enabled);
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
        if (force || prefs.getString('${_prefLastNotifiedKey}_overdue') != overdueSlot) {
          await _showOverdueNotification(stats.oldPendingCount, stats.pendingCount);
          await prefs.setString('${_prefLastNotifiedKey}_overdue', overdueSlot);
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
              shouldNotifyPending = prefs.getString('${_prefLastNotifiedKey}_pending_$pendingSlot') != pendingSlot;
            }
          } else if (mode == 'every2hours') {
            if (now.hour >= 8 && now.hour <= 20 && now.hour % 2 == 0) {
              pendingSlot = '$dayPrefix-pending-2hr-${now.hour}';
              shouldNotifyPending = prefs.getString('${_prefLastNotifiedKey}_pending_$pendingSlot') != pendingSlot;
            }
          } else {
            // Scheduled specific times
            final times = await getPendingOrdersTimes();
            for (final t in times) {
              if (now.hour == t.hour && (now.minute - t.minute).abs() <= 15) {
                pendingSlot = '$dayPrefix-pending-${t.hour}:${t.minute}';
                shouldNotifyPending = prefs.getString('${_prefLastNotifiedKey}_pending_$pendingSlot') != pendingSlot;
                break;
              }
            }
          }
        }

        if (shouldNotifyPending) {
          String pendingTitle = '📋 ${stats.pendingCount} Pending Counter Orders';
          String pendingBody =
              'You have ${stats.pendingCount} unclosed customer order(s). Tap here to review and finalize.';
          if (now.hour <= 10) {
            pendingTitle = '🌅 Morning Status: ${stats.pendingCount} Open Orders';
          } else if (now.hour >= 20) {
            pendingTitle = '🌙 Closing Reminder: ${stats.pendingCount} Unclosed Bills';
            pendingBody = 'Day-end closing! Close counter orders to update daily sales & khata balances.';
          }

          const androidDetails = AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
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
          await prefs.setString('${_prefLastNotifiedKey}_pending_$pendingSlot', pendingSlot);
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
            if (now.hour == t.hour && (now.minute - t.minute).abs() <= 15) {
              procureSlot = '$dayPrefix-procure-${t.hour}:${t.minute}';
              shouldNotifyProcure = prefs.getString('${_prefLastNotifiedKey}_procure_$procureSlot') != procureSlot;
              break;
            }
          }
        }

        if (shouldNotifyProcure) {
          const androidDetails = AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
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
          await prefs.setString('${_prefLastNotifiedKey}_procure_$procureSlot', procureSlot);
        }
      }

      // 4. DAILY SHOP SUMMARY REPORT
      final dailyReportOn = await isDailyReportEnabled();
      if (dailyReportOn) {
        final reportTime = await getDailyReportTime();
        final reportSlot = '$dayPrefix-daily-report';
        bool shouldNotifyReport = force ||
            (now.hour == reportTime.hour &&
                (now.minute - reportTime.minute).abs() <= 15 &&
                prefs.getString('${_prefLastNotifiedKey}_report') != reportSlot);

        if (shouldNotifyReport) {
          final db = await DatabaseHelper.instance.database;
          final todayIso = DateFormat('yyyy-MM-dd').format(now);
          final todayOrders = await db.rawQuery('''
            SELECT COUNT(*) as count, COALESCE(SUM(estimate_total), 0.0) as total_sales
            FROM orders
            WHERE date(created_at) = ? AND LOWER(status) IN ('completed', 'closed')
          ''', [todayIso]);
          final totalSales = (todayOrders.first['total_sales'] as num?)?.toDouble() ?? 0.0;
          final completedCount = (todayOrders.first['count'] as num?)?.toInt() ?? 0;

          final todayPayments = await db.rawQuery('''
            SELECT COALESCE(SUM(amount), 0.0) as total_collected
            FROM customer_payments
            WHERE date(created_at) = ?
          ''', [todayIso]);
          final totalCollected =
              (todayPayments.first['total_collected'] as num?)?.toDouble() ?? 0.0;

          await _showDailyReportNotification(
            totalSales: totalSales,
            completedCount: completedCount,
            totalCollected: totalCollected,
            pendingCount: stats.pendingCount,
          );
          await prefs.setString('${_prefLastNotifiedKey}_report', reportSlot);
        }
      }

      // 5. MARKET PRICE CAUTION CHECK
      if (force || now.hour <= 11) {
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
      importance: Importance.high,
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
      importance: Importance.high,
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
