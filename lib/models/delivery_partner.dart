import 'dart:convert';

enum DeliveryTxType { perBox, line, payout }

String deliveryTxTypeToDb(DeliveryTxType type) {
  switch (type) {
    case DeliveryTxType.perBox:
      return 'per_box';
    case DeliveryTxType.line:
      return 'line';
    case DeliveryTxType.payout:
      return 'payout';
  }
}

DeliveryTxType deliveryTxTypeFromDb(String? raw) {
  switch (raw) {
    case 'per_box':
      return DeliveryTxType.perBox;
    case 'line':
      return DeliveryTxType.line;
    case 'payout':
    default:
      return DeliveryTxType.payout;
  }
}

class BoxRateTier {
  const BoxRateTier({
    required this.boxes,
    required this.rate,
  });

  final int boxes;
  final double rate;

  double get subtotal => boxes * rate;

  Map<String, dynamic> toMap() => {
        'boxes': boxes,
        'rate': rate,
      };

  factory BoxRateTier.fromMap(Map<String, dynamic> map) {
    return BoxRateTier(
      boxes: (map['boxes'] as num?)?.toInt() ?? 0,
      rate: (map['rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DeliveryPartner {
  const DeliveryPartner({
    this.id,
    this.cloudPartnerId,
    required this.name,
    this.phone,
    this.vehicleInfo,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    this.totalEarned = 0.0,
    this.totalPaid = 0.0,
    this.txCount = 0,
    this.lastTxAt,
  });

  final int? id;
  final String? cloudPartnerId;
  final String name;
  final String? phone;
  final String? vehicleInfo;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  /// Summary fields populated by ledger queries
  final double totalEarned;
  final double totalPaid;
  final int txCount;
  final DateTime? lastTxAt;

  /// Positive = shop owes driver (Payable).
  /// Negative = driver has Advance with them.
  double get balance => totalEarned - totalPaid;

  double get advanceBalance => balance < 0 ? -balance : 0.0;

  double get payableBalance => balance > 0 ? balance : 0.0;

  DeliveryPartner copyWith({
    int? id,
    String? cloudPartnerId,
    String? name,
    String? phone,
    String? vehicleInfo,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    double? totalEarned,
    double? totalPaid,
    int? txCount,
    DateTime? lastTxAt,
  }) {
    return DeliveryPartner(
      id: id ?? this.id,
      cloudPartnerId: cloudPartnerId ?? this.cloudPartnerId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      totalEarned: totalEarned ?? this.totalEarned,
      totalPaid: totalPaid ?? this.totalPaid,
      txCount: txCount ?? this.txCount,
      lastTxAt: lastTxAt ?? this.lastTxAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'cloud_partner_id': cloudPartnerId,
        'name': name,
        'phone': phone,
        'vehicle_info': vehicleInfo,
        'notes': notes,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory DeliveryPartner.fromMap(Map<String, Object?> map) {
    return DeliveryPartner(
      id: (map['id'] as num?)?.toInt(),
      cloudPartnerId: map['cloud_partner_id'] as String?,
      name: (map['name'] as String?)?.trim() ?? 'Delivery Partner',
      phone: map['phone'] as String?,
      vehicleInfo: map['vehicle_info'] as String?,
      notes: map['notes'] as String?,
      isActive: ((map['is_active'] as num?)?.toInt() ?? 1) == 1,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
              DateTime.now(),
      totalEarned: (map['total_earned'] as num?)?.toDouble() ?? 0.0,
      totalPaid: (map['total_paid'] as num?)?.toDouble() ?? 0.0,
      txCount: (map['tx_count'] as num?)?.toInt() ?? 0,
      lastTxAt: map['last_tx_at'] != null
          ? DateTime.tryParse(map['last_tx_at'].toString())
          : null,
    );
  }
}

class DeliveryTransaction {
  const DeliveryTransaction({
    this.id,
    this.cloudTxId,
    required this.partnerId,
    required this.txType,
    this.location,
    this.totalBoxes = 0,
    this.rateTiers = const [],
    this.earnedAmount = 0.0,
    this.paidAmount = 0.0,
    this.cutAmount = 0.0,
    this.paymentMode = 'none',
    this.description,
    required this.createdAt,
  });

  final int? id;
  final String? cloudTxId;
  final int partnerId;
  final DeliveryTxType txType;
  final String? location;
  final int totalBoxes;
  final List<BoxRateTier> rateTiers;
  final double earnedAmount;
  final double paidAmount;
  final double cutAmount;
  final String paymentMode;
  final String? description;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'cloud_tx_id': cloudTxId,
        'partner_id': partnerId,
        'tx_type': deliveryTxTypeToDb(txType),
        'location': location,
        'total_boxes': totalBoxes,
        'rate_breakdown_json': rateTiers.isEmpty
            ? null
            : jsonEncode(rateTiers.map((e) => e.toMap()).toList()),
        'earned_amount': earnedAmount,
        'paid_amount': paidAmount,
        'cut_amount': cutAmount,
        'payment_mode': paymentMode,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };

  factory DeliveryTransaction.fromMap(Map<String, Object?> map) {
    final rawJson = map['rate_breakdown_json'] as String?;
    List<BoxRateTier> tiers = const [];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        tiers = decoded
            .whereType<Map<String, dynamic>>()
            .map(BoxRateTier.fromMap)
            .toList();
      } catch (_) {}
    }

    return DeliveryTransaction(
      id: (map['id'] as num?)?.toInt(),
      cloudTxId: map['cloud_tx_id'] as String?,
      partnerId: (map['partner_id'] as num?)?.toInt() ?? 0,
      txType: deliveryTxTypeFromDb(map['tx_type'] as String?),
      location: map['location'] as String?,
      totalBoxes: (map['total_boxes'] as num?)?.toInt() ?? 0,
      rateTiers: tiers,
      earnedAmount: (map['earned_amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      cutAmount: (map['cut_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode: (map['payment_mode'] as String?) ?? 'none',
      description: map['description'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
