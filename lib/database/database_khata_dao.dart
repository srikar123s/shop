part of 'database_helper.dart';

/// Khata billing, credit limits, and ledger persistence methods.
extension DatabaseKhataDao on DatabaseHelper {
  Future<void> recordOrderPayment({
    required int orderId,
    required double paidAmount,
    required String paymentMode,
  }) async {
    final db = await database;
    int? newPaymentId;
    await db.transaction((txn) async {
      final order =
          await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (order.isEmpty) return;
      final total = (order.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
      final prevPaid = (order.first['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final status = paidAmount >= total
          ? 'paid'
          : (paidAmount > 0 ? 'partial' : 'unpaid');

      await txn.update(
        'orders',
        {
          'paid_amount': paidAmount,
          'payment_mode': paymentMode,
          'payment_status': status,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      final added = paidAmount - prevPaid;
      final customerId = order.first['customer_id'] as int?;
      final displayNum = (order.first['order_number'] as num?)?.toInt() ?? orderId;
      if (added > 0.001 && customerId != null) {
        final now = DateTime.now().toIso8601String();
        newPaymentId = await txn.insert('customer_payments', {
          'customer_id': customerId,
          'amount': added,
          'payment_mode': paymentMode.toLowerCase(),
          'notes': 'Payment for Order #ORD-${displayNum.toString().padLeft(4, "0")}',
          'created_at': now,
        });
      } else if (added < -0.001 && customerId != null) {
        // Compensating adjustment for payment reduction / refund
        final now = DateTime.now().toIso8601String();
        newPaymentId = await txn.insert('customer_payments', {
          'customer_id': customerId,
          'amount': added,
          'payment_mode': paymentMode.toLowerCase(),
          'notes': 'Refund/Adjustment for Order #ORD-${displayNum.toString().padLeft(4, "0")}',
          'created_at': now,
        });
      }
    });

    if (newPaymentId != null) {
      unawaited(ShopSyncService.instance.syncPayment(newPaymentId!).catchError((e) {
        debugPrint('Error syncing payment in recordOrderPayment: $e');
      }));
    }
    unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
      debugPrint('Error syncing order in recordOrderPayment: $e');
    }));
  }

  Future<void> recordCustomerKhataPayment({
    required int customerId,
    required double amount,
    required String paymentMode,
    String? notes,
  }) async {
    final db = await database;
    int? createdPaymentId;
    final syncedOrderIds = <int>{};
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      createdPaymentId = await txn.insert('customer_payments', {
        'customer_id': customerId,
        'amount': amount,
        'payment_mode': paymentMode,
        'notes': notes,
        'created_at': now,
      });

      // Apply payment to oldest pending/partial orders first
      final unpaidOrders = await txn.query(
        'orders',
        where: "deleted_at IS NULL AND customer_id = ? AND estimate_total > paid_amount AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')",
        whereArgs: [customerId],
        orderBy: 'created_at ASC',
      );

      double remainingToApply = amount;
      for (final row in unpaidOrders) {
        if (remainingToApply <= 0) break;
        final orderId = row['id'] as int;
        final total = (row['estimate_total'] as num?)?.toDouble() ?? 0.0;
        final alreadyPaid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final due = total - alreadyPaid;

        if (due > 0) {
          final payingForThis =
              remainingToApply >= due ? due : remainingToApply;
          final newPaid = alreadyPaid + payingForThis;
          final newStatus = newPaid >= total ? 'paid' : 'partial';

          final existingMode =
              (row['payment_mode'] as String?)?.trim().toLowerCase() ?? '';
          final newModeLower = paymentMode.trim().toLowerCase();
          final resolvedMode = (alreadyPaid > 0.001 &&
                  existingMode.isNotEmpty &&
                  existingMode != 'unpaid' &&
                  existingMode != 'khata' &&
                  existingMode != newModeLower)
              ? 'split'
              : paymentMode;

          await txn.update(
            'orders',
            {
              'paid_amount': newPaid,
              'payment_status': newStatus,
              'payment_mode': resolvedMode,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [orderId],
          );
          remainingToApply -= payingForThis;
          syncedOrderIds.add(orderId);
        }
      }
    });

    for (final orderId in syncedOrderIds) {
      unawaited(ShopSyncService.instance.syncOrder(orderId).catchError((e) {
        debugPrint('Error syncing order in recordCustomerKhataPayment: $e');
      }));
    }
    if (createdPaymentId != null) {
      unawaited(ShopSyncService.instance.syncPayment(createdPaymentId!).catchError((e) {
        debugPrint('Error syncing payment in recordCustomerKhataPayment: $e');
      }));
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerKhataList() async {
    final db = await database;
    final query = '''
      SELECT 
        c.id as customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        COALESCE(c.address, '') as customer_location,
        COALESCE(c.credit_limit, 0.0) as credit_limit,
        COALESCE(b.total_billed, 0.0) as total_billed,
        COALESCE(p.total_paid, 0.0) as total_paid,
        COALESCE(b.order_count, 0) as order_count,
        b.last_order_date,
        p.last_payment_date,
        p.last_payment_mode,
        b.oldest_unpaid_date
      FROM customers c
      LEFT JOIN (
        SELECT 
          customer_id,
          SUM(estimate_total) as total_billed,
          COUNT(id) as order_count,
          MAX(created_at) as last_order_date,
          MIN(CASE WHEN estimate_total > (paid_amount + 0.01) AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed')) THEN created_at ELSE NULL END) as oldest_unpaid_date
        FROM orders
        WHERE deleted_at IS NULL
          AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')
        GROUP BY customer_id
      ) b ON c.id = b.customer_id
      LEFT JOIN (
        SELECT 
          p1.customer_id,
          SUM(p1.amount) as total_paid,
          MAX(p1.created_at) as last_payment_date,
          (SELECT payment_mode FROM customer_payments p2 WHERE p2.customer_id = p1.customer_id ORDER BY p2.created_at DESC LIMIT 1) as last_payment_mode
        FROM customer_payments p1
        GROUP BY p1.customer_id
      ) p ON c.id = p.customer_id
      WHERE (
          ABS(COALESCE(b.total_billed, 0.0) - COALESCE(p.total_paid, 0.0)) > 0.01 
          OR COALESCE(b.total_billed, 0.0) > 0 
          OR COALESCE(p.total_paid, 0.0) > 0
          OR c.credit_limit > 0
        )
        AND (
          (c.is_active = 1 AND c.deleted_at IS NULL)
          OR ABS(COALESCE(b.total_billed, 0.0) - COALESCE(p.total_paid, 0.0)) > 0.01
        )
      ORDER BY (COALESCE(b.total_billed, 0.0) - COALESCE(p.total_paid, 0.0)) DESC, c.name ASC
    ''';
    final rows = await db.rawQuery(query);
    final now = DateTime.now();

    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      final billed = (map['total_billed'] as num?)?.toDouble() ?? 0.0;
      final paid = (map['total_paid'] as num?)?.toDouble() ?? 0.0;
      final diff = billed - paid;
      final due = (diff.abs() > 0.01) ? diff : 0.0;
      map['balance_due'] = due;

      final oldestDateStr = map['oldest_unpaid_date'] as String?;
      int daysOverdue = 0;
      if (oldestDateStr != null && oldestDateStr.isNotEmpty) {
        final dt = DateTime.tryParse(oldestDateStr);
        if (dt != null) {
          daysOverdue = now.difference(dt).inDays;
          if (daysOverdue < 0) daysOverdue = 0;
        }
      }
      map['days_overdue'] = daysOverdue;

      final limit = (map['credit_limit'] as num?)?.toDouble() ?? 0.0;
      map['credit_limit'] = limit;
      map['is_over_limit'] = limit > 0 && due > limit;
      map['available_credit'] = limit > 0 ? (limit - due) : 0.0;
      return map;
    }).toList();
  }

  /// Returns customer's net Khata balance (billed - paid).
  /// > 0: customer owes money to shop (due).
  /// < 0: customer has advance credit deposited with shop (-balance).
  Future<double> getCustomerKhataBalance(int customerId) async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT 
        COALESCE((
          SELECT SUM(o.estimate_total) 
          FROM orders o 
          WHERE o.customer_id = ? 
            AND o.deleted_at IS NULL
            AND (LOWER(o.status) IN ('completed', 'closed', 'pending', 'partially completed') OR o.notes LIKE '%khata_debit%')
        ), 0.0) - 
        COALESCE((
          SELECT SUM(p.amount) 
          FROM customer_payments p 
          WHERE p.customer_id = ?
        ), 0.0) AS net_balance
    ''', [customerId, customerId]);
    if (res.isNotEmpty) {
      return (res.first['net_balance'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  /// Updates a customer's maximum credit limit (Khata limit)
  Future<void> updateCustomerCreditLimit(int customerId, double creditLimit) async {
    if (creditLimit < 0) {
      throw ArgumentError.value(
        creditLimit,
        'creditLimit',
        'Credit limit cannot be negative',
      );
    }
    final db = await database;
    await db.update(
      'customers',
      {
        'credit_limit': creditLimit,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  /// Checks credit limit vs current balance for an order
  Future<Map<String, dynamic>> getCustomerCreditStatus(int customerId) async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        COALESCE(c.credit_limit, 0.0) as credit_limit,
        (
          COALESCE((
            SELECT SUM(o.estimate_total) 
            FROM orders o 
            WHERE o.customer_id = c.id 
              AND o.deleted_at IS NULL
              AND (LOWER(o.status) IN ('completed', 'closed', 'pending', 'partially completed') OR o.notes LIKE '%khata_debit%')
          ), 0.0) - 
          COALESCE((
            SELECT SUM(p.amount) 
            FROM customer_payments p 
            WHERE p.customer_id = c.id
          ), 0.0)
        ) as balance_due
      FROM customers c
      WHERE c.id = ?
    ''', [customerId]);

