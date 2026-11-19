import 'dart:convert';
import 'package:shop/models/customer.dart';


enum ItemStatus { given, partial, notGiven }

enum OrderStatus { pending, partiallyCompleted, completed, closed }

enum ProcurementStatus { notRequired, toProcure }

String itemStatusLabel(ItemStatus status) {
  switch (status) {
    case ItemStatus.given:
      return 'GIVEN';
    case ItemStatus.partial:
      return 'PARTIAL';
    case ItemStatus.notGiven:
      return 'NOT GIVEN';
  }
}

String orderStatusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return 'PENDING';
    case OrderStatus.partiallyCompleted:
      return 'PARTIALLY COMPLETED';
    case OrderStatus.completed:
      return 'COMPLETED';
    case OrderStatus.closed:
      return 'CLOSED';
  }
}

class OtherCharge {
  const OtherCharge({
    required this.name,
    required this.amount,
  });

  final String name;
  final double amount;

  OtherCharge copyWith({
    String? name,
    double? amount,
  }) {
    return OtherCharge(
      name: name ?? this.name,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'amount': amount,
  };

  factory OtherCharge.fromMap(Map<String, dynamic> map) {
    return OtherCharge(
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class BillBreakdown {
  const BillBreakdown({
    required this.subtotal,
    this.applyGst = false,
    this.gstRate = 18.0,
    this.gstAmount = 0.0,
    this.otherCharges = const <OtherCharge>[],
    this.otherChargesTotal = 0.0,
    this.applyDiscount = false,
    this.discountType = 'flat', // 'flat' or 'percent'
    this.discountValue = 0.0,
    this.discountAmount = 0.0,
    required this.grandTotal,
    this.note,
    this.customerPhone,
    this.takenBy,
  });

  final double subtotal;
  final bool applyGst;
  final double gstRate;
  final double gstAmount;
  final List<OtherCharge> otherCharges;
  final double otherChargesTotal;
  final bool applyDiscount;
  final String discountType;
  final double discountValue;
  final double discountAmount;
  final double grandTotal;
  final String? note;
  final String? customerPhone;
  final String? takenBy;

  BillBreakdown copyWith({
    double? subtotal,
    bool? applyGst,
    double? gstRate,
    double? gstAmount,
    List<OtherCharge>? otherCharges,
    double? otherChargesTotal,
    bool? applyDiscount,
    String? discountType,
    double? discountValue,
    double? discountAmount,
    double? grandTotal,
    String? note,
    String? customerPhone,
    String? takenBy,
  }) {
    return BillBreakdown(
      subtotal: subtotal ?? this.subtotal,
      applyGst: applyGst ?? this.applyGst,
      gstRate: gstRate ?? this.gstRate,
      gstAmount: gstAmount ?? this.gstAmount,
      otherCharges: otherCharges ?? this.otherCharges,
      otherChargesTotal: otherChargesTotal ?? this.otherChargesTotal,
      applyDiscount: applyDiscount ?? this.applyDiscount,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      discountAmount: discountAmount ?? this.discountAmount,
      grandTotal: grandTotal ?? this.grandTotal,
      note: note ?? this.note,
      customerPhone: customerPhone ?? this.customerPhone,
      takenBy: takenBy ?? this.takenBy,
    );
  }

  factory BillBreakdown.calculate({
    required double subtotal,
    bool applyGst = false,
    double gstRate = 18.0,
    List<OtherCharge> otherCharges = const <OtherCharge>[],
    bool applyDiscount = false,
    String discountType = 'flat',
    double discountValue = 0.0,
    double? grandTotalOverride,
    String? note,
    String? customerPhone,
    String? takenBy,
  }) {
    final discount = applyDiscount
        ? (discountType == 'percent'
            ? (subtotal * discountValue / 100.0)
            : discountValue)
        : 0.0;
    final taxableOrNet = (subtotal - discount).clamp(0.0, double.infinity);
    final gst = applyGst ? (taxableOrNet * gstRate / 100.0) : 0.0;
    final otherTotal =
        otherCharges.fold<double>(0.0, (sum, c) => sum + c.amount);
    final calculatedGrandTotal =
        (taxableOrNet + gst + otherTotal).clamp(0.0, double.infinity);
    return BillBreakdown(
      subtotal: subtotal,
      applyGst: applyGst,
      gstRate: gstRate,
      gstAmount: gst,
      otherCharges: otherCharges,
      otherChargesTotal: otherTotal,
      applyDiscount: applyDiscount,
      discountType: discountType,
      discountValue: discountValue,
      discountAmount: discount,
      grandTotal: grandTotalOverride ?? calculatedGrandTotal,
      note: note,
      customerPhone: customerPhone,
      takenBy: takenBy,
    );
  }

  Map<String, dynamic> toMap() => {
    'subtotal': subtotal,
    'applyGst': applyGst,
    'gstRate': gstRate,
    'gstAmount': gstAmount,
    'otherCharges': otherCharges.map((e) => e.toMap()).toList(),
    'otherChargesTotal': otherChargesTotal,
    'applyDiscount': applyDiscount,
    'discountType': discountType,
    'discountValue': discountValue,
    'discountAmount': discountAmount,
    'grandTotal': grandTotal,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (customerPhone != null && customerPhone!.isNotEmpty) 'customerPhone': customerPhone,
    if (takenBy != null && takenBy!.isNotEmpty) 'takenBy': takenBy,
  };

  factory BillBreakdown.fromMap(Map<String, dynamic> map) {
    final otherChargesList = (map['otherCharges'] as List<dynamic>? ?? [])
        .map((e) => OtherCharge.fromMap(e as Map<String, dynamic>))
        .toList();
    final sub = (map['subtotal'] as num?)?.toDouble() ?? 0.0;
    final hasDisc = map['applyDiscount'] as bool? ?? false;
    final dType = map['discountType'] as String? ?? 'flat';
    final dVal = (map['discountValue'] as num?)?.toDouble() ?? 0.0;
    final dAmt = (map['discountAmount'] as num?)?.toDouble() ??
        (hasDisc
            ? (dType == 'percent' ? (sub * dVal / 100.0) : dVal)
            : 0.0);

    return BillBreakdown(
      subtotal: sub,
      applyGst: map['applyGst'] as bool? ?? false,
      gstRate: (map['gstRate'] as num?)?.toDouble() ?? 18.0,
      gstAmount: (map['gstAmount'] as num?)?.toDouble() ?? 0.0,
      otherCharges: otherChargesList,
      otherChargesTotal: (map['otherChargesTotal'] as num?)?.toDouble() ??
          otherChargesList.fold<double>(0.0, (sum, c) => sum + c.amount),
      applyDiscount: hasDisc,
      discountType: dType,
      discountValue: dVal,
      discountAmount: dAmt,
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0.0,
      note: map['note'] as String?,
      customerPhone: map['customerPhone'] as String?,
      takenBy: map['takenBy'] as String?,
    );
  }

  static BillBreakdown? fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('subtotal') ||
            decoded.containsKey('applyGst') ||
            decoded.containsKey('otherCharges') ||
            decoded.containsKey('applyDiscount') ||
            decoded.containsKey('note')) {
          return BillBreakdown.fromMap(decoded);
        }
      }
    } catch (_) {}
    return null;
  }
}

