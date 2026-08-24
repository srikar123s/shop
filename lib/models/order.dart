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

class DraftOrder {
  DraftOrder(
      {required this.customer, List<DraftOrderItem>? items, this.estimateTotal})
      : items = items ?? <DraftOrderItem>[];

  final Customer customer;
  final List<DraftOrderItem> items;
  final double? estimateTotal;
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
}

class OrderEntity {
  const OrderEntity({
    this.id,
    required this.customerId,
    required this.customerNameSnapshot,
    required this.createdAt,
    required this.status,
    this.notes,
    this.estimateTotal = 0,
  });

  final int? id;
  final int customerId;
  final String customerNameSnapshot;
  final DateTime createdAt;
  final OrderStatus status;
  final String? notes;
  final double estimateTotal;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'customer_name_snapshot': customerNameSnapshot,
      'created_at': createdAt.toIso8601String(),
      'status': orderStatusLabel(status),
      'notes': notes,
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

  OrderItemEntity copyWith({
    double? quantityGiven,
    ItemStatus? status,
    ProcurementStatus? procurementStatus,
  }) {
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
      productSnapshot: productSnapshot,
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
    required this.createdAt,
    required this.totalItems,
    required this.pendingCount,
    required this.status,
  });

  final int orderId;
  final int customerId;
  final String customerName;
  final DateTime createdAt;
  final int totalItems;
  final int pendingCount;
  final OrderStatus status;
}

class OrderDetails {
  const OrderDetails({required this.order, required this.items});

  final OrderEntity order;
  final List<OrderItemEntity> items;
}
