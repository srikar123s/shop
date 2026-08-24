import 'dart:convert';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/order.dart';

class OrderRepository {
  const OrderRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<int> createOrder(DraftOrder draftOrder,
      {double? estimateTotal}) async {
    final db = await _databaseHelper.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final orderId = await txn.insert('orders', {
        'customer_id': draftOrder.customer.id,
        'customer_name_snapshot': draftOrder.customer.name,
        'created_at': now.toIso8601String(),
        'status': orderStatusLabel(OrderStatus.pending),
        'notes': null,
        'estimate_total': estimateTotal ?? draftOrder.estimateTotal ?? 0,
      });

      for (final item in draftOrder.items) {
        final itemStatus = ItemStatus.notGiven;
        final procurementStatus = item.isOtherItem
            ? ProcurementStatus.toProcure
            : ProcurementStatus.notRequired;

        final itemId = await txn.insert('order_items', {
          'order_id': orderId,
          'product_id': item.productId,
          'item_name': item.itemName,
          'quantity_ordered': item.quantity,
          'quantity_given': 0,
          'unit': item.unit,
          'status': itemStatusLabel(itemStatus),
          'is_other_item': item.isOtherItem ? 1 : 0,
          'procurement_status': procurementStatus.name,
          'details': item.description,
          'notes': item.notes,
          'product_snapshot': jsonEncode({
            'itemName': item.itemName,
            'options': item.options,
            'description': item.description,
            'notes': item.notes,
            'unitPrice': item.unitPrice,
            'unitFactor': item.unitFactor,
          }),
        });

        for (final option in item.options.entries) {
          await txn.insert('order_item_options', {
            'order_item_id': itemId,
            'option_name': option.key,
            'option_value': option.value,
          });
        }
      }
      return orderId;
    });
  }

  Future<void> addItemsToOrder({
    required int orderId,
    required List<DraftOrderItem> items,
    double estimateTotalAddition = 0,
  }) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      for (final item in items) {
        final itemId = await txn.insert('order_items', {
          'order_id': orderId,
          'product_id': item.productId,
          'item_name': item.itemName,
          'quantity_ordered': item.quantity,
          'quantity_given': 0,
          'unit': item.unit,
          'status': itemStatusLabel(ItemStatus.notGiven),
          'is_other_item': item.isOtherItem ? 1 : 0,
          'procurement_status': (item.isOtherItem
                  ? ProcurementStatus.toProcure
                  : ProcurementStatus.notRequired)
              .name,
          'details': item.description,
          'notes': item.notes,
          'product_snapshot': jsonEncode({
            'itemName': item.itemName,
            'options': item.options,
            'description': item.description,
            'notes': item.notes,
            'unitPrice': item.unitPrice,
            'unitFactor': item.unitFactor,
          }),
        });
        for (final option in item.options.entries) {
          await txn.insert('order_item_options', {
            'order_item_id': itemId,
            'option_name': option.key,
            'option_value': option.value,
          });
        }
      }
      await txn.update(
        'orders',
        {'status': orderStatusLabel(OrderStatus.partiallyCompleted)},
        where: 'id = ?',
        whereArgs: <Object?>[orderId],
      );
      if (estimateTotalAddition != 0) {
        await txn.rawUpdate(
          'UPDATE orders SET estimate_total = estimate_total + ? WHERE id = ?',
          <Object?>[estimateTotalAddition, orderId],
        );
      }
    });
  }

  Future<List<OrderSummary>> searchOrderSummaries(String query) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim();
    final orderRows = await db.query(
      'orders',
      where: normalized.isEmpty ? null : 'customer_name_snapshot LIKE ?',
      whereArgs: normalized.isEmpty ? null : ['%$normalized%'],
      orderBy: 'created_at DESC',
    );

    final summaries = <OrderSummary>[];
    for (final row in orderRows) {
      final orderId = row['id'] as int;
      final itemRows = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      final statuses = itemRows
          .map((e) => _itemStatusFromLabel(e['status'] as String))
          .toList();
      final pendingCount = statuses.where((s) => s != ItemStatus.given).length;
      final status = _calculateOrderStatus(statuses);
      summaries.add(
        OrderSummary(
          orderId: orderId,
          customerId: row['customer_id'] as int,
          customerName: row['customer_name_snapshot'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          totalItems: itemRows.length,
          pendingCount: pendingCount,
          status: status,
          estimateTotal: (row['estimate_total'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return summaries;
  }

  Future<List<OrderSummary>> getCustomerOrderSummaries(int customerId) async {
    final db = await _databaseHelper.database;
    final customer = await db.query(
      'customers',
      columns: <String>['name'],
      where: 'id = ?',
      whereArgs: <Object?>[customerId],
      limit: 1,
    );
    if (customer.isEmpty) return <OrderSummary>[];
    return searchOrderSummaries(customer.first['name'] as String).then(
      (orders) =>
          orders.where((order) => order.customerId == customerId).toList(),
    );
  }

  Future<void> closePendingOrdersForCustomer(int customerId) async {
    final db = await _databaseHelper.database;
    await db.update(
      'orders',
      {'status': orderStatusLabel(OrderStatus.closed)},
      where: 'customer_id = ? AND status IN (?, ?)',
      whereArgs: <Object?>[
        customerId,
        orderStatusLabel(OrderStatus.pending),
        orderStatusLabel(OrderStatus.partiallyCompleted),
      ],
    );
  }

  Future<void> closeOrder(int orderId) async {
    final db = await _databaseHelper.database;
    await db.update(
      'orders',
      {'status': orderStatusLabel(OrderStatus.closed)},
      where: 'id = ?',
      whereArgs: <Object?>[orderId],
    );
  }

  Future<OrderDetails?> getOrderDetails(int orderId) async {
    final db = await _databaseHelper.database;
    final orderRows = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (orderRows.isEmpty) {
      return null;
    }

    final orderRow = orderRows.first;
    final itemRows = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );

    final items = <OrderItemEntity>[];
    for (final itemRow in itemRows) {
      final itemId = itemRow['id'] as int;
      final optionRows = await db.query(
        'order_item_options',
        where: 'order_item_id = ?',
        whereArgs: [itemId],
        orderBy: 'id ASC',
      );

      items.add(
        OrderItemEntity(
          id: itemId,
          orderId: orderId,
          productId: itemRow['product_id'] as int?,
          itemName: itemRow['item_name'] as String,
          quantityOrdered: (itemRow['quantity_ordered'] as num).toDouble(),
          quantityGiven: (itemRow['quantity_given'] as num).toDouble(),
          unit: itemRow['unit'] as String,
          status: _itemStatusFromLabel(itemRow['status'] as String),
          isOtherItem: (itemRow['is_other_item'] as int) == 1,
          procurementStatus:
              _procurementFromLabel(itemRow['procurement_status'] as String),
          productSnapshot: itemRow['product_snapshot'] as String,
          description: itemRow['details'] as String?,
          notes: itemRow['notes'] as String?,
          options: optionRows
              .map(
                (e) => OrderItemOptionEntity(
                  id: e['id'] as int,
                  orderItemId: itemId,
                  optionName: e['option_name'] as String,
                  optionValue: e['option_value'] as String,
                ),
              )
              .toList(),
        ),
      );
    }

    final order = OrderEntity(
      id: orderId,
      customerId: orderRow['customer_id'] as int,
      customerNameSnapshot: orderRow['customer_name_snapshot'] as String,
      createdAt: DateTime.parse(orderRow['created_at'] as String),
      status: _orderStatusFromLabel(orderRow['status'] as String),
      notes: orderRow['notes'] as String?,
      estimateTotal: (orderRow['estimate_total'] as num?)?.toDouble() ?? 0,
    );

    return OrderDetails(order: order, items: items);
  }

  Future<void> updateOrderFulfillment({
    required int orderId,
    required List<OrderItemEntity> items,
  }) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      for (final item in items) {
        final status =
            _statusFromGiven(item.quantityOrdered, item.quantityGiven);
        final procurement = _procurementFromPending(
          item.isOtherItem,
          item.quantityOrdered,
          item.quantityGiven,
        );
        await txn.update(
          'order_items',
          {
            'quantity_given': item.quantityGiven,
            'status': itemStatusLabel(status),
            'procurement_status': procurement.name,
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }

      final statuses = items
          .map((e) => _statusFromGiven(e.quantityOrdered, e.quantityGiven))
          .toList();

      await txn.update(
        'orders',
        {'status': orderStatusLabel(_calculateOrderStatus(statuses))},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  ItemStatus _statusFromGiven(double ordered, double given) {
    if (given <= 0) {
      return ItemStatus.notGiven;
    }
    if (given >= ordered) {
      return ItemStatus.given;
    }
    return ItemStatus.partial;
  }

  ProcurementStatus _procurementFromPending(
    bool isOther,
    double ordered,
    double given,
  ) {
    if (ordered - given > 0 || isOther) {
      return ProcurementStatus.toProcure;
    }
    return ProcurementStatus.notRequired;
  }

  ItemStatus _itemStatusFromLabel(String label) {
    switch (label) {
      case 'GIVEN':
        return ItemStatus.given;
      case 'PARTIAL':
        return ItemStatus.partial;
      default:
        return ItemStatus.notGiven;
    }
  }

  ProcurementStatus _procurementFromLabel(String label) {
    if (label.toLowerCase() == ProcurementStatus.toProcure.name.toLowerCase()) {
      return ProcurementStatus.toProcure;
    }
    return ProcurementStatus.notRequired;
  }

  OrderStatus _orderStatusFromLabel(String label) {
    switch (label) {
      case 'COMPLETED':
        return OrderStatus.completed;
      case 'PARTIALLY COMPLETED':
        return OrderStatus.partiallyCompleted;
      case 'CLOSED':
        return OrderStatus.closed;
      default:
        return OrderStatus.pending;
    }
  }

  OrderStatus _calculateOrderStatus(List<ItemStatus> statuses) {
    if (statuses.isEmpty) {
      return OrderStatus.pending;
    }
    if (statuses.every((s) => s == ItemStatus.given)) {
      return OrderStatus.completed;
    }
    if (statuses.every((s) => s == ItemStatus.notGiven)) {
      return OrderStatus.pending;
    }
    return OrderStatus.partiallyCompleted;
  }
}
