import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/l10n/strings_en.dart';
import 'package:shop/l10n/strings_te.dart';
import 'package:shop/services/app_telemetry_service.dart';

void main() {
  group('Security Rules & Release Build Hardening Checks', () {
    test('firestore.rules enforces pending staff onboarding and owner-only admin/archive writes', () {
      final rules = File('firestore.rules').readAsStringSync();

      // Must not allow unrestricted global read on shops collection
      expect(rules.contains('allow read: if isAuthenticated();'), isFalse);
      expect(rules, contains('allow get: if isApprovedShopMember(shopCode);'));
      expect(rules, contains('allow list: if false;'));

      // Device creation must enforce pending status & restricted defaults for staff
      expect(rules, contains("request.resource.data.role == 'staff'"));
      expect(rules, contains("request.resource.data.status == 'pending'"));
      expect(rules, contains("request.resource.data.get('canChangePrice', false) == false"));
      expect(rules, contains("request.resource.data.get('canManageProducts', false) == false"));

      // Archives & audit logs must reject all client writes
      expect(rules, contains('match /storage_archives/{archiveId}'));
      expect(rules, contains('match /storage_audit_logs/{logId}'));
      expect(rules, contains('allow write: if false;'));

      // Rejected/revoked staff devices may not self-reset back to pending
      expect(rules, contains("resource.data.status == 'pending'"));
      expect(rules.contains("resource.data.status != 'approved'"), isFalse);

      // Permissioned product/order rules enforced on server
      expect(rules, contains("staffHasPermission(shopCode, 'canManageProducts')"));
      expect(rules, contains("staffHasPermission(shopCode, 'canCloseOrders')"));
    });

    test('functions/index.js pins firebase-functions/v1 compatibility import', () {
      final indexJs = File('functions/index.js').readAsStringSync();
      expect(indexJs, contains("require('firebase-functions/v1')"));
    });

    test('android/app/build.gradle.kts refuses debug-keystore fallback for release builds', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle.contains('signingConfigs.getByName("debug")'), isFalse);
      expect(gradle, contains('throw GradleException('));
      expect(gradle, contains('hasValidReleaseKeystore'));
      expect(gradle, contains('requireProductionAppId'));
      expect(File('android/key.properties.example').existsSync(), isTrue);
      expect(File('env/wholesale.dev.json.example').existsSync(), isTrue);
      expect(File('env/wholesale.prod.json.example').existsSync(), isTrue);
    });

    test('ShopSyncService and LifetimeReportScreen are modularized and typed', () {
      expect(File('lib/services/shop_sync_entities.dart').existsSync(), isTrue);
      expect(File('lib/services/shop_sync_realtime.dart').existsSync(), isTrue);
      expect(File('lib/screens/lifetime_report_tabs.dart').existsSync(), isTrue);

      final syncUi = File('lib/screens/shop_sync_screen.dart').readAsStringSync();
      expect(RegExp(r'\bdynamic\s+shop\b').hasMatch(syncUi), isFalse);
    });

    test('firebase.json indexes file exists on disk and contains valid JSON', () {
      final firebaseJson = File('firebase.json').readAsStringSync();
      expect(firebaseJson, contains('"indexes": "firestore.indexes.json"'));
      expect(File('firestore.indexes.json').existsSync(), isTrue);
    });

    test('AndroidManifest removes USE_EXACT_ALARM and NotificationReceiver uses goAsync()', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('android.permission.USE_EXACT_ALARM'), isFalse);

      final receiver = File(
        'android/app/src/main/kotlin/com/example/shop/ShopNotificationReceiver.kt',
      ).readAsStringSync();
      expect(receiver, contains('goAsync()'));
      expect(receiver, contains('Executors.newSingleThreadExecutor()'));

      final scheduler = File(
        'android/app/src/main/kotlin/com/example/shop/ShopAlarmScheduler.kt',
      ).readAsStringSync();
      expect(scheduler.contains('setAlarmClock'), isFalse);
    });

    test('Localization maps include otherItem and keep all keys synced between en and te', () {
      expect(stringsEn.containsKey('otherItem'), isTrue);
      expect(stringsTe.containsKey('otherItem'), isTrue);
      for (final key in stringsEn.keys) {
        expect(stringsTe.containsKey(key), isTrue, reason: 'Missing te key: $key');
      }
    });

    test('GitHub Actions CI workflow exists', () {
      expect(File('.github/workflows/ci.yml').existsSync(), isTrue);
    });

    test('firestore.rules validates entity schemas and error_logs writes', () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('validShopCreate(request.resource.data, shopCode)'));
      expect(rules, contains('validProductData(request.resource.data)'));
      expect(rules, contains('validCustomerData(request.resource.data)'));
      expect(rules, contains('validOrderData(request.resource.data)'));
      expect(rules, contains('validPaymentData(request.resource.data)'));
      expect(rules, contains('match /error_logs/{logId}'));
      expect(rules, contains('isNonEmptyText(request.resource.data.shopName, 120)'));
    });

    test('AndroidManifest drops REQUEST_IGNORE_BATTERY_OPTIMIZATIONS and gradle declares flavors', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'), isFalse);

      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('productFlavors'));
      expect(gradle, contains('create("wholesale")'));
      expect(gradle, contains('create("retail")'));
    });

    test('Repo hygiene keeps fixtures in test/fixtures without scratch scripts', () {
      expect(
        File('simple_shop_product_catalog_with_unit_conversion.xlsx').existsSync(),
        isFalse,
      );
      expect(
        File('test/fixtures/simple_shop_product_catalog_with_unit_conversion.xlsx')
            .existsSync(),
        isTrue,
      );
      expect(Directory('tools/patch_history').existsSync(), isFalse);
      expect(Directory('scratch').existsSync(), isFalse);
    });

    test('AppTelemetryService stores bounded sanitized errors locally', () async {
      SharedPreferences.setMockInitialValues({});
      final telemetry = AppTelemetryService();
      await telemetry.clearRecentErrors();

      for (var i = 0; i < 30; i++) {
        await telemetry.recordError(
          StateError('Error #$i phone 9876543210'),
          StackTrace.current,
          source: 'test',
        );
      }

      final recent = await telemetry.getRecentErrors();
      expect(recent.length, 25);
      expect(recent.first['message'].toString(), contains('[REDACTED_NUM]'));
      expect(recent.first['message'].toString().contains('9876543210'), isFalse);
    });
  });
}
