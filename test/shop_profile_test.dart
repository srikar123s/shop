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

    test('StaffDevice serializes and deserializes with permissions correctly', () {
      final device = StaffDevice(
        deviceId: 'dev_949369',
        staffName: 'Sridevi',
        role: 'staff',
        status: 'pending',
        canChangePrice: false,
        canManageProducts: false,
        canCloseOrders: true,
        canChangeShortcuts: false,
        canViewBillTotals: true,
        lastActive: DateTime(2026, 11, 15, 1, 0),
      );

      final map = device.toMap();
      expect(map['deviceId'], 'dev_949369');
      expect(map['staffName'], 'Sridevi');
      expect(map['status'], 'pending');
      expect(map['canChangePrice'], isFalse);
      expect(map['canManageProducts'], isFalse);
      expect(map['canCloseOrders'], isTrue);
      expect(map['canChangeShortcuts'], isFalse);
      expect(map['canViewBillTotals'], isTrue);

      final restored = StaffDevice.fromMap(map);
      expect(restored.deviceId, 'dev_949369');
      expect(restored.isPending, isTrue);
      expect(restored.isApproved, isFalse);
      expect(restored.canChangePrice, isFalse);
      expect(restored.canManageProducts, isFalse);
      expect(restored.canCloseOrders, isTrue);
      expect(restored.canChangeShortcuts, isFalse);
      expect(restored.canViewBillTotals, isTrue);
      expect(restored.isOwner, isFalse);
    });

    test('StaffDevice handles simulated Timestamp object safely', () {
      final dummyMap = {
        'deviceId': 'dev_123456',
        'staffName': 'Counter 1',
        'role': 'staff',
        'status': 'pending',
        // Object with toDate method like Firestore Timestamp
        'lastActive': _FakeTimestamp(DateTime(2026, 11, 15, 12, 0)),
      };

      final device = StaffDevice.fromMap(dummyMap);
      expect(device.deviceId, 'dev_123456');
      expect(device.lastActive, equals(DateTime(2026, 11, 15, 12, 0)));
      expect(device.isPending, isTrue);
    });
  });
}

class _FakeTimestamp {
  _FakeTimestamp(this._dt);
  final DateTime _dt;
  DateTime toDate() => _dt;
}

