import 'dart:convert';

class ShopProfile {
  const ShopProfile({
    required this.shopCode,
    required this.shopName,
    this.ownerPhone = '',
    this.ownerName = '',
    this.address = '',
    this.gstin = '',
    this.defaultGstRate = 18.0,
    this.role = 'owner', // 'owner' or 'staff'
    this.staffName = 'Counter 1',
    this.createdAt,
    this.lastSyncedAt,
    this.isCloudEnabled = false,
  });

  final String shopCode;
  final String shopName;
  final String ownerPhone;
  final String ownerName;
  final String address;
  final String gstin;
  final double defaultGstRate;
  final String role; // 'owner' or 'staff'
  final String staffName;
  final DateTime? createdAt;
  final DateTime? lastSyncedAt;
  final bool isCloudEnabled;

  bool get isOwner => role == 'owner';

  ShopProfile copyWith({
    String? shopCode,
    String? shopName,
    String? ownerPhone,
    String? ownerName,
    String? address,
    String? gstin,
    double? defaultGstRate,
    String? role,
    String? staffName,
    DateTime? createdAt,
    DateTime? lastSyncedAt,
    bool? isCloudEnabled,
  }) {
    return ShopProfile(
      shopCode: shopCode ?? this.shopCode,
      shopName: shopName ?? this.shopName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      ownerName: ownerName ?? this.ownerName,
      address: address ?? this.address,
      gstin: gstin ?? this.gstin,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      role: role ?? this.role,
      staffName: staffName ?? this.staffName,
      createdAt: createdAt ?? this.createdAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isCloudEnabled: isCloudEnabled ?? this.isCloudEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shopCode': shopCode,
      'shopName': shopName,
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'address': address,
      'gstin': gstin,
      'defaultGstRate': defaultGstRate,
      'role': role,
      'staffName': staffName,
      'createdAt': createdAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isCloudEnabled': isCloudEnabled,
    };
  }

  factory ShopProfile.fromMap(Map<String, dynamic> map) {
    return ShopProfile(
      shopCode: (map['shopCode'] as String? ?? '').trim().toUpperCase(),
      shopName: map['shopName'] as String? ?? 'My Shop',
      ownerPhone: map['ownerPhone'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      address: map['address'] as String? ?? '',
      gstin: map['gstin'] as String? ?? '',
      defaultGstRate: (map['defaultGstRate'] as num?)?.toDouble() ?? 18.0,
      role: map['role'] as String? ?? 'owner',
      staffName: map['staffName'] as String? ?? 'Counter 1',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'] as String)
          : null,
      isCloudEnabled: map['isCloudEnabled'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ShopProfile.fromJson(String source) =>
      ShopProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