class DraftOrder {
  DraftOrder({
    required this.customer,
    List<DraftOrderItem>? items,
    this.estimateTotal,
    this.applyGst = false,
    this.gstRate = 18.0,
    List<OtherCharge>? otherCharges,
    this.applyDiscount = false,
    this.discountType = 'flat',
    this.discountValue = 0.0,
  })  : items = items ?? <DraftOrderItem>[],
        otherCharges = otherCharges ?? <OtherCharge>[];

  final Customer customer;
  final List<DraftOrderItem> items;
  final double? estimateTotal;
  final bool applyGst;
  final double gstRate;
  final List<OtherCharge> otherCharges;
  final bool applyDiscount;
  final String discountType;
  final double discountValue;

  DraftOrder copyWith({
    Customer? customer,
    List<DraftOrderItem>? items,
    double? estimateTotal,
    bool? applyGst,
    double? gstRate,
    List<OtherCharge>? otherCharges,
    bool? applyDiscount,
    String? discountType,
    double? discountValue,
  }) {
    return DraftOrder(
      customer: customer ?? this.customer,
      items: items ?? this.items,
      estimateTotal: estimateTotal ?? this.estimateTotal,
      applyGst: applyGst ?? this.applyGst,
      gstRate: gstRate ?? this.gstRate,
      otherCharges: otherCharges ?? this.otherCharges,
      applyDiscount: applyDiscount ?? this.applyDiscount,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customer': customer.toMap(),
      'items': items.map((e) => e.toMap()).toList(),
      'estimateTotal': estimateTotal,
      'applyGst': applyGst,
      'gstRate': gstRate,
      'otherCharges': otherCharges.map((e) => e.toMap()).toList(),
      'applyDiscount': applyDiscount,
      'discountType': discountType,
      'discountValue': discountValue,
    };
  }