    if (res.isEmpty) {
      return {
        'credit_limit': 0.0,
        'balance_due': 0.0,
        'is_over_limit': false,
        'available_credit': 0.0,
      };
    }
    final row = res.first;
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
    };
  }

  /// Retrieves a chronological combined ledger of all debit (bills/orders)
  /// and credit (payments) for a customer with computed running balances.
  Future<List<Map<String, dynamic>>> getCustomerKhataLedger(int customerId) async {
    final db = await database;

    // 1. Fetch only closed orders / manual khata debits for customer
    final orderRows = await db.rawQuery('''
      SELECT 
        o.id,
        o.order_number,
        o.estimate_total,
        o.paid_amount,
        o.created_at,
        o.payment_mode,
        o.payment_status,
        o.status,
        o.notes,
        (SELECT COUNT(*) FROM order_items WHERE order_id = o.id) as item_count
      FROM orders o
      WHERE o.customer_id = ? 
        AND o.deleted_at IS NULL
        AND (LOWER(o.status) IN ('completed', 'closed', 'pending', 'partially completed') OR o.notes LIKE '%khata_debit%')
      ORDER BY o.created_at ASC
    ''', [customerId]);

    // 2. Fetch all direct payments
    final paymentRows = await db.query(
      'customer_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at ASC',
    );

    // 3. Combine into chronological ledger entries
    final entries = <Map<String, dynamic>>[];

    for (final o in orderRows) {
      final total = (o['estimate_total'] as num?)?.toDouble() ?? 0.0;
      final paidAmt = (o['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final itemCount = (o['item_count'] as num?)?.toInt() ?? 0;
      final notes = (o['notes'] as String?) ?? '';
      final mode = (o['payment_mode'] as String?) ?? 'Khata';

      final isManualDebit = notes.isNotEmpty && notes.contains('khata_debit');
      String subtitle;
      if (isManualDebit) {
        String desc = 'Manual Udhaar Entry';
        try {
          final decoded = jsonDecode(notes);
          if (decoded is Map && decoded['description'] != null) {
            desc = decoded['description'] as String;
          }
        } catch (_) {}
        subtitle = 'Manual Udhaar • $desc';
      } else if (paidAmt > 0) {
        final bal = (total - paidAmt) > 0 ? (total - paidAmt) : 0.0;
        subtitle = '$itemCount item(s) • Paid: ₹${paidAmt.toStringAsFixed(0)} ($mode) • Udhaar: ₹${bal.toStringAsFixed(2)}';
      } else {
        subtitle = '$itemCount item(s) • 100% Udhaar (Unpaid)';
      }

      entries.add({
        'type': 'debit', // You Gave (Bill)
        'is_manual_debit': isManualDebit,
        'id': o['id'],
        'order_id': o['id'],
        'order_number': (o['order_number'] as num?)?.toInt() ?? o['id'],
        'title': 'Bill #${(o['order_number'] as num?)?.toInt() ?? o['id']}',
        'subtitle': subtitle,
        'date': DateTime.tryParse(o['created_at'] as String? ?? '') ?? DateTime.now(),
        'amount': total,
        'debit': total,
        'credit': 0.0,
        'payment_mode': mode,
        'paid_amount': paidAmt,
        'status': o['status'],
        'notes': notes,
      });
    }

    for (final p in paymentRows) {
      final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      final rawMode = (p['payment_mode'] as String?) ?? 'Cash';
      final mode = rawMode.toUpperCase();
      final notes = (p['notes'] as String?) ?? '';
      final sub = notes.isNotEmpty ? notes : 'Direct Khata Payment';

      entries.add({
        'type': 'credit', // You Got (Payment)
        'id': p['id'],
        'title': 'Payment Received',
        'subtitle': 'Collected via $mode • $sub',
        'date': DateTime.tryParse(p['created_at'] as String? ?? '') ?? DateTime.now(),
        'amount': amt,
        'debit': 0.0,
        'credit': amt,
        'payment_mode': rawMode,
        'notes': notes,
      });
    }

    // Sort chronologically ascending
    entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Compute running balance & assign sequential customer bill numbers (Bill #1, Bill #2, Bill #3...)
    double running = 0.0;
    int billSequence = 0;
    for (final entry in entries) {
      if (entry['type'] == 'debit') {
        billSequence++;
        entry['bill_number'] = billSequence;
        entry['title'] = 'Bill #$billSequence';
      }
      running += ((entry['debit'] as num?)?.toDouble() ?? 0.0) -
                 ((entry['credit'] as num?)?.toDouble() ?? 0.0);
      entry['running_balance'] = running;
    }

    return entries;
  }

  /// Returns the sequential bill number for a specific customer order.
  /// Customer's first order is Bill 1, second order is Bill 2, etc.
  Future<int?> getCustomerBillSequence(int orderId) async {
    final db = await database;
    final target = await db.query(
      'orders',
      columns: ['customer_id'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (target.isEmpty) return null;
    final customerId = target.first['customer_id'] as int?;
    if (customerId == null) return null;

    final customerOrders = await db.rawQuery('''
      SELECT id FROM orders
      WHERE customer_id = ?
        AND deleted_at IS NULL
        AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')
      ORDER BY created_at ASC, id ASC
    ''', [customerId]);

    final idx = customerOrders.indexWhere((r) => r['id'] == orderId);
    if (idx < 0) return null;
    return idx + 1;
  }

  /// Records a manual Udhaar / Debit entry (e.g. Previous balance, opening balance, or cash lent)
  Future<int> recordManualKhataDebit({
    required int customerId,
    required double amount,
    required String description,
    String? takenBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final customer = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    final customerName = customer.isNotEmpty
        ? (customer.first['name'] as String? ?? 'Customer')
        : 'Customer';
    final customerPhone =
        customer.isNotEmpty ? customer.first['phone'] as String? : null;
    final effectiveTakenBy =
        takenBy ?? ShopSyncService.instance.currentUserOrDeviceName;

    final breakdownMap = {
      'subtotal': amount,
      'grandTotal': amount,
      'applyGst': false,
      'gstRate': 0.0,
      'gstAmount': 0.0,
      'otherCharges': <Map<String, dynamic>>[],
      'otherChargesTotal': 0.0,
      'applyDiscount': false,
      'discountType': 'flat',
      'discountValue': 0.0,
      'discountAmount': 0.0,
      'note': description,
      'customerPhone': customerPhone,
      'takenBy': effectiveTakenBy,
      'type': 'khata_debit',
      'description': description,
    };

    final newOrderId = await db.insert('orders', {
      'customer_id': customerId,
      'customer_name_snapshot': customerName,
      'customer_phone': customerPhone,
      'status': 'COMPLETED',
      'created_at': now,
      'updated_at': now,
      'notes': jsonEncode(breakdownMap),
      'taken_by': effectiveTakenBy,
      'estimate_total': amount,
      'paid_amount': 0.0,
      'payment_mode': 'Khata',
      'payment_status': 'unpaid',
    });
    unawaited(ShopSyncService.instance.syncOrder(newOrderId).catchError((e) {
      debugPrint('Error syncing order in recordManualKhataDebit: $e');
    }));
    return newOrderId;
  }

  /// Calculates aggregated Khata metrics for the business dashboard.
  /// Pass [preloadedList] if getCustomerKhataList() was already called to avoid duplicate query.
  Future<Map<String, dynamic>> getKhataSummaryMetrics([List<Map<String, dynamic>>? preloadedList]) async {
    final list = preloadedList ?? await getCustomerKhataList();
    double totalDue = 0;
    double totalAdvance = 0;
    double totalBilled = 0;
    double totalPaid = 0;
    double overdue30Days = 0;
    int dueCustomersCount = 0;
    int settledCustomersCount = 0;
    int overLimitCustomersCount = 0;

    for (final item in list) {
      final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final billed = (item['total_billed'] as num?)?.toDouble() ?? 0.0;
      final paid = (item['total_paid'] as num?)?.toDouble() ?? 0.0;
      final days = (item['days_overdue'] as num?)?.toInt() ?? 0;
      final isOver = item['is_over_limit'] as bool? ?? false;

      totalBilled += billed;
      totalPaid += paid;

      if (isOver) {
        overLimitCustomersCount++;
      }

      if (due > 0.01) {
        totalDue += due;
        dueCustomersCount++;
        if (days >= 30) {
          overdue30Days += due;
        }
      } else if (due < -0.01) {
        totalAdvance += -due;
      } else {
        settledCustomersCount++;
      }
    }

    // Today's collections
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final nextDay = DateTime(now.year, now.month, now.day + 1).toIso8601String();

    final paymentsToday = await db.query(
      'customer_payments',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [startOfDay, nextDay],
    );

    double collectedToday = 0;
    for (final p in paymentsToday) {
      collectedToday += (p['amount'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'totalMarketDue': totalDue,
      'totalAdvance': totalAdvance,
      'totalBilled': totalBilled,
      'totalPaid': totalPaid,
      'overdue30Days': overdue30Days,
      'dueCustomersCount': dueCustomersCount,
      'settledCustomersCount': settledCustomersCount,
      'overLimitCustomersCount': overLimitCustomersCount,
      'collectedToday': collectedToday,
      'totalCustomers': list.length,
    };
  }

  Future<Map<int, double>> _getCustomerBalancesBatch(
    DatabaseExecutor db,
    Iterable<int> customerIds,
  ) async {
    final uniqueIds = customerIds.toSet().toList();
    if (uniqueIds.isEmpty) return const <int, double>{};
    final result = <int, double>{for (final id in uniqueIds) id: 0.0};

    for (var i = 0; i < uniqueIds.length; i += 400) {
      final chunk = uniqueIds.sublist(
        i,
        i + 400 > uniqueIds.length ? uniqueIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');

      final billedRows = await db.rawQuery('''
        SELECT customer_id, COALESCE(SUM(estimate_total), 0.0) AS total_billed
        FROM orders
        WHERE customer_id IN ($placeholders)
          AND deleted_at IS NULL
          AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')
        GROUP BY customer_id
      ''', chunk);
      for (final r in billedRows) {
        final cid = (r['customer_id'] as num?)?.toInt();
        if (cid != null) {
          result[cid] =
              (result[cid] ?? 0.0) + ((r['total_billed'] as num?)?.toDouble() ?? 0.0);
        }
      }

      final paidRows = await db.rawQuery('''
        SELECT customer_id, COALESCE(SUM(amount), 0.0) AS total_paid
        FROM customer_payments
        WHERE customer_id IN ($placeholders)
        GROUP BY customer_id
      ''', chunk);
      for (final r in paidRows) {
        final cid = (r['customer_id'] as num?)?.toInt();
        if (cid != null) {
          result[cid] =
              (result[cid] ?? 0.0) - ((r['total_paid'] as num?)?.toDouble() ?? 0.0);
        }
      }
    }
    return result;
  }
}
