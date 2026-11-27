import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/order.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:sqflite/sqflite.dart';

class OrderRepository {
  const OrderRepository(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  double _extractRowUnitPrice(Map<String, Object?> row) {
    var unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
    if (unitPrice <= 0.0) {
      final snapRaw = row['product_snapshot'] as String?;
      if (snapRaw != null && snapRaw.isNotEmpty) {
        try {
          final snapMap = jsonDecode(snapRaw);
          if (snapMap is Map) {
            unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (_) {}
      }
    }
    return unitPrice;
  }

  Future<int> createOrder(
    DraftOrder draftOrder, {
    double? estimateTotal,
    BillBreakdown? billBreakdown,
    String? takenBy,
  }) async {
    final db = await _databaseHelper.database;
    int localMaxHint = 0;
    try {
      final maxRows = await db.rawQuery(
        'SELECT MAX(COALESCE(order_number, id)) as max_num FROM orders',
      );
      if (maxRows.isNotEmpty && maxRows.first['max_num'] != null) {
        localMaxHint = (maxRows.first['max_num'] as num).toInt();
      }
    } catch (_) {}

    // Allocate cloud order number BEFORE acquiring SQLite's exclusive write lock
    final cloudOrderNumber = await ShopSyncService.instance
        .allocateCloudOrderNumber(localMaxHint: localMaxHint);

    final createdOrderId = await db.transaction((txn) async {
      final now = DateTime.now();
      final effectiveTakenBy =
          takenBy ?? ShopSyncService.instance.currentUserOrDeviceName;
      final phone = draftOrder.customer.phone;

      final notes = billBreakdown != null
          ? jsonEncode(billBreakdown
              .copyWith(
                customerPhone: phone,
                takenBy: effectiveTakenBy,
              )
              .toMap())
          : (draftOrder.applyGst ||
                  draftOrder.otherCharges.isNotEmpty ||
                  draftOrder.applyDiscount)
              ? jsonEncode(BillBreakdown.calculate(
                  subtotal: draftOrder.items.fold<double>(
                      0, (sum, i) => sum + (i.unitPrice ?? 0) * i.quantity),
                  applyGst: draftOrder.applyGst,
                  gstRate: draftOrder.gstRate,
                  otherCharges: draftOrder.otherCharges,
                  applyDiscount: draftOrder.applyDiscount,
                  discountType: draftOrder.discountType,
                  discountValue: draftOrder.discountValue,
                  grandTotalOverride: estimateTotal ?? draftOrder.estimateTotal,
                  customerPhone: phone,
                  takenBy: effectiveTakenBy,
                ).toMap())
              : jsonEncode(BillBreakdown.calculate(
                  subtotal: draftOrder.items.fold<double>(
                      0, (sum, i) => sum + (i.unitPrice ?? 0) * i.quantity),
                  customerPhone: phone,
                  takenBy: effectiveTakenBy,
                ).toMap());

      final calculatedSubtotal = draftOrder.items.fold<double>(
          0, (sum, i) => sum + (i.unitPrice ?? 0) * i.quantity);
      final calculatedGrandTotal = billBreakdown?.grandTotal ?? calculatedSubtotal;

      int nextOrderNumber;
      if (cloudOrderNumber != null && cloudOrderNumber > 0) {
        nextOrderNumber = cloudOrderNumber;
      } else {
        final txnMaxRows = await txn.rawQuery(
          'SELECT MAX(COALESCE(order_number, id)) as max_num FROM orders',
        );
        final txnLocalMax =
            (txnMaxRows.isNotEmpty && txnMaxRows.first['max_num'] != null)
                ? (txnMaxRows.first['max_num'] as num).toInt()
                : 0;
        nextOrderNumber = txnLocalMax + 1;
      }

      final orderId = await txn.insert('orders', {
        'order_number': nextOrderNumber,
        'customer_id': draftOrder.customer.id,
        'customer_name_snapshot': draftOrder.customer.name,
        'customer_phone': phone,
        'taken_by': effectiveTakenBy,
        'created_at': now.toIso8601String(),
        'status': orderStatusLabel(OrderStatus.pending),
        'notes': notes,
        'estimate_total': estimateTotal ?? draftOrder.estimateTotal ?? calculatedGrandTotal,
      });

      for (final item in draftOrder.items) {
        final itemStatus = ItemStatus.notGiven;
        const procurementStatus = ProcurementStatus.notRequired;

        final itemId = await txn.insert('order_items', {
          'order_id': orderId,
          'product_id': item.productId,
          'item_name': item.itemName,
          'quantity_ordered': item.quantity,
          'quantity_given': 0,
          'unit': item.unit,
          'unit_price': item.unitPrice ?? 0.0,
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

    unawaited(ShopSyncService.instance.syncOrder(createdOrderId).catchError((e) {
      debugPrint('Error syncing order in createOrder: $e');
    }));
    return createdOrderId;
  }

  Future<void> addItemsToOrder({
    required int orderId,
    required List<DraftOrderItem> items,
    double estimateTotalAddition = 0,
    BillBreakdown? billBreakdown,
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
          'unit_price': item.unitPrice ?? 0.0,
          'status': itemStatusLabel(ItemStatus.notGiven),
          'is_other_item': item.isOtherItem ? 1 : 0,
          'procurement_status': ProcurementStatus.notRequired.name,
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

      // Query all items for this order to calculate the complete combined subtotal
      final allItemRows = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: <Object?>[orderId],
      );
      double combinedSubtotal = 0.0;
      for (final row in allItemRows) {
        final qty = (row['quantity_ordered'] as num).toDouble();
        combinedSubtotal += _extractRowUnitPrice(row) * qty;
      }

      final combinedBreakdown = billBreakdown != null
          ? BillBreakdown.calculate(
              subtotal: combinedSubtotal,
              applyGst: billBreakdown.applyGst,
              gstRate: billBreakdown.gstRate,
              otherCharges: billBreakdown.otherCharges,
              applyDiscount: billBreakdown.applyDiscount,
              discountType: billBreakdown.discountType,
              discountValue: billBreakdown.discountValue,
              note: billBreakdown.note,
            )
          : null;

      // Fetch existing order info to retain status, phone and takenBy
      final orderRow = await txn.query(
        'orders',
        columns: ['status', 'notes', 'customer_phone', 'taken_by'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      final currentStatus = orderRow.isNotEmpty ? orderRow.first['status'] as String? : null;
      final existingNotes = orderRow.isNotEmpty ? orderRow.first['notes'] as String? : null;
      final existingBd = BillBreakdown.fromJsonString(existingNotes);

      final anyGiven = allItemRows.any((r) => ((r['quantity_given'] as num?)?.toDouble() ?? 0.0) > 0);
      final newStatus = anyGiven
          ? orderStatusLabel(OrderStatus.partiallyCompleted)
          : (currentStatus ?? orderStatusLabel(OrderStatus.pending));

      final orderUpdateData = <String, Object?>{
        'status': newStatus,
      };
      if (combinedBreakdown != null) {
        final mergedBreakdown = combinedBreakdown.copyWith(
          customerPhone: existingBd?.customerPhone ?? (orderRow.isNotEmpty ? orderRow.first['customer_phone'] as String? : null),
          takenBy: existingBd?.takenBy ?? (orderRow.isNotEmpty ? orderRow.first['taken_by'] as String? : null),
        );
        orderUpdateData['notes'] = jsonEncode(mergedBreakdown.toMap());
        orderUpdateData['estimate_total'] = mergedBreakdown.grandTotal;
      } else if (estimateTotalAddition != 0) {
        await txn.rawUpdate(
          'UPDATE orders SET estimate_total = estimate_total + ? WHERE id = ?',
          <Object?>[estimateTotalAddition, orderId],
        );
      }
      await txn.update(
        'orders',
        orderUpdateData,
        where: 'id = ?',
        whereArgs: <Object?>[orderId],
      );
    });
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in addItemsToOrder: $e');
    }));
  }

  Future<List<OrderSummary>> searchOrderSummaries(String query) async {
    final db = await _databaseHelper.database;
    final normalized = query.trim();
    final orderRows = await db.rawQuery('''
      SELECT o.*, c.address as customer_address
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      ${normalized.isEmpty ? '' : 'WHERE o.customer_name_snapshot LIKE ?'}
      ORDER BY o.created_at DESC
    ''', normalized.isEmpty ? null : ['%$normalized%']);

    final orderIds = orderRows.map((r) => r['id'] as int).toList();
    final itemsByOrderId = <int, List<Map<String, Object?>>>{};
    for (var i = 0; i < orderIds.length; i += 400) {
      final chunk = orderIds.sublist(
        i,
        i + 400 > orderIds.length ? orderIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final itemRows = await db.query(
        'order_items',
        where: 'order_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final itemRow in itemRows) {
        final oid = itemRow['order_id'] as int;
        itemsByOrderId.putIfAbsent(oid, () => []).add(itemRow);
      }
    }

    final summaries = <OrderSummary>[];
    for (final row in orderRows) {
      final orderId = row['id'] as int;
      final notes = row['notes'] as String?;
      final breakdown = BillBreakdown.fromJsonString(notes);
      final customerPhone =
          (row['customer_phone'] as String?) ?? breakdown?.customerPhone;
      final customerAddress = (row['customer_address'] as String?)?.trim();
      final rawTakenBy = (row['taken_by'] as String?) ?? breakdown?.takenBy;
      final takenBy = (rawTakenBy != null &&
              rawTakenBy.trim().isNotEmpty &&
              rawTakenBy.trim() != 'Store')
          ? rawTakenBy.trim()
          : ShopSyncService.instance.currentUserOrDeviceName;

      final itemRows = itemsByOrderId[orderId] ?? const <Map<String, Object?>>[];
      final statuses = itemRows
          .map((e) => _itemStatusFromLabel(e['status'] as String))
          .toList();
      final pendingCount = statuses.where((s) => s != ItemStatus.given).length;
      final rawDbStatus = row['status'] as String? ?? '';
      final dbStatus = _orderStatusFromLabel(rawDbStatus);
      final status = (dbStatus == OrderStatus.completed || dbStatus == OrderStatus.closed)
          ? dbStatus
          : _calculateOrderStatus(statuses);

      final unfulfilledItems = <String>[];
      for (final item in itemRows) {
        final ordered = (item['quantity_ordered'] as num).toDouble();
        final given = (item['quantity_given'] as num?)?.toDouble() ?? 0.0;
        final pending = ordered - given;
        if (pending > 0.001) {
          final name = item['item_name'] as String;
          final unit = (item['unit'] as String?) ?? 'pcs';
          final pStr = pending % 1 == 0 ? pending.toInt().toString() : pending.toString();
          unfulfilledItems.add('$name ($pStr $unit)');
        }
      }

      summaries.add(
        OrderSummary(
          orderId: orderId,
          orderNumber: (row['order_number'] as num?)?.toInt(),
          customerId: row['customer_id'] as int,
          customerName: row['customer_name_snapshot'] as String,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          takenBy: takenBy,
          createdAt: DateTime.parse(row['created_at'] as String),
          totalItems: itemRows.length,
          pendingCount: pendingCount,
          status: status,
          estimateTotal: (row['estimate_total'] as num?)?.toDouble() ?? 0,
          paidAmount: (row['paid_amount'] as num?)?.toDouble() ?? 0.0,
          paymentMode: row['payment_mode'] as String?,
          paymentStatus: row['payment_status'] as String?,
          unfulfilledItemNames: unfulfilledItems,
          deliveryPartnerName: row['delivery_partner_name'] as String?,
          boxCount: (row['box_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return summaries;
  }

  Future<List<OrderSummary>> getCustomerOrderSummaries(
    int customerId, {
    String? customerName,
    String? customerPhone,
  }) async {
    final all = await searchOrderSummaries('');
    final cleanPhone =
        customerPhone?.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    final lowerName = customerName?.trim().toLowerCase();

    return all.where((o) {
      if (cleanPhone != null && cleanPhone.isNotEmpty) {
        final orderPhone =
            o.customerPhone?.replaceAll(RegExp(r'[^0-9+]'), '').trim();
        if (orderPhone != null && orderPhone.isNotEmpty) {
          return orderPhone == cleanPhone;
        }
      }
      if (lowerName != null && lowerName.isNotEmpty) {
        if (o.customerName.trim().toLowerCase() == lowerName) {
          final orderPhone =
              o.customerPhone?.replaceAll(RegExp(r'[^0-9+]'), '').trim();
          if (cleanPhone == null ||
              cleanPhone.isEmpty ||
              orderPhone == null ||
              orderPhone.isEmpty ||
              orderPhone == cleanPhone) {
            return true;
          }
        }
      }
      return o.customerId == customerId;
    }).toList();
  }

  Future<void> closePendingOrdersForCustomer(int customerId, {bool adjustToGivenOnly = false}) async {
    final db = await _databaseHelper.database;
    final pendingOrders = await db.query(
      'orders',
      columns: ['id'],
      where: 'customer_id = ? AND status IN (?, ?)',
      whereArgs: [
        customerId,
        orderStatusLabel(OrderStatus.pending),
        orderStatusLabel(OrderStatus.partiallyCompleted),
      ],
    );
    for (final row in pendingOrders) {
      final orderId = row['id'] as int;
      if (adjustToGivenOnly) {
        await closeOrderWithDeliveredItemsOnly(orderId: orderId);
      } else {
        await closeOrderWithAllGiven(orderId);
      }
    }
  }

  /// Closes an order by marking ALL items as given (100% delivered) and setting full bill.
  Future<void> closeOrderWithAllGiven(int orderId) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      double fullSubtotal = 0;
      for (final row in itemRows) {
        final itemId = row['id'] as int;
        final ordered = (row['quantity_ordered'] as num).toDouble();
        double unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
        if (unitPrice <= 0.0) {
          final snapRaw = row['product_snapshot'] as String?;
          if (snapRaw != null && snapRaw.isNotEmpty) {
            try {
              final snapMap = jsonDecode(snapRaw) as Map<String, dynamic>;
              unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
            } catch (_) {}
          }
        }
        fullSubtotal += unitPrice * ordered;

        await txn.update(
          'order_items',
          {
            'quantity_given': ordered,
            'status': itemStatusLabel(ItemStatus.given),
            'procurement_status': ProcurementStatus.notRequired.name,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }

      final orderRows = await txn.query(
        'orders',
        columns: ['notes'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      final existingNotes = orderRows.isNotEmpty ? orderRows.first['notes'] as String? : null;
      final existingBreakdown = BillBreakdown.fromJsonString(existingNotes);

      BillBreakdown newBreakdown;
      if (existingBreakdown != null) {
        newBreakdown = BillBreakdown.calculate(
          subtotal: fullSubtotal,
          applyGst: existingBreakdown.applyGst,
          gstRate: existingBreakdown.gstRate,
          otherCharges: existingBreakdown.otherCharges,
          applyDiscount: existingBreakdown.applyDiscount,
          discountType: existingBreakdown.discountType,
          discountValue: existingBreakdown.discountValue,
          customerPhone: existingBreakdown.customerPhone,
          takenBy: existingBreakdown.takenBy,
          note: existingBreakdown.note ?? 'All items marked as delivered and completed.',
        );
      } else {
        newBreakdown = BillBreakdown.calculate(
          subtotal: fullSubtotal,
          note: 'All items marked as delivered and completed.',
        );
      }

      await txn.update(
        'orders',
        {
          'status': orderStatusLabel(OrderStatus.completed),
          'estimate_total': newBreakdown.grandTotal,
          'notes': jsonEncode(newBreakdown.toMap()),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in addItemsToOrder: $e');
    }));
  }

  /// Closes an order billing ONLY the items that were actually given.
  /// Any unfulfilled shortage remains out of stock and goes to the Procurement List.
  /// Customer is billed strictly for delivered goods.
  Future<void> closeOrderWithDeliveredItemsOnly({
    required int orderId,
    String? note,
  }) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      double deliveredSubtotal = 0;
      final procuredParts = <String>[];

      for (final row in itemRows) {
        final itemId = row['id'] as int;
        final ordered = (row['quantity_ordered'] as num).toDouble();
        final given = (row['quantity_given'] as num).toDouble();
        double unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
        if (unitPrice <= 0.0) {
          final snapRaw = row['product_snapshot'] as String?;
          if (snapRaw != null && snapRaw.isNotEmpty) {
            try {
              final snapMap = jsonDecode(snapRaw) as Map<String, dynamic>;
              unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
            } catch (_) {}
          }
        }
        final itemName = row['item_name'] as String;

        // Customer is billed ONLY for items actually delivered
        deliveredSubtotal += unitPrice * given;

        if (given < ordered) {
          final shortage = ordered - given;
          final shortStr = shortage % 1 == 0 ? shortage.toInt().toString() : shortage.toString();
          final gvnStr = given % 1 == 0 ? given.toInt().toString() : given.toString();
          final ordStr = ordered % 1 == 0 ? ordered.toInt().toString() : ordered.toString();

          // Out of stock shortage strictly goes to procurement
          procuredParts.add('$itemName ($shortStr to procure)');
          final itemStatus = given > 0 ? ItemStatus.partial : ItemStatus.notGiven;
          await txn.update(
            'order_items',
            {
              'status': itemStatusLabel(itemStatus),
              'procurement_status': ProcurementStatus.toProcure.name,
              'notes': 'Given $gvnStr of $ordStr. Remaining $shortStr in procurement list.',
            },
            where: 'id = ?',
            whereArgs: [itemId],
          );
        } else {
          // Fully delivered
          await txn.update(
            'order_items',
            {
              'status': itemStatusLabel(ItemStatus.given),
              'procurement_status': ProcurementStatus.notRequired.name,
            },
            where: 'id = ?',
            whereArgs: [itemId],
          );
        }
      }

      final orderRows = await txn.query(
        'orders',
        columns: ['notes'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      final existingNotes = orderRows.isNotEmpty ? orderRows.first['notes'] as String? : null;
      final existingBreakdown = BillBreakdown.fromJsonString(existingNotes);

      final auditList = <String>[];
      if (procuredParts.isNotEmpty) {
        auditList.add('To Procure: ${procuredParts.join(', ')}');
      }

      final fullNote = note ?? (auditList.isNotEmpty
          ? 'Closed with partial items delivered. Billed for given goods. ${auditList.join('. ')}'
          : 'Order closed and completed.');

      BillBreakdown newBreakdown;
      if (existingBreakdown != null) {
        newBreakdown = BillBreakdown.calculate(
          subtotal: deliveredSubtotal,
          applyGst: existingBreakdown.applyGst,
          gstRate: existingBreakdown.gstRate,
          otherCharges: existingBreakdown.otherCharges,
          applyDiscount: existingBreakdown.applyDiscount,
          discountType: existingBreakdown.discountType,
          discountValue: existingBreakdown.discountValue,
          note: fullNote,
          customerPhone: existingBreakdown.customerPhone,
          takenBy: existingBreakdown.takenBy,
        );
      } else {
        newBreakdown = BillBreakdown.calculate(
          subtotal: deliveredSubtotal,
          note: fullNote,
        );
      }

      await txn.update(
        'orders',
        {
          'status': orderStatusLabel(OrderStatus.completed),
          'estimate_total': newBreakdown.grandTotal,
          'notes': jsonEncode(newBreakdown.toMap()),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in addItemsToOrder: $e');
    }));
  }

  Future<void> closeOrder(int orderId) async {
    await closeOrderWithAllGiven(orderId);
  }

  Future<void> updateOrderBillBreakdown({
    required int orderId,
    required BillBreakdown billBreakdown,
  }) async {
    final db = await _databaseHelper.database;
    await db.update(
      'orders',
      {
        'estimate_total': billBreakdown.grandTotal,
        'notes': jsonEncode(billBreakdown.toMap()),
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in addItemsToOrder: $e');
    }));
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

      final seenOptionKeys = <String>{};
      final distinctOptions = <OrderItemOptionEntity>[];
      for (final e in optionRows) {
        final optName = (e['option_name'] as String?)?.trim() ?? '';
        final optVal = (e['option_value'] as String?)?.trim() ?? '';
        final key = '${optName.toLowerCase()}:${optVal.toLowerCase()}';
        if (optName.isNotEmpty && seenOptionKeys.add(key)) {
          distinctOptions.add(
            OrderItemOptionEntity(
              id: e['id'] as int,
              orderItemId: itemId,
              optionName: optName,
              optionValue: optVal,
            ),
          );
        }
      }

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
          options: distinctOptions,
        ),
      );
    }

    final notes = orderRow['notes'] as String?;
    final breakdown = BillBreakdown.fromJsonString(notes);
    final customerPhone =
        (orderRow['customer_phone'] as String?) ?? breakdown?.customerPhone;
    final rawTakenBy =
        (orderRow['taken_by'] as String?) ?? breakdown?.takenBy;
    final takenBy = (rawTakenBy != null &&
            rawTakenBy.trim().isNotEmpty &&
            rawTakenBy.trim() != 'Store')
        ? rawTakenBy.trim()
        : ShopSyncService.instance.currentUserOrDeviceName;

    var order = OrderEntity(
      id: orderId,
      orderNumber: (orderRow['order_number'] as num?)?.toInt(),
      customerId: orderRow['customer_id'] as int,
      customerNameSnapshot: orderRow['customer_name_snapshot'] as String,
      customerPhone: customerPhone,
      takenBy: takenBy,
      createdAt: DateTime.parse(orderRow['created_at'] as String),
      status: _orderStatusFromLabel(orderRow['status'] as String),
      notes: notes,
      estimateTotal: (orderRow['estimate_total'] as num?)?.toDouble() ?? 0,
      paidAmount: (orderRow['paid_amount'] as num?)?.toDouble() ?? 0,
      paymentMode: (orderRow['payment_mode'] as String?) ?? 'unpaid',
      paymentStatus: (orderRow['payment_status'] as String?) ?? 'unpaid',
      deliveryPartnerName: orderRow['delivery_partner_name'] as String?,
      boxCount: (orderRow['box_count'] as num?)?.toInt() ?? 0,
    );

    // Auto-heal if billBreakdown subtotal is 0 but items have non-zero prices
    final hasItemsWithPrices = items.any((i) => i.unitPrice > 0);
    if (hasItemsWithPrices && (breakdown == null || breakdown.subtotal == 0)) {
      double correctedSubtotal = 0;
      if (order.status == OrderStatus.completed) {
        final hasGiven = items.any((i) => i.quantityGiven > 0);
        if (hasGiven) {
          correctedSubtotal = items.fold(0.0, (sum, i) => sum + i.unitPrice * i.quantityGiven);
        } else {
          correctedSubtotal = items.fold(0.0, (sum, i) => sum + i.unitPrice * i.quantityOrdered);
        }
      } else {
        correctedSubtotal = items.fold(0.0, (sum, i) => sum + i.unitPrice * i.quantityOrdered);
      }

      if (correctedSubtotal > 0) {
        final healedBreakdown = BillBreakdown.calculate(
          subtotal: correctedSubtotal,
          applyGst: breakdown?.applyGst ?? false,
          gstRate: breakdown?.gstRate ?? 18.0,
          otherCharges: breakdown?.otherCharges ?? const [],
          note: breakdown?.note,
        );

        order = order.copyWith(
          estimateTotal: healedBreakdown.grandTotal,
          notes: jsonEncode(healedBreakdown.toMap()),
        );

        unawaited(db.update(
          'orders',
          {
            'estimate_total': healedBreakdown.grandTotal,
            'notes': jsonEncode(healedBreakdown.toMap()),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        ).then((_) {
          ShopSyncService.instance.syncOrder(orderId).catchError((e) {
            debugPrint('Error syncing healed order: $e');
          });
        }).catchError((e) {
          debugPrint('Error updating healed order: $e');
        }));
      }
    }

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
        final notGiven = item.quantityOrdered - item.quantityGiven;
        final procurement = notGiven > 0.001
            ? ProcurementStatus.toProcure
            : ProcurementStatus.notRequired;
        await txn.update(
          'order_items',
          {
            'quantity_given': item.quantityGiven,
            'unit_price': item.unitPrice,
            'status': itemStatusLabel(status),
            'procurement_status': procurement.name,
            'product_snapshot': item.productSnapshot,
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }

      // Fetch all items belonging to this order to calculate true ordered total and status
      final allDbItems = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      double orderedSubtotal = 0;
      final allStatuses = <ItemStatus>[];
      for (final row in allDbItems) {
        final qGiven = (row['quantity_given'] as num?)?.toDouble() ?? 0.0;
        final qOrd = (row['quantity_ordered'] as num?)?.toDouble() ?? 0.0;
        final uPrice = _extractRowUnitPrice(row);
        orderedSubtotal += uPrice * qOrd;
        allStatuses.add(_statusFromGiven(qOrd, qGiven));
      }

      final calculatedStatus = _calculateOrderStatus(allStatuses);
      final updateData = <String, Object?>{
        'status': orderStatusLabel(calculatedStatus),
      };

      final orderRows = await txn.query('orders',
          columns: ['notes', 'estimate_total'],
          where: 'id = ?',
          whereArgs: [orderId]);
      if (orderRows.isNotEmpty) {
        final existingNotes = orderRows.first['notes'] as String?;
        final existingEstimate =
            (orderRows.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
        final existingBreakdown = BillBreakdown.fromJsonString(existingNotes);
        if (existingBreakdown != null) {
          final calcWithoutOverride = BillBreakdown.calculate(
            subtotal: existingBreakdown.subtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
            applyDiscount: existingBreakdown.applyDiscount,
            discountType: existingBreakdown.discountType,
            discountValue: existingBreakdown.discountValue,
          ).grandTotal;
          final hadManualOverride =
              (existingEstimate - calcWithoutOverride).abs() > 0.01;
          final orderedChanged =
              (orderedSubtotal - existingBreakdown.subtotal).abs() > 0.01;

          final updatedBreakdown = BillBreakdown.calculate(
            subtotal: orderedSubtotal,
            applyGst: existingBreakdown.applyGst,
            gstRate: existingBreakdown.gstRate,
            otherCharges: existingBreakdown.otherCharges,
            applyDiscount: existingBreakdown.applyDiscount,
            discountType: existingBreakdown.discountType,
            discountValue: existingBreakdown.discountValue,
            grandTotalOverride:
                (hadManualOverride && !orderedChanged) ? existingEstimate : null,
            customerPhone: existingBreakdown.customerPhone,
            takenBy: existingBreakdown.takenBy,
            note: existingBreakdown.note,
          );
          updateData['notes'] = jsonEncode(updatedBreakdown.toMap());
          updateData['estimate_total'] = updatedBreakdown.grandTotal;
        } else if (orderedSubtotal > 0) {
          updateData['estimate_total'] = orderedSubtotal;
        }
      }

      await txn.update(
        'orders',
        updateData,
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order: $e');
    }));
  }


  Future<List<ProcurementItem>> getProcurementItems({String query = ''}) async {
    final db = await _databaseHelper.database;
    final results = await db.rawQuery('''
      SELECT 
        oi.id as item_id,
        oi.order_id,
        oi.item_name,
        oi.unit,
        oi.unit_price,
        oi.quantity_ordered,
        oi.quantity_given,
        oi.product_snapshot,
        o.order_number,
        o.customer_name_snapshot,
        o.customer_phone,
        o.taken_by,
        o.created_at,
        o.notes as order_notes,
        c.address as customer_address
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      LEFT JOIN customers c ON o.customer_id = c.id
      WHERE LOWER(oi.procurement_status) = 'toprocure'
        AND (oi.quantity_ordered - oi.quantity_given) > 0
      ORDER BY o.created_at ASC
    ''');

    final itemIds = results.map((r) => r['item_id'] as int).toList();
    final optionsByItemId = <int, List<String>>{};
    for (var i = 0; i < itemIds.length; i += 400) {
      final chunk = itemIds.sublist(
        i,
        i + 400 > itemIds.length ? itemIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final optRows = await db.query(
        'order_item_options',
        where: 'order_item_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final o in optRows) {
        final oid = o['order_item_id'] as int;
        optionsByItemId
            .putIfAbsent(oid, () => [])
            .add('${o['option_name']}: ${o['option_value']}');
      }
    }

    final result = <ProcurementItem>[];
    for (final row in results) {
      final orderId = row['order_id'] as int;
      final itemId = row['item_id'] as int;
      final orderNumber = (row['order_number'] as num?)?.toInt();
      final customerName =
          (row['customer_name_snapshot'] as String?) ?? 'Customer';
      final orderNotes = row['order_notes'] as String?;
      final breakdown = BillBreakdown.fromJsonString(orderNotes);
      final customerPhone =
          (row['customer_phone'] as String?) ?? breakdown?.customerPhone;
      final customerAddress = (row['customer_address'] as String?)?.trim();
      final rawTakenBy =
          (row['taken_by'] as String?) ?? breakdown?.takenBy;
      final takenBy = (rawTakenBy != null &&
              rawTakenBy.trim().isNotEmpty &&
              rawTakenBy.trim() != 'Store')
          ? rawTakenBy.trim()
          : ShopSyncService.instance.currentUserOrDeviceName;
      final createdAt =
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now();

      final options = optionsByItemId[itemId] ?? const <String>[];
      final snapRaw = row['product_snapshot'] as String?;
      final unitPrice = _extractRowUnitPrice(row);

      result.add(
        ProcurementItem(
          itemId: itemId,
          orderId: orderId,
          orderNumber: orderNumber,
          customerName: customerName,
          customerPhone: customerPhone,
          customerAddress: customerAddress,
          takenBy: takenBy,
          createdAt: createdAt,
          itemName: row['item_name'] as String,
          unit: row['unit'] as String,
          quantityOrdered: (row['quantity_ordered'] as num).toDouble(),
          quantityGiven: (row['quantity_given'] as num).toDouble(),
          unitPrice: unitPrice,
          options: options,
          productSnapshot: snapRaw ?? '',
        ),
      );
    }

    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      return result.where((i) =>
        i.itemName.toLowerCase().contains(q) ||
        i.customerName.toLowerCase().contains(q) ||
        i.formattedOrderId.toLowerCase().contains(q)
      ).toList();
    }

    return result;
  }

  Future<({int pendingCount, int oldPendingCount, int toProcureCount})>
      getPendingAndProcurementStats() async {
    final db = await _databaseHelper.database;
    final openOrders = await db.rawQuery('''
      SELECT o.id, o.created_at
      FROM orders o
      WHERE UPPER(o.status) NOT IN ('COMPLETED', 'CLOSED')
        AND EXISTS (
          SELECT 1 FROM order_items oi 
          WHERE oi.order_id = o.id 
            AND LOWER(oi.status) != 'given'
            AND (oi.quantity_ordered - oi.quantity_given) > 0
        )
    ''');

    int pendingCount = openOrders.length;
    int oldPendingCount = 0;
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

    for (final row in openOrders) {
      final dt = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (dt != null && dt.isBefore(threeDaysAgo)) {
        oldPendingCount++;
      }
    }

    final procureRows = await db.rawQuery('''
      SELECT COUNT(oi.id) as count
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      WHERE LOWER(oi.procurement_status) = 'toprocure'
        AND (oi.quantity_ordered - oi.quantity_given) > 0
    ''');
    int toProcureCount = 0;
    if (procureRows.isNotEmpty && procureRows.first['count'] != null) {
      toProcureCount = (procureRows.first['count'] as num).toInt();
    }

    return (
      pendingCount: pendingCount,
      oldPendingCount: oldPendingCount,
      toProcureCount: toProcureCount,
    );
  }

  Future<void> _markItemProcuredInTxn(
    DatabaseExecutor txn, {
    required int itemId,
    required int orderId,
    double? customQuantityGiven,
  }) async {
    final orderRows = await txn.query(
      'orders',
      columns: ['status', 'notes', 'estimate_total'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    final rawOrderStatus =
        orderRows.isNotEmpty ? (orderRows.first['status'] as String? ?? '') : '';
    final existingOrderStatus = _orderStatusFromLabel(rawOrderStatus);
    final wasAlreadyClosed = existingOrderStatus == OrderStatus.completed ||
        existingOrderStatus == OrderStatus.closed;

    final itemRows = await txn.query(
      'order_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    final ordered = itemRows.isNotEmpty
        ? (itemRows.first['quantity_ordered'] as num).toDouble()
        : 0.0;
    final currentGiven = itemRows.isNotEmpty
        ? (itemRows.first['quantity_given'] as num?)?.toDouble() ?? 0.0
        : 0.0;

    if (wasAlreadyClosed && customQuantityGiven == null) {
      // Closed orders already billed only for delivered goods; clear procurement queue flag
      // without changing the customer's closed invoice or delivered quantities.
      await txn.update(
        'order_items',
        {'procurement_status': ProcurementStatus.notRequired.name},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      return;
    }

    final effectiveGiven = customQuantityGiven ?? ordered;
    final status = _statusFromGiven(ordered, effectiveGiven);
    final procurementStatus = effectiveGiven < ordered
        ? ProcurementStatus.toProcure
        : ProcurementStatus.notRequired;

    await txn.update(
      'order_items',
      {
        'procurement_status': procurementStatus.name,
        'quantity_given': effectiveGiven,
        'status': itemStatusLabel(status),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );

    if (wasAlreadyClosed) {
      return;
    }

    final allItems = await txn.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    double orderedSubtotal = 0.0;
    final itemStatuses = <ItemStatus>[];
    for (final i in allItems) {
      final ord = (i['quantity_ordered'] as num?)?.toDouble() ?? 0.0;
      final giv = (i['quantity_given'] as num?)?.toDouble() ?? 0.0;
      orderedSubtotal += _extractRowUnitPrice(i) * ord;
      itemStatuses.add(_statusFromGiven(ord, giv));
    }

    final newOrderStatus = _calculateOrderStatus(itemStatuses);
    final orderUpdates = <String, Object?>{
      'status': orderStatusLabel(newOrderStatus),
    };

    if (orderRows.isNotEmpty) {
      final existingTotal =
          (orderRows.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
      final existingBreakdown =
          BillBreakdown.fromJsonString(orderRows.first['notes'] as String?);
      if ((existingTotal <= 0.01 && orderedSubtotal > 0) ||
          (currentGiven != effectiveGiven &&
              existingBreakdown != null &&
              existingBreakdown.subtotal <= 0.01 &&
              orderedSubtotal > 0)) {
        final restoredBreakdown = existingBreakdown != null
            ? BillBreakdown.calculate(
                subtotal: orderedSubtotal,
                applyGst: existingBreakdown.applyGst,
                gstRate: existingBreakdown.gstRate,
                otherCharges: existingBreakdown.otherCharges,
                applyDiscount: existingBreakdown.applyDiscount,
                discountType: existingBreakdown.discountType,
                discountValue: existingBreakdown.discountValue,
                customerPhone: existingBreakdown.customerPhone,
                takenBy: existingBreakdown.takenBy,
                note: existingBreakdown.note,
              )
            : BillBreakdown.calculate(subtotal: orderedSubtotal);
        orderUpdates['estimate_total'] = restoredBreakdown.grandTotal;
        orderUpdates['notes'] = jsonEncode(restoredBreakdown.toMap());
      }
    }

    await txn.update(
      'orders',
      orderUpdates,
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  /// Marks a specific order item as procured in the procurement list.
  /// Preserves already-closed customer bills; updates open orders accurately.
  Future<void> markItemAsProcured({
    required int itemId,
    required int orderId,
    double? customQuantityGiven,
  }) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await _markItemProcuredInTxn(
        txn,
        itemId: itemId,
        orderId: orderId,
        customQuantityGiven: customQuantityGiven,
      );
    });
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in markItemAsProcured: $e');
    }));
  }

  /// Marks ALL currently pending items across all open orders as procured in a single transaction.
  Future<void> markAllItemsAsProcured() async {
    final items = await getProcurementItems();
    if (items.isEmpty) return;
    final db = await _databaseHelper.database;
    final affectedOrderIds = <int>{};
    await db.transaction((txn) async {
      for (final item in items) {
        await _markItemProcuredInTxn(
          txn,
          itemId: item.itemId,
          orderId: item.orderId,
        );
        affectedOrderIds.add(item.orderId);
      }
    });
    for (final oid in affectedOrderIds) {
      unawaited(ShopSyncService.instance.syncOrder(oid).catchError((e) {
        debugPrint('Error syncing order $oid in markAllItemsAsProcured: $e');
      }));
    }
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

  ItemStatus _itemStatusFromLabel(String label) {
    switch (label.toUpperCase().trim()) {
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
    switch (label.toUpperCase().trim()) {
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
