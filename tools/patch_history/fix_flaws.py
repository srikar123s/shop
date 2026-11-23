import sys

# 1. Update database_helper.dart
path_db = r'lib\database\database_helper.dart'
with open(path_db, 'r', encoding='utf-8') as f:
    cdb = f.read()

target_rop = """    final total = (order.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
    final status = paidAmount >= total
        ? 'paid'
        : (paidAmount > 0 ? 'partial' : 'unpaid');

    await db.update(
      'orders',
      {
        'paid_amount': paidAmount,
        'payment_mode': paymentMode,
        'payment_status': status,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }"""

rep_rop = """    final total = (order.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
    final prevPaid = (order.first['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final status = paidAmount >= total
        ? 'paid'
        : (paidAmount > 0 ? 'partial' : 'unpaid');

    await db.update(
      'orders',
      {
        'paid_amount': paidAmount,
        'payment_mode': paymentMode,
        'payment_status': status,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );

    final added = paidAmount - prevPaid;
    final customerId = order.first['customer_id'] as int?;
    if (added > 0.001 && customerId != null) {
      final now = DateTime.now().toIso8601String();
      await db.insert('customer_payments', {
        'customer_id': customerId,
        'amount': added,
        'payment_mode': paymentMode.toLowerCase(),
        'notes': 'Payment for Order #ORD-${orderId.toString().padLeft(4, "0")}',
        'created_at': now,
      });
    }
  }"""

target_gcs = """    final row = res.first;
    final limit = (row['credit_limit'] as num?)?.toDouble() ?? 0.0;
    final due = (row['balance_due'] as num?)?.toDouble() ?? 0.0;
    final finalDue = due > 0.01 ? due : 0.0;
    final isOver = limit > 0 && finalDue > limit;
    final available = limit > 0 ? (limit - finalDue) : 0.0;
    return {
      'credit_limit': limit,
      'balance_due': finalDue,
      'is_over_limit': isOver,
      'available_credit': available,
    };"""

rep_gcs = """    final row = res.first;
    final limit = (row['credit_limit'] as num?)?.toDouble() ?? 0.0;
    final due = (row['balance_due'] as num?)?.toDouble() ?? 0.0;
    final finalDue = due > 0.01 ? due : 0.0;
    final advanceCredit = due < -0.01 ? (-due) : 0.0;
    final isOver = limit > 0 && finalDue > limit;
    final available = limit > 0 ? (limit - finalDue) : 0.0;
    return {
      'credit_limit': limit,
      'balance_due': finalDue,
      'advance_credit': advanceCredit,
      'is_over_limit': isOver,
      'available_credit': available,
    };"""

assert target_rop in cdb, "target_rop not found"
assert target_gcs in cdb, "target_gcs not found"

cdb = cdb.replace(target_rop, rep_rop, 1)
cdb = cdb.replace(target_gcs, rep_gcs, 1)

with open(path_db, 'w', encoding='utf-8') as f:
    f.write(cdb)
print("database_helper updated successfully")


# 2. Update order_repository.dart
path_repo = r'lib\repositories\order_repository.dart'
with open(path_repo, 'r', encoding='utf-8') as f:
    crepo = f.read()

target_sos_status = """      final pendingCount = statuses.where((s) => s != ItemStatus.given).length;
      final status = _calculateOrderStatus(statuses);"""

rep_sos_status = """      final pendingCount = statuses.where((s) => s != ItemStatus.given).length;
      final rawDbStatus = row['status'] as String? ?? '';
      final dbStatus = _orderStatusFromLabel(rawDbStatus);
      final status = (dbStatus == OrderStatus.completed || dbStatus == OrderStatus.closed)
          ? dbStatus
          : _calculateOrderStatus(statuses);"""

target_pstats = """    final openOrders = await db.query(
      'orders',
      where: "UPPER(status) NOT IN ('COMPLETED', 'CLOSED')",
    );

    int pendingCount = openOrders.length;
    int oldPendingCount = 0;
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));

    for (final row in openOrders) {
      final dt = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (dt != null && dt.isBefore(threeDaysAgo)) {
        oldPendingCount++;
      }
    }"""

rep_pstats = """    final openOrders = await db.rawQuery('''
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
    }"""

assert target_sos_status in crepo, "target_sos_status not found"
assert target_pstats in crepo, "target_pstats not found"

crepo = crepo.replace(target_sos_status, rep_sos_status, 1)
crepo = crepo.replace(target_pstats, rep_pstats, 1)

with open(path_repo, 'w', encoding='utf-8') as f:
    f.write(crepo)
print("order_repository updated successfully")