  factory DraftOrder.fromMap(Map<String, dynamic> map) {
    return DraftOrder(
      customer: Customer.fromMap(map['customer'] as Map<String, dynamic>),
      items: (map['items'] as List<dynamic>? ?? [])
          .map((e) => DraftOrderItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      estimateTotal: (map['estimateTotal'] as num?)?.toDouble(),
      applyGst: map['applyGst'] as bool? ?? false,
      gstRate: (map['gstRate'] as num?)?.toDouble() ?? 18.0,
      otherCharges: (map['otherCharges'] as List<dynamic>? ?? [])
          .map((e) => OtherCharge.fromMap(e as Map<String, dynamic>))
          .toList(),
      applyDiscount: map['applyDiscount'] as bool? ?? false,
      discountType: map['discountType'] as String? ?? 'flat',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DraftOrderItem {
  DraftOrderItem({
    this.productId,
    required this.itemName,
    required this.options,
    required this.quantity,
    required this.unit,
    this.isOtherItem = false,
    this.description,
    this.notes,
    this.unitPrice,
    this.unitFactor = 1,
  });

  final int? productId;
  final String itemName;
  final Map<String, String> options;
  final double quantity;
  final String unit;
  final bool isOtherItem;
  final String? description;
  final String? notes;
  final double? unitPrice;
  final double unitFactor;

  DraftOrderItem copyWith({
    int? productId,
    String? itemName,
    Map<String, String>? options,
    double? quantity,
    String? unit,
    bool? isOtherItem,
    String? description,
    String? notes,
    double? unitPrice,
    double? unitFactor,
  }) {
    return DraftOrderItem(
      productId: productId ?? this.productId,
      itemName: itemName ?? this.itemName,
      options: options ?? this.options,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      isOtherItem: isOtherItem ?? this.isOtherItem,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      unitPrice: unitPrice ?? this.unitPrice,
      unitFactor: unitFactor ?? this.unitFactor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'itemName': itemName,
      'options': options,
      'quantity': quantity,
      'unit': unit,
      'isOtherItem': isOtherItem,
      'description': description,
      'notes': notes,
      'unitPrice': unitPrice,
      'unitFactor': unitFactor,
    };
  }

  factory DraftOrderItem.fromMap(Map<String, dynamic> map) {
    return DraftOrderItem(
      productId: map['productId'] as int?,
      itemName: map['itemName'] as String,
      options: (map['options'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      isOtherItem: map['isOtherItem'] as bool? ?? false,
      description: map['description'] as String?,
      notes: map['notes'] as String?,
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      unitFactor: (map['unitFactor'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class OrderEntity {
  const OrderEntity({
    this.id,
    required this.customerId,
    required this.customerNameSnapshot,
    this.customerPhone,
    this.takenBy,
    required this.createdAt,
    required this.status,
    this.notes,
    this.estimateTotal = 0,
    this.paidAmount = 0,
    this.paymentMode = 'unpaid',
    this.paymentStatus = 'unpaid',
  });

  final int? id;
  final int customerId;
  final String customerNameSnapshot;
  final String? customerPhone;
  final String? takenBy;
  final DateTime createdAt;
  final OrderStatus status;
  final String? notes;
  final double estimateTotal;
  final double paidAmount;
  final String paymentMode;
  final String paymentStatus;

  String get formattedOrderId =>
      id != null ? '#ORD-${id.toString().padLeft(4, '0')}' : '#ORD-NEW';

  BillBreakdown? get billBreakdown => BillBreakdown.fromJsonString(notes);

  double get dueAmount => (estimateTotal - paidAmount).clamp(0, double.infinity);
  bool get isFullyPaid => dueAmount <= 0.01 && estimateTotal > 0;

  OrderEntity copyWith({
    int? id,
    int? customerId,
    String? customerNameSnapshot,
    String? customerPhone,
    String? takenBy,
    DateTime? createdAt,
    OrderStatus? status,
    String? notes,
    double? estimateTotal,
    double? paidAmount,
    String? paymentMode,
    String? paymentStatus,
  }) {
    return OrderEntity(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerNameSnapshot: customerNameSnapshot ?? this.customerNameSnapshot,
      customerPhone: customerPhone ?? this.customerPhone,
      takenBy: takenBy ?? this.takenBy,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      estimateTotal: estimateTotal ?? this.estimateTotal,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentMode: paymentMode ?? this.paymentMode,
      paymentStatus: paymentStatus ?? this.paymentStatus,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'customer_name_snapshot': customerNameSnapshot,
      'customer_phone': customerPhone,
      'taken_by': takenBy,
      'created_at': createdAt.toIso8601String(),
      'status': orderStatusLabel(status),
      'notes': notes,
      'estimate_total': estimateTotal,
      'paid_amount': paidAmount,
      'payment_mode': paymentMode,
      'payment_status': paymentStatus,
    };
  }
}

class OrderItemEntity {
  const OrderItemEntity({
    this.id,
    required this.orderId,
    this.productId,
    required this.itemName,
    required this.quantityOrdered,
    required this.quantityGiven,
    required this.unit,
    required this.status,
    required this.isOtherItem,
    required this.procurementStatus,
    required this.productSnapshot,
    this.description,
    this.notes,
    this.options = const <OrderItemOptionEntity>[],
  });

  final int? id;
  final int orderId;
  final int? productId;
  final String itemName;
  final double quantityOrdered;
  final double quantityGiven;
  final String unit;
  final ItemStatus status;
  final bool isOtherItem;
  final ProcurementStatus procurementStatus;
  final String productSnapshot;
  final String? description;
  final String? notes;
  final List<OrderItemOptionEntity> options;

  double get quantityPending => quantityOrdered - quantityGiven;

  double get unitPrice {
    try {
      final map = jsonDecode(productSnapshot) as Map<String, dynamic>;
      if (map.containsKey('unitPrice') && map['unitPrice'] != null) {
        return (map['unitPrice'] as num).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  OrderItemEntity copyWith({
    double? quantityGiven,
    ItemStatus? status,
    ProcurementStatus? procurementStatus,
    double? unitPrice,
  }) {
    String updatedSnapshot = productSnapshot;
    if (unitPrice != null) {
      try {
        final map = jsonDecode(productSnapshot) as Map<String, dynamic>;
        map['unitPrice'] = unitPrice;
        updatedSnapshot = jsonEncode(map);
      } catch (_) {}
    }
    return OrderItemEntity(
      id: id,
      orderId: orderId,
      productId: productId,
      itemName: itemName,
      quantityOrdered: quantityOrdered,
      quantityGiven: quantityGiven ?? this.quantityGiven,
      unit: unit,
      status: status ?? this.status,
      isOtherItem: isOtherItem,
      procurementStatus: procurementStatus ?? this.procurementStatus,
      productSnapshot: updatedSnapshot,
      description: description,
      notes: notes,
      options: options,
    );
  }
}


class OrderItemOptionEntity {
  const OrderItemOptionEntity({
    this.id,
    required this.orderItemId,
    required this.optionName,
    required this.optionValue,
  });

  final int? id;
  final int orderItemId;
  final String optionName;
  final String optionValue;
}

class OrderSummary {
  const OrderSummary({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.takenBy,
    required this.createdAt,
    required this.totalItems,
    required this.pendingCount,
    required this.status,
    this.estimateTotal = 0,
    this.paidAmount = 0.0,
    this.paymentMode,
    this.paymentStatus,
  });

  final int orderId;
  final int customerId;
  final String customerName;
  final String? customerPhone;
  final String? takenBy;
  final DateTime createdAt;
  final int totalItems;
  final int pendingCount;
  final OrderStatus status;
  final double estimateTotal;
  final double paidAmount;
  final String? paymentMode;
  final String? paymentStatus;

  double get dueAmount =>
      (estimateTotal - paidAmount).clamp(0.0, double.infinity);
  bool get isFullyPaid => estimateTotal > 0 && paidAmount >= estimateTotal;

  String get formattedOrderId => '#ORD-${orderId.toString().padLeft(4, '0')}';
}

class OrderDetails {
  const OrderDetails({required this.order, required this.items});

  final OrderEntity order;
  final List<OrderItemEntity> items;
}

class ProcurementItem {
  const ProcurementItem({
    required this.itemId,
    required this.orderId,
    required this.customerName,
    this.customerPhone,
    required this.takenBy,
    required this.createdAt,
    required this.itemName,
    required this.unit,
    required this.quantityOrdered,
    required this.quantityGiven,
    required this.unitPrice,
    this.options = const [],
    this.productSnapshot = '',
  });

  final int itemId;
  final int orderId;
  final String customerName;
  final String? customerPhone;
  final String takenBy;
  final DateTime createdAt;
  final String itemName;
  final String unit;
  final double quantityOrdered;
  final double quantityGiven;
  final double unitPrice;
  final List<String> options;
  final String productSnapshot;

  double get quantityPending =>
      (quantityOrdered - quantityGiven).clamp(0.0, double.infinity);
  String get formattedOrderId => '#ORD-${orderId.toString().padLeft(4, '0')}';
}
