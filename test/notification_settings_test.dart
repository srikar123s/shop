import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/services/app_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Settings & Preferences Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default notification settings are initialized properly', () async {
      final notif = AppNotificationService.instance;

      expect(await notif.isEnabled(), isTrue);
      expect(await notif.isPendingOrdersEnabled(), isTrue);
      expect(await notif.getPendingOrdersMode(), 'scheduled');

      final pendingTimes = await notif.getPendingOrdersTimes();
      expect(pendingTimes.length, 3);
      expect(pendingTimes[0].hour, 10);
      expect(pendingTimes[1].hour, 14);
      expect(pendingTimes[2].hour, 19);

      expect(await notif.isProcurementEnabled(), isTrue);
      final procureTimes = await notif.getProcurementTimes();
      expect(procureTimes.length, 2);
      expect(procureTimes[0].hour, 9);
      expect(procureTimes[0].minute, 30);
      expect(procureTimes[1].hour, 17);
      expect(procureTimes[1].minute, 30);

      expect(await notif.isDailyReportEnabled(), isTrue);
      final dailyTime = await notif.getDailyReportTime();
      expect(dailyTime.hour, 21);
      expect(dailyTime.minute, 0);

      expect(await notif.isPriceCautionEnabled(), isTrue);
      expect(await notif.getPriceCautionDays(), 30);
    });

    test('Custom times and modes can be configured and persisted', () async {
      final notif = AppNotificationService.instance;

      // Configure pending orders mode to hourly
      await notif.setPendingOrdersMode('hourly');
      expect(await notif.getPendingOrdersMode(), 'hourly');

      // Configure custom pending times
      final customPendingTimes = [
        const TimeOfDay(hour: 8, minute: 15),
        const TimeOfDay(hour: 13, minute: 45),
        const TimeOfDay(hour: 18, minute: 0),
        const TimeOfDay(hour: 21, minute: 30),
      ];
      await notif.setPendingOrdersTimes(customPendingTimes);
      final savedPendingTimes = await notif.getPendingOrdersTimes();
      expect(savedPendingTimes.length, 4);
      expect(savedPendingTimes[0].hour, 8);
      expect(savedPendingTimes[0].minute, 15);
      expect(savedPendingTimes[3].hour, 21);
      expect(savedPendingTimes[3].minute, 30);

      // Configure custom procurement times
      final customProcureTimes = [
        const TimeOfDay(hour: 7, minute: 0),
        const TimeOfDay(hour: 12, minute: 0),
        const TimeOfDay(hour: 17, minute: 0),
      ];
      await notif.setProcurementTimes(customProcureTimes);
      final savedProcureTimes = await notif.getProcurementTimes();
      expect(savedProcureTimes.length, 3);
      expect(savedProcureTimes[0].hour, 7);
      expect(savedProcureTimes[1].hour, 12);
      expect(savedProcureTimes[2].hour, 17);

      // Configure daily report time
      await notif.setDailyReportTime(const TimeOfDay(hour: 20, minute: 45));
      final savedDailyTime = await notif.getDailyReportTime();
      expect(savedDailyTime.hour, 20);
      expect(savedDailyTime.minute, 45);

      // Configure price caution days
      await notif.setPriceCautionDays(45);
      expect(await notif.getPriceCautionDays(), 45);

      await notif.setPriceCautionEnabled(false);
      expect(await notif.isPriceCautionEnabled(), isFalse);
    });
  });
}
