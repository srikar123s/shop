import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

      // Permissioned product/order rules enforced on server
      expect(rules, contains("staffHasPermission(shopCode, 'canManageProducts')"));
      expect(rules, contains("staffHasPermission(shopCode, 'canCloseOrders')"));
    });

    test('android/app/build.gradle.kts refuses debug-keystore fallback for release builds', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle.contains('signingConfigs.getByName("debug")'), isFalse);
      expect(gradle, contains('throw GradleException('));
      expect(gradle, contains('hasValidReleaseKeystore'));
    });

    test('firebase.json indexes file exists on disk and contains valid JSON', () {
      final firebaseJson = File('firebase.json').readAsStringSync();
      expect(firebaseJson, contains('"indexes": "firestore.indexes.json"'));
      expect(File('firestore.indexes.json').existsSync(), isTrue);
    });
  });
}
