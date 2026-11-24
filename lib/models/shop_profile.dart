import 'dart:convert';

DateTime? _parseDateTime(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) return val;
  if (val is String) return DateTime.tryParse(val);
  if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
  try {
    final dynamic dyn = val;
    if (dyn.toDate is Function) {
      return dyn.toDate() as DateTime?;
    }
  } catch (_) {
    // Ignored: not a Firestore Timestamp
  }
  return null;
}

class ShopProfile {
  const ShopProfile({
    required this.shopCode,
    required this.shopName,
    this.ownerUid = '',
    this.ownerPhone = '',
    this.ownerName = '',
    this.address = '',
    this.gstin = '',
    this.upiId = '',
    this.digitalStamp = '',
    this.defaultGstRate = 18.0,
    this.role = 'owner', // 'owner' or 'staff'
    this.staffName = 'Counter 1',
    this.status = 'approved', // 'pending', 'approved', 'rejected'
    this.createdAt,
    this.lastSyncedAt,
    this.isCloudEnabled = false,
  });

  final String shopCode;
  final String shopName;
  final String ownerUid;
  final String ownerPhone;
  final String ownerName;
  final String address;
  final String gstin;
  final String upiId;
  final String digitalStamp;
  final double defaultGstRate;
  final String role; // 'owner' or 'staff'
  final String staffName;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime? createdAt;
  final DateTime? lastSyncedAt;
  final bool isCloudEnabled;

  bool get isOwner => role == 'owner';
  bool get isPending => status == 'pending';
  bool get isApproved => status.trim().toLowerCase() == 'approved';
  bool get isRejected => status == 'rejected';

  ShopProfile copyWith({
    String? shopCode,
    String? shopName,
    String? ownerUid,
    String? ownerPhone,
    String? ownerName,
    String? address,
    String? gstin,
    String? upiId,
    String? digitalStamp,
    double? defaultGstRate,
    String? role,
    String? staffName,
    String? status,
    DateTime? createdAt,
    DateTime? lastSyncedAt,
    bool? isCloudEnabled,
  }) {
    return ShopProfile(
      shopCode: shopCode ?? this.shopCode,
      shopName: shopName ?? this.shopName,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      ownerName: ownerName ?? this.ownerName,
      address: address ?? this.address,
      gstin: gstin ?? this.gstin,
      upiId: upiId ?? this.upiId,
      digitalStamp: digitalStamp ?? this.digitalStamp,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      role: role ?? this.role,
      staffName: staffName ?? this.staffName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isCloudEnabled: isCloudEnabled ?? this.isCloudEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shopCode': shopCode,
      'shopName': shopName,
      'ownerUid': ownerUid,
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'address': address,
      'gstin': gstin,
      'upiId': upiId,
      'digitalStamp': digitalStamp,
      'defaultGstRate': defaultGstRate,
      'role': role,
      'staffName': staffName,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isCloudEnabled': isCloudEnabled,
    };
  }

  factory ShopProfile.fromMap(Map<String, dynamic> map) {
    return ShopProfile(
      shopCode: (map['shopCode'] as String? ?? '').trim().toUpperCase(),
      shopName: map['shopName'] as String? ?? 'My Shop',
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerPhone: map['ownerPhone'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      address: map['address'] as String? ?? '',
      gstin: map['gstin'] as String? ?? '',
      upiId: map['upiId'] as String? ?? '',
      digitalStamp: map['digitalStamp'] as String? ?? '',
      defaultGstRate: (map['defaultGstRate'] as num?)?.toDouble() ?? 18.0,
      role: map['role'] as String? ?? 'owner',
      staffName: map['staffName'] as String? ?? 'Counter 1',
      status: map['status'] as String? ?? 'approved',
      createdAt: _parseDateTime(map['createdAt']),
      lastSyncedAt: _parseDateTime(map['lastSyncedAt']),
      isCloudEnabled: map['isCloudEnabled'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ShopProfile.fromJson(String source) =>
      ShopProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class StaffDevice {
  const StaffDevice({
    required this.deviceId,
    required this.staffName,
    this.role = 'staff',
    this.status = 'pending', // 'pending', 'approved', 'rejected'
    this.canChangePrice = true,
    this.canManageProducts = true,
    this.canCloseOrders = true,
    this.canChangeShortcuts = true,
    this.canViewBillTotals = true,
    this.requestedAt,
    this.lastActive,
  });

  final String deviceId;
  final String staffName;
  final String role; // 'owner' or 'staff'
  final String status; // 'pending', 'approved', 'rejected'
  final bool canChangePrice;
  final bool canManageProducts;
  final bool canCloseOrders;
  final bool canChangeShortcuts;
  final bool canViewBillTotals;
  final DateTime? requestedAt;
  final DateTime? lastActive;

  bool get isOwner => role == 'owner';
  bool get isPending => status == 'pending';
  bool get isApproved => status.trim().toLowerCase() == 'approved';
  bool get isRejected => status == 'rejected';

  StaffDevice copyWith({
    String? deviceId,
    String? staffName,
    String? role,
    String? status,
    bool? canChangePrice,
    bool? canManageProducts,
    bool? canCloseOrders,
    bool? canChangeShortcuts,
    bool? canViewBillTotals,
    DateTime? requestedAt,
    DateTime? lastActive,
  }) {
    return StaffDevice(
      deviceId: deviceId ?? this.deviceId,
      staffName: staffName ?? this.staffName,
      role: role ?? this.role,
      status: status ?? this.status,
      canChangePrice: canChangePrice ?? this.canChangePrice,
      canManageProducts: canManageProducts ?? this.canManageProducts,
      canCloseOrders: canCloseOrders ?? this.canCloseOrders,
      canChangeShortcuts: canChangeShortcuts ?? this.canChangeShortcuts,
      canViewBillTotals: canViewBillTotals ?? this.canViewBillTotals,
      requestedAt: requestedAt ?? this.requestedAt,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'staffName': staffName,
      'role': role,
      'status': status,
      'canChangePrice': canChangePrice,
      'canManageProducts': canManageProducts,
      'canCloseOrders': canCloseOrders,
      'canChangeShortcuts': canChangeShortcuts,
      'canViewBillTotals': canViewBillTotals,
      'requestedAt': requestedAt?.toIso8601String(),
      'lastActive': lastActive?.toIso8601String(),
    };
  }

  factory StaffDevice.fromMap(Map<String, dynamic> map) {
    return StaffDevice(
      deviceId: map['deviceId'] as String? ?? '',
      staffName: map['staffName'] as String? ?? 'Staff Counter',
      role: map['role'] as String? ?? 'staff',
      status: map['status'] as String? ?? 'approved',
      canChangePrice: map['canChangePrice'] as bool? ?? true,
      canManageProducts: map['canManageProducts'] as bool? ?? true,
      canCloseOrders: map['canCloseOrders'] as bool? ?? true,
      canChangeShortcuts: map['canChangeShortcuts'] as bool? ?? true,
      canViewBillTotals: map['canViewBillTotals'] as bool? ?? true,
      requestedAt: _parseDateTime(map['requestedAt']),
      lastActive: _parseDateTime(map['lastActive']),
    );
  }
}


