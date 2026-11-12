import 'package:flutter_test/flutter_test.dart';
import 'package:shop/models/shop_profile.dart';

void main() {
  group('ShopProfile Model & Synchronization Tests', () {
    test('ShopProfile serializes to and from Map correctly', () {
      final profile = ShopProfile(
        shopCode: 'SH-8492',
        shopName: 'Srikar Hardware & Paints',
        ownerName: 'Srikar',
        ownerPhone: '9876543210',
        address: 'Main Road, Market',
        gstin: '36AAAAA0000A1Z5',
        defaultGstRate: 18.0,
        role: 'owner',
        staffName: 'Master Device',
        createdAt: DateTime(2026, 11, 13, 1, 0),
        lastSyncedAt: DateTime(2026, 11, 13, 2, 0),
        isCloudEnabled: true,
      );

      final map = profile.toMap();
      expect(map['shopCode'], equals('SH-8492'));
      expect(map['shopName'], equals('Srikar Hardware & Paints'));
      expect(map['ownerPhone'], equals('9876543210'));
      expect(map['role'], equals('owner'));
      expect(map['isCloudEnabled'], isTrue);

      final fromMap = ShopProfile.fromMap(map);
      expect(fromMap.shopCode, equals('SH-8492'));
      expect(fromMap.shopName, equals(profile.shopName));
      expect(fromMap.ownerPhone, equals(profile.ownerPhone));
      expect(fromMap.role, equals(profile.role));
      expect(fromMap.isOwner, isTrue);
    });

    test('Staff profile joins with staff role', () {
      final ownerProfile = ShopProfile(
        shopCode: 'SH-1234',
        shopName: 'Srikar Hardware',
        ownerName: 'Srikar',
        ownerPhone: '9876543210',
        role: 'owner',
      );

      final staffProfile = ownerProfile.copyWith(
        role: 'staff',
        staffName: 'Counter 2',
      );

      expect(staffProfile.isOwner, isFalse);
      expect(staffProfile.role, equals('staff'));
      expect(staffProfile.staffName, equals('Counter 2'));
      expect(staffProfile.shopCode, equals('SH-1234'));
    });
  });
}

