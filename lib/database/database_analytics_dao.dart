part of 'database_helper.dart';

/// Evening closing and lifetime business analytics queries.
extension DatabaseAnalyticsDao on DatabaseHelper {
  Future<Map<String, dynamic>> getEveningClosingReport(DateTime date) async {
    try {
      final db = await database;
      final startOfDay =
          DateTime(date.year, date.month, date.day).toIso8601String();
      final nextDay =
          DateTime(date.year, date.month, date.day + 1).toIso8601String();

      final orderRows = await db.query(
        'orders',
        where: 'deleted_at IS NULL AND created_at >= ? AND created_at < ?',
        whereArgs: [startOfDay, nextDay],
      );

      double totalSales = 0;
      double creditSales = 0;
      int completedCount = 0;
      int pendingCount = 0;
      final todayOrderIds = <int>{};
      final todayOrderNumbers = <int>{};

      for (final row in orderRows) {
        final oid = (row['id'] as num?)?.toInt();
        final oNum = (row['order_number'] as num?)?.toInt();
        if (oid != null) todayOrderIds.add(oid);
        if (oNum != null) todayOrderNumbers.add(oNum);

        final total = (row['estimate_total'] as num?)?.toDouble() ?? 0.0;
        final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final status = (row['status'] as String?)?.trim().toUpperCase() ?? '';

        totalSales += total;
        if (status == 'COMPLETED' || status == 'CLOSED') {
          completedCount++;
        } else {
          pendingCount++;
        }

        final due = total - paid;
        if (due > 0) {
          creditSales += due;
        }
      }

      // Derive all collections strictly from customer_payments to preserve per-payment modes
      // (cash / upi / cheque / bank_transfer) and eliminate same-day Khata double-counting.
      final paymentRows = await db.query(
        'customer_payments',
        where: 'created_at >= ? AND created_at < ?',
        whereArgs: [startOfDay, nextDay],
      );

      double cashSales = 0;
      double upiSales = 0;
      double otherSales = 0;
      double directPayments = 0;
      final matchedOrderRefsToday = <int>{};
      final paidCustomerIdsToday = <int>{};

      for (final p in paymentRows) {
        final cid = (p['customer_id'] as num?)?.toInt();
        if (cid != null) paidCustomerIdsToday.add(cid);
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final mode = (p['payment_mode'] as String?)?.trim().toLowerCase() ?? '';
        final notes = (p['notes'] as String?) ?? '';

        if (mode == 'cash') {
          cashSales += amt;
        } else if (mode == 'upi') {
          upiSales += amt;
        } else {
          otherSales += amt;
        }

        bool isTodayOrderPayment = false;
        final match = RegExp(r'Order #ORD-(\d+)').firstMatch(notes);
        if (match != null) {
          final matchedOrderNum = int.tryParse(match.group(1) ?? '');
          if (matchedOrderNum != null &&
              (todayOrderIds.contains(matchedOrderNum) ||
                  todayOrderNumbers.contains(matchedOrderNum))) {
            isTodayOrderPayment = true;
            matchedOrderRefsToday.add(matchedOrderNum);
          }
        }

        if (!isTodayOrderPayment) {
          directPayments += amt;
        }
      }

      // Fallback only for legacy rows that set orders.paid_amount directly without any customer_payments entry
      for (final row in orderRows) {
        final oid = (row['id'] as num?)?.toInt();
        final oNum = (row['order_number'] as num?)?.toInt();
        final cid = (row['customer_id'] as num?)?.toInt();
        final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
        if (paid <= 0.001) continue;
        final hasMatchedPayment = (oid != null && matchedOrderRefsToday.contains(oid)) ||
            (oNum != null && matchedOrderRefsToday.contains(oNum)) ||
            (cid != null && paidCustomerIdsToday.contains(cid));
        if (!hasMatchedPayment) {
          final mode = (row['payment_mode'] as String?)?.trim().toLowerCase() ?? 'unpaid';
          if (mode == 'cash') {
            cashSales += paid;
          } else if (mode == 'upi') {
            upiSales += paid;
          } else if (mode != 'unpaid' && mode != 'khata' && mode.isNotEmpty) {
            otherSales += paid;
          }
        }
      }

      TopProductStat? topItem;
      try {
        final topRows = await db.rawQuery('''
          SELECT oi.item_name, SUM(oi.quantity_ordered) as total_qty, oi.unit
          FROM order_items oi
          INNER JOIN orders o ON oi.order_id = o.id
          WHERE o.deleted_at IS NULL AND o.created_at >= ? AND o.created_at < ?
          GROUP BY oi.item_name, oi.unit
          ORDER BY total_qty DESC
          LIMIT 1
        ''', [startOfDay, nextDay]);
        if (topRows.isNotEmpty) {
          topItem = TopProductStat(
            itemName: topRows.first['item_name'] as String? ?? 'None',
            totalQuantity: (topRows.first['total_qty'] as num?)?.toDouble() ?? 0.0,
            totalRevenue: 0.0,
            unit: topRows.first['unit'] as String? ?? '',
            orderCount: 1,
          );
        }
      } catch (e) {
        debugPrint('Top product calculation error in evening report: $e');
      }

      final totalCollectedToday = cashSales + upiSales + otherSales;

      return {
        'date': date,
        'totalOrders': orderRows.length,
        'completedOrders': completedCount,
        'pendingOrders': pendingCount,
        'totalSales': totalSales,
        'cashSales': cashSales,
        'upiSales': upiSales,
        'otherSales': otherSales,
        'creditSales': creditSales,
        'directPayments': directPayments,
        'totalCollectedToday': totalCollectedToday,
        'topItemName': topItem?.itemName ?? 'None',
        'topItemQty': topItem?.totalQuantity ?? 0,
        'topItemUnit': topItem?.unit ?? '',
      };
    } catch (e) {
      debugPrint('Error getting evening closing report: $e');
      return {
        'date': date,
        'totalOrders': 0,
        'completedOrders': 0,
        'pendingOrders': 0,
        'totalSales': 0.0,
        'cashSales': 0.0,
        'upiSales': 0.0,
        'otherSales': 0.0,
        'creditSales': 0.0,
        'directPayments': 0.0,
        'totalCollectedToday': 0.0,
        'topItemName': 'None',
        'topItemQty': 0,
        'topItemUnit': '',
      };
    }
  }

  /// Retrieves list of all collections (payments) recorded on a specific date with customer details.
  Future<List<Map<String, dynamic>>> getCollectionsForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
    final nextDay = DateTime(date.year, date.month, date.day + 1).toIso8601String();

    final rows = await db.rawQuery('''
      SELECT 
        cp.id,
        cp.customer_id,
        cp.amount,
        cp.payment_mode,
        cp.notes,
        cp.created_at,
        c.name as customer_name,
        c.phone as customer_phone,
        COALESCE(c.address, '') as customer_location
      FROM customer_payments cp
      JOIN customers c ON cp.customer_id = c.id
      WHERE cp.created_at >= ? AND cp.created_at < ?
      ORDER BY cp.created_at DESC
    ''', [startOfDay, nextDay]);

    final balancesByCustomer = await _getCustomerBalancesBatch(
      db,
      rows.map((r) => r['customer_id'] as int),
    );
    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final cid = row['customer_id'] as int;
      map['remaining_due'] = balancesByCustomer[cid] ?? 0.0;
      list.add(map);
    }
    return list;
  }

  /// Calculates comprehensive Lifetime Business Analytics across all time or custom range/location.
  Future<Map<String, dynamic>> getLifetimeBusinessReport({
    String? locationFilter,
    String? staffFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    final orderWhereParts = <String>['o.deleted_at IS NULL'];
    final orderWhereArgs = <Object?>[];

    if (startDate != null) {
      orderWhereParts.add('o.created_at >= ?');
      orderWhereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      orderWhereParts.add('o.created_at <= ?');
      orderWhereArgs.add(endDate.toIso8601String());
    }

    final bool isLocFiltered = locationFilter != null &&
        locationFilter.trim().isNotEmpty &&
        locationFilter.trim() != 'All Locations';
    final String? cleanLoc = isLocFiltered ? locationFilter.trim() : null;

    final bool isStaffFiltered = staffFilter != null &&
        staffFilter.trim().isNotEmpty &&
        staffFilter.trim() != 'All Staff' &&
        staffFilter.trim() != 'All Partners' &&
        staffFilter.trim() != 'All Partner Devices / Counters';
    final String? cleanStaff = isStaffFiltered ? staffFilter.trim() : null;

    if (cleanLoc != null) {
      orderWhereParts.add('TRIM(c.address) = ? COLLATE NOCASE');
      orderWhereArgs.add(cleanLoc);
    }
    if (cleanStaff != null) {
      orderWhereParts.add('TRIM(o.taken_by) = ? COLLATE NOCASE');
      orderWhereArgs.add(cleanStaff);
    }

    final orderWhereClause = orderWhereParts.isNotEmpty
        ? 'WHERE ${orderWhereParts.join(' AND ')}'
        : '';

    // 1. Orders aggregates
    final orderAggQuery = '''
      SELECT 
        COUNT(o.id) as total_orders,
        COALESCE(SUM(o.estimate_total), 0.0) as total_sales,
        COALESCE(SUM(o.paid_amount), 0.0) as total_order_paid,
        SUM(CASE WHEN UPPER(o.status) IN ('COMPLETED', 'CLOSED') THEN 1 ELSE 0 END) as completed_orders,
        SUM(CASE WHEN UPPER(o.status) NOT IN ('COMPLETED', 'CLOSED') THEN 1 ELSE 0 END) as pending_orders
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
    ''';
    final orderAggRows = await db.rawQuery(orderAggQuery, orderWhereArgs);
    final orderAgg = orderAggRows.isNotEmpty ? orderAggRows.first : {};
    final totalOrders = (orderAgg['total_orders'] as num?)?.toInt() ?? 0;
    final totalSales = (orderAgg['total_sales'] as num?)?.toDouble() ?? 0.0;
    final completedOrders = (orderAgg['completed_orders'] as num?)?.toInt() ?? 0;
    final pendingOrders = (orderAgg['pending_orders'] as num?)?.toInt() ?? 0;

    // 2. Collections (customer_payments)
    final payWhereParts = <String>[];
    final payWhereArgs = <Object?>[];
    if (startDate != null) {
      payWhereParts.add('cp.created_at >= ?');
      payWhereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      payWhereParts.add('cp.created_at <= ?');
      payWhereArgs.add(endDate.toIso8601String());
    }
    if (cleanLoc != null) {
      payWhereParts.add('TRIM(c.address) = ? COLLATE NOCASE');
      payWhereArgs.add(cleanLoc);
    }
    if (cleanStaff != null) {
      payWhereParts.add(
        'cp.customer_id IN (SELECT DISTINCT o.customer_id FROM orders o WHERE o.deleted_at IS NULL AND TRIM(o.taken_by) = ? COLLATE NOCASE)',
      );
      payWhereArgs.add(cleanStaff);
    }

    final payWhereClause = payWhereParts.isNotEmpty
        ? 'WHERE ${payWhereParts.join(' AND ')}'
        : '';

    final payAggQuery = '''
      SELECT COALESCE(SUM(cp.amount), 0.0) as total_collected
      FROM customer_payments cp
      LEFT JOIN customers c ON cp.customer_id = c.id
      $payWhereClause
    ''';
    final payAggRows = await db.rawQuery(payAggQuery, payWhereArgs);
    final totalCollected = payAggRows.isNotEmpty
        ? (payAggRows.first['total_collected'] as num?)?.toDouble() ?? 0.0
        : 0.0;

    // 3. Outstanding Market Due & Advance Pool (Filtered by location & staff if specified)
    final rawKhataList = await getCustomerKhataList();
    Set<int>? staffCustomerIds;
    if (cleanStaff != null) {
      final staffCustRows = await db.rawQuery(
        'SELECT DISTINCT customer_id FROM orders WHERE deleted_at IS NULL AND TRIM(taken_by) = ? COLLATE NOCASE',
        [cleanStaff],
      );
      staffCustomerIds = staffCustRows
          .map((r) => (r['customer_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
    }
    final targetLocLower = cleanLoc?.toLowerCase();
    final khataList = (cleanLoc != null || staffCustomerIds != null)
        ? rawKhataList.where((item) {
            if (targetLocLower != null) {
              final loc = (item['customer_location'] as String?)?.trim().toLowerCase();
              if (loc != targetLocLower) return false;
            }
            if (staffCustomerIds != null) {
              final cid = (item['customer_id'] as num?)?.toInt();
              if (cid == null || !staffCustomerIds.contains(cid)) return false;
            }
            return true;
          }).toList()
        : rawKhataList;

    final khataSummary = await getKhataSummaryMetrics(khataList);
    final totalMarketDue = (khataSummary['totalMarketDue'] as num?)?.toDouble() ?? 0.0;
    final overdue30 = (khataSummary['overdue30Days'] as num?)?.toDouble() ?? 0.0;

    final highestDueCustomers = khataList
        .where((item) => ((item['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.01)
        .toList()
      ..sort((a, b) => ((b['balance_due'] as num?)?.toDouble() ?? 0.0)
          .compareTo((a['balance_due'] as num?)?.toDouble() ?? 0.0));

    final advanceCustomers = khataList
        .where((item) => ((item['balance_due'] as num?)?.toDouble() ?? 0.0) < -0.01)
        .toList();
    final advancePoolTotal = advanceCustomers.fold<double>(
        0.0, (sum, item) => sum + (-((item['balance_due'] as num).toDouble())));
    final advanceAccountsCount = advanceCustomers.length;

    // 4. Financial & Basket Intelligence (AOV, Basket Size, Discounts, GST, Cash vs UPI)
    final basketQuery = '''
      SELECT 
        COALESCE(SUM(oi.quantity_ordered), 0.0) as total_items_sold,
        COUNT(oi.id) as total_lines_sold
      FROM order_items oi
      INNER JOIN orders o ON oi.order_id = o.id
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
    ''';
    final basketRows = await db.rawQuery(basketQuery, orderWhereArgs);
    final totalItemsSold = (basketRows.first['total_items_sold'] as num?)?.toDouble() ?? 0.0;
    final totalLinesSold = (basketRows.first['total_lines_sold'] as num?)?.toInt() ?? 0;
    final averageOrderValue = totalOrders > 0 ? (totalSales / totalOrders) : 0.0;
    final avgBasketSize = totalOrders > 0 ? (totalItemsSold / totalOrders) : 0.0;
    final avgLinesPerOrder = totalOrders > 0 ? (totalLinesSold / totalOrders) : 0.0;

    // Discounts & Taxes from orders.notes JSON
    final orderNotesRows = await db.rawQuery('''
      SELECT o.notes 
      FROM orders o 
      LEFT JOIN customers c ON o.customer_id = c.id 
      $orderWhereClause
    ''', orderWhereArgs);
    double totalDiscountsGiven = 0.0;
    double totalGstBilled = 0.0;
    for (final r in orderNotesRows) {
      final raw = r['notes'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          if (m['applyDiscount'] == true) {
            totalDiscountsGiven += (m['discountAmount'] as num?)?.toDouble() ?? 0.0;
          }
          if (m['applyGst'] == true) {
            totalGstBilled += (m['gstAmount'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (_) {}
      }
    }

    // Cash vs UPI Breakdown
    final payModeQuery = '''
      SELECT 
        COALESCE(SUM(CASE WHEN LOWER(cp.payment_mode) = 'cash' THEN cp.amount ELSE 0.0 END), 0.0) as cash_collected,
        COALESCE(SUM(CASE WHEN LOWER(cp.payment_mode) = 'upi' THEN cp.amount ELSE 0.0 END), 0.0) as upi_collected
      FROM customer_payments cp
      LEFT JOIN customers c ON cp.customer_id = c.id
      $payWhereClause
    ''';
    final payModeRows = await db.rawQuery(payModeQuery, payWhereArgs);
    final cashCollected = (payModeRows.first['cash_collected'] as num?)?.toDouble() ?? 0.0;
    final upiCollected = (payModeRows.first['upi_collected'] as num?)?.toDouble() ?? 0.0;
    final cashPercentage = totalCollected > 0 ? (cashCollected / totalCollected) * 100 : 0.0;
    final upiPercentage = totalCollected > 0 ? (upiCollected / totalCollected) * 100 : 0.0;

    // 5. Store Financial Health Score (0 - 100 & Grade A+, A, B, C, D)
    final recoveryRate = (totalSales + totalMarketDue) > 0 
        ? ((totalCollected / (totalSales + totalMarketDue)) * 100).clamp(0.0, 100.0) 
        : 100.0;
    final overdueRatio = totalMarketDue > 0 ? ((overdue30 / totalMarketDue) * 100).clamp(0.0, 100.0) : 0.0;
    final completionRate = totalOrders > 0 ? ((completedOrders / totalOrders) * 100).clamp(0.0, 100.0) : 100.0;
    final rawHealth = (recoveryRate * 0.40) + ((100.0 - overdueRatio) * 0.35) + (completionRate * 0.25);
    final healthScore = rawHealth.round().clamp(0, 100);
    String healthGrade;
    String healthSummary;
    if (healthScore >= 88) {
      healthGrade = 'Grade A+';
      healthSummary = 'Outstanding Cashflow & Low Overdue Risk';
    } else if (healthScore >= 75) {
      healthGrade = 'Grade A';
      healthSummary = 'Healthy Cashflow & Consistent Settlements';
    } else if (healthScore >= 60) {
      healthGrade = 'Grade B';
      healthSummary = 'Moderate Health • Monitor Aging Udhaar';
    } else if (healthScore >= 45) {
      healthGrade = 'Grade C';
      healthSummary = 'High Credit Risk • Follow Up on Outstanding Dues';
    } else {
      healthGrade = 'Grade D';
      healthSummary = 'Critical Overdue • Urgent Payment Recovery Needed';
    }

    // 6. Customer Repeat Rate & Loyalty
    final custOrdersQuery = '''
      SELECT 
        o.customer_id, 
        COUNT(o.id) as cust_order_count 
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY o.customer_id
    ''';
    final custOrderRows = await db.rawQuery(custOrdersQuery, orderWhereArgs);
    final uniqueCustomerCount = custOrderRows.length;
    final repeatCustomerCount = custOrderRows.where((r) => ((r['cust_order_count'] as num?)?.toInt() ?? 0) > 1).length;
    final oneTimeCustomerCount = uniqueCustomerCount - repeatCustomerCount;
    final repeatRatePercentage = uniqueCustomerCount > 0 ? (repeatCustomerCount / uniqueCustomerCount) * 100 : 0.0;

    // 7. Dormant / Lost Customers (Inactive 30+ days, sorted by past spend, using local device clock)
    final dormantWhereParts = <String>[
      'o.deleted_at IS NULL',
      'COALESCE(c.is_active, 1) = 1',
      'c.deleted_at IS NULL',
    ];
    final dormantWhereArgs = <Object?>[];
    if (cleanLoc != null) {
      dormantWhereParts.add('TRIM(c.address) = ? COLLATE NOCASE');
      dormantWhereArgs.add(cleanLoc);
    }
    if (cleanStaff != null) {
      dormantWhereParts.add('TRIM(o.taken_by) = ? COLLATE NOCASE');
      dormantWhereArgs.add(cleanStaff);
    }
    final dormantWhereClause = dormantWhereParts.isNotEmpty
        ? 'WHERE ${dormantWhereParts.join(' AND ')}'
        : '';
    final nowLocalIso = DateTime.now().toIso8601String();
    final dormantQuery = '''
      SELECT 
        c.id as customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        COALESCE(c.address, '') as customer_location,
        MAX(o.created_at) as last_order_date,
        SUM(o.estimate_total) as past_total_bought,
        COUNT(o.id) as past_order_count,
        CAST((julianday(?) - julianday(MAX(o.created_at))) as INTEGER) as days_since_last_order
      FROM orders o
      JOIN customers c ON o.customer_id = c.id
      $dormantWhereClause
      GROUP BY c.id
      HAVING (julianday(?) - julianday(MAX(o.created_at))) >= 30
      ORDER BY past_total_bought DESC
      LIMIT 20
    ''';
    final dormantCustomers = await db.rawQuery(
      dormantQuery,
      [nowLocalIso, ...dormantWhereArgs, nowLocalIso],
    );

    // 8. Average Udhaar Clearance Cycle (FIFO DSO per customer, avoiding M×N join explosion)
    final dsoOrderRows = await db.rawQuery('''
      SELECT o.id, o.customer_id, o.created_at, o.estimate_total
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      ORDER BY o.customer_id ASC, o.created_at ASC, o.id ASC
    ''', orderWhereArgs);
    final dsoCustomerIds = dsoOrderRows
        .map((r) => (r['customer_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    final dsoPayRows = <Map<String, Object?>>[];
    for (var i = 0; i < dsoCustomerIds.length; i += 400) {
      final chunk = dsoCustomerIds.sublist(
        i,
        i + 400 > dsoCustomerIds.length ? dsoCustomerIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT cp.customer_id, cp.created_at, cp.amount
        FROM customer_payments cp
        WHERE cp.customer_id IN ($placeholders)
        ORDER BY cp.created_at ASC, cp.id ASC
      ''', chunk);
      dsoPayRows.addAll(rows);
    }
    final rawDso = DatabaseHelper.computeAverageDsoFromRows(dsoOrderRows, dsoPayRows);
    final avgDsoDays = rawDso != null
        ? rawDso.round()
        : (totalMarketDue > 0 && totalSales > 0 ? ((totalMarketDue / totalSales) * 30).round() : 14);

    // 9. Top Selling Products
    final topProductsQuery = '''
      SELECT 
        oi.item_name,
        oi.unit,
        SUM(oi.quantity_ordered) as total_qty,
        SUM(oi.quantity_ordered * oi.unit_price) as total_rev
      FROM order_items oi
      INNER JOIN orders o ON oi.order_id = o.id
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY oi.item_name, oi.unit
      ORDER BY total_rev DESC, total_qty DESC
      LIMIT 10
    ''';
    final topProdRows = await db.rawQuery(topProductsQuery, orderWhereArgs);

    // 10. Least Selling Products / Slow moving (filtered consistently by date, location & staff)
    final leastProductsQuery = '''
      SELECT 
        p.name as item_name,
        p.category,
        COALESCE(s.total_qty, 0.0) as total_qty
      FROM products p
      LEFT JOIN (
        SELECT 
          oi.product_id,
          SUM(oi.quantity_ordered) as total_qty
        FROM order_items oi
        INNER JOIN orders o ON oi.order_id = o.id
        LEFT JOIN customers c ON o.customer_id = c.id
        $orderWhereClause
        GROUP BY oi.product_id
      ) s ON s.product_id = p.id
      WHERE p.is_active = 1
      ORDER BY total_qty ASC, p.name ASC
      LIMIT 10
    ''';
    final leastProdRows = await db.rawQuery(leastProductsQuery, orderWhereArgs);

    // 11. Dead Stock Alert (0 sales in catalog for current filter)
    final deadStockWhereSubquery = orderWhereClause.isEmpty
        ? 'WHERE oi.product_id IS NOT NULL'
        : '$orderWhereClause AND oi.product_id IS NOT NULL';

    final deadStockQuery = '''
      SELECT 
        p.id,
        p.name as item_name,
        p.category,
        p.created_at
      FROM products p
      WHERE p.is_active = 1
        AND p.id NOT IN (
          SELECT DISTINCT oi.product_id 
          FROM order_items oi
          INNER JOIN orders o ON oi.order_id = o.id
          LEFT JOIN customers c ON o.customer_id = c.id
          $deadStockWhereSubquery
        )
      ORDER BY p.name ASC
      LIMIT 20
    ''';
    final deadStockProducts = await db.rawQuery(deadStockQuery, orderWhereArgs);

    // 12. Category Sales Breakdown
    final categoryQuery = '''
      SELECT 
        COALESCE(NULLIF(TRIM(p.category), ''), 'General Hardware') as category,
        COALESCE(SUM(oi.quantity_ordered * oi.unit_price), 0.0) as category_sales,
        COUNT(oi.id) as item_count
      FROM order_items oi
      INNER JOIN orders o ON oi.order_id = o.id
      LEFT JOIN products p ON oi.product_id = p.id
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY category
      ORDER BY category_sales DESC
    ''';
    final categorySales = await db.rawQuery(categoryQuery, orderWhereArgs);

    // 13. Most Frequent Shortages / Stockouts during fulfillment
    final shortageWhere = orderWhereClause.isEmpty 
        ? 'WHERE oi.quantity_ordered > oi.quantity_given' 
        : '$orderWhereClause AND oi.quantity_ordered > oi.quantity_given';
    final shortageQuery = '''
      SELECT 
        oi.item_name,
        oi.unit,
        COUNT(oi.id) as shortage_events,
        SUM(oi.quantity_ordered - oi.quantity_given) as total_short_qty
      FROM order_items oi
      INNER JOIN orders o ON oi.order_id = o.id
      LEFT JOIN customers c ON o.customer_id = c.id
      $shortageWhere
      GROUP BY oi.item_name, oi.unit
      ORDER BY shortage_events DESC, total_short_qty DESC
      LIMIT 10
    ''';
    final topStockouts = await db.rawQuery(shortageQuery, orderWhereArgs);

    // 14. Top Valued Customers: Buyers & Payers
    final topBuyersQuery = '''
      SELECT 
        c.id,
        c.name,
        c.name as customer_name,
        c.phone,
        c.phone as customer_phone,
        COALESCE(c.address, '') as location,
        COALESCE(c.address, '') as customer_location,
        SUM(o.estimate_total) as total_bought,
        COUNT(o.id) as order_count
      FROM orders o
      JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY c.id
      ORDER BY total_bought DESC
      LIMIT 10
    ''';
    final topBuyers = await db.rawQuery(topBuyersQuery, orderWhereArgs);

    final topPayersQuery = '''
      SELECT 
        c.id,
        c.name,
        c.name as customer_name,
        c.phone,
        c.phone as customer_phone,
        COALESCE(c.address, '') as location,
        COALESCE(c.address, '') as customer_location,
        SUM(cp.amount) as total_paid,
        COUNT(cp.id) as payment_count
      FROM customer_payments cp
      JOIN customers c ON cp.customer_id = c.id
      $payWhereClause
      GROUP BY c.id
      ORDER BY total_paid DESC
      LIMIT 10
    ''';
    final topPayers = await db.rawQuery(topPayersQuery, payWhereArgs);

    // 15. Peak Days (Day of Week analysis: Sunday to Saturday)
    final peakDaysQuery = '''
      SELECT 
        strftime('%w', o.created_at) as day_of_week,
        COUNT(o.id) as order_count,
        COALESCE(SUM(o.estimate_total), 0.0) as sales_volume
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY day_of_week
      ORDER BY day_of_week ASC
    ''';
    final peakRows = await db.rawQuery(peakDaysQuery, orderWhereArgs);
    final dayOfWeekStats = <int, Map<String, dynamic>>{};
    for (int i = 0; i < 7; i++) {
      dayOfWeekStats[i] = {'count': 0, 'sales': 0.0};
    }
    for (final r in peakRows) {
      final day = int.tryParse(r['day_of_week']?.toString() ?? '') ?? 0;
      dayOfWeekStats[day] = {
        'count': (r['order_count'] as num?)?.toInt() ?? 0,
        'sales': (r['sales_volume'] as num?)?.toDouble() ?? 0.0,
      };
    }

    // 16. Rush Hours (Busiest Hours of the Day Heatmap)
    final hourlyQuery = '''
      SELECT 
        strftime('%H', o.created_at) as hour_of_day,
        COUNT(o.id) as order_count,
        COALESCE(SUM(o.estimate_total), 0.0) as sales
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY hour_of_day
      ORDER BY hour_of_day ASC
    ''';
    final hourlyStats = await db.rawQuery(hourlyQuery, orderWhereArgs);

    // 17. Month-on-Month Growth Trend (Last 12 Months)
    final monthlySalesQuery = '''
      SELECT 
        strftime('%Y-%m', o.created_at) as month_key,
        COUNT(o.id) as order_count,
        COALESCE(SUM(o.estimate_total), 0.0) as sales
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY month_key
      ORDER BY month_key DESC
      LIMIT 12
    ''';
    final monthlySalesRows = await db.rawQuery(monthlySalesQuery, orderWhereArgs);

    final monthlyPayQuery = '''
      SELECT 
        strftime('%Y-%m', cp.created_at) as month_key,
        COALESCE(SUM(cp.amount), 0.0) as collections
      FROM customer_payments cp
      LEFT JOIN customers c ON cp.customer_id = c.id
      $payWhereClause
      GROUP BY month_key
      ORDER BY month_key DESC
      LIMIT 12
    ''';
    final monthlyPayRows = await db.rawQuery(monthlyPayQuery, payWhereArgs);
    final payByMonth = {for (final r in monthlyPayRows) r['month_key'] as String: (r['collections'] as num?)?.toDouble() ?? 0.0};

    final monthlyTrend = <Map<String, dynamic>>[];
    for (final sRow in monthlySalesRows.reversed) {
      final mKey = sRow['month_key'] as String;
      monthlyTrend.add({
        'month_key': mKey,
        'orders': (sRow['order_count'] as num?)?.toInt() ?? 0,
        'sales': (sRow['sales'] as num?)?.toDouble() ?? 0.0,
        'collections': payByMonth[mKey] ?? 0.0,
      });
    }

    // 18. Staff & Device Performance Leaderboard
    final staffLeaderboardQuery = '''
      SELECT 
        COALESCE(NULLIF(TRIM(o.taken_by), ''), 'Store') as staff_name,
        COUNT(o.id) as orders_taken,
        COALESCE(SUM(o.estimate_total), 0.0) as total_sales,
        COALESCE(SUM(o.paid_amount), 0.0) as direct_collected
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      $orderWhereClause
      GROUP BY staff_name
      ORDER BY total_sales DESC
    ''';
    final staffLeaderboard = await db.rawQuery(staffLeaderboardQuery, orderWhereArgs);

    // 19. Collections List
    final collectionsQuery = '''
      SELECT 
        cp.id,
        cp.customer_id,
        cp.amount,
        cp.payment_mode,
        cp.notes,
        cp.created_at,
        c.name as customer_name,
        c.phone as customer_phone,
        COALESCE(c.address, '') as customer_location
      FROM customer_payments cp
      JOIN customers c ON cp.customer_id = c.id
      $payWhereClause
      ORDER BY cp.created_at DESC
      LIMIT 100
    ''';
    final collectionRows = await db.rawQuery(collectionsQuery, payWhereArgs);
    final batchBalances = await _getCustomerBalancesBatch(
      db,
      collectionRows.map((r) => r['customer_id'] as int),
    );
    final collectionsWithDue = <Map<String, dynamic>>[];
    for (final row in collectionRows) {
      final map = Map<String, dynamic>.from(row);
      final cid = row['customer_id'] as int;
      map['remaining_due'] = batchBalances[cid] ?? 0.0;
      collectionsWithDue.add(map);
    }

    // 20. Distinct Locations & Staff
    final locRows = await db.rawQuery('''
      SELECT DISTINCT TRIM(address) as location 
      FROM customers 
      WHERE COALESCE(is_active, 1) = 1 AND deleted_at IS NULL
        AND address IS NOT NULL AND TRIM(address) != ''
      GROUP BY TRIM(address) COLLATE NOCASE
      ORDER BY location ASC
    ''');
    final allLocations = locRows
        .map((r) => r['location'] as String)
        .where((l) => l.isNotEmpty)
        .toList();

    final staffRows = await db.rawQuery('''
      SELECT DISTINCT TRIM(taken_by) as staff 
      FROM orders 
      WHERE deleted_at IS NULL
        AND taken_by IS NOT NULL AND TRIM(taken_by) != '' AND TRIM(taken_by) != 'Store'
      GROUP BY TRIM(taken_by) COLLATE NOCASE
      ORDER BY staff ASC
    ''');
    final allStaff = staffRows
        .map((r) => r['staff'] as String)
        .where((s) => s.isNotEmpty)
        .toList();

    return {
      // Core Metrics
      'totalSales': totalSales,
      'totalCollected': totalCollected,
      'totalCollections': totalCollected,
      'totalMarketDue': totalMarketDue,
      'totalOrders': totalOrders,
      'completedOrders': completedOrders,
      'pendingOrders': pendingOrders,

      // Financial & Basket Size
      'averageOrderValue': averageOrderValue,
      'totalItemsSold': totalItemsSold,
      'totalLinesSold': totalLinesSold,
      'avgBasketSize': avgBasketSize,
      'avgLinesPerOrder': avgLinesPerOrder,
      'totalDiscountsGiven': totalDiscountsGiven,
      'totalGstBilled': totalGstBilled,
      'cashCollected': cashCollected,
      'upiCollected': upiCollected,
      'cashPercentage': cashPercentage,
      'upiPercentage': upiPercentage,
      'advancePoolTotal': advancePoolTotal,
      'advanceAccountsCount': advanceAccountsCount,

      // Store Financial Health
      'healthGrade': healthGrade,
      'healthScore': healthScore,
      'healthSummary': healthSummary,
      'avgDsoDays': avgDsoDays,

      // Customer Retention & Intelligence
      'uniqueCustomerCount': uniqueCustomerCount,
      'repeatCustomerCount': repeatCustomerCount,
      'oneTimeCustomerCount': oneTimeCustomerCount,
      'repeatRatePercentage': repeatRatePercentage,
      'dormantCustomers': dormantCustomers,
      'topBuyers': topBuyers,
      'topPayers': topPayers,
      'highestDueCustomers': highestDueCustomers.take(15).toList(),
      'highestDues': highestDueCustomers.take(15).toList(),

      // Product & Inventory Intelligence
      'topProducts': topProdRows,
      'topSellingProducts': topProdRows,
      'leastProducts': leastProdRows,
      'leastSellingProducts': leastProdRows,
      'deadStockProducts': deadStockProducts,
      'categorySales': categorySales,
      'topStockouts': topStockouts,

      // Time & Trend Visuals
      'peakDays': peakRows,
      'dayOfWeekStats': dayOfWeekStats,
      'hourlyStats': hourlyStats,
      'monthlyTrend': monthlyTrend,

      // Staff & Meta
      'staffLeaderboard': staffLeaderboard,
      'collections': collectionsWithDue,
      'collectionsList': collectionsWithDue,
      'allLocations': allLocations,
      'allStaff': allStaff,
    };
  }

  Future<List<KhataCustomerSummary>> getTypedCustomerKhataList() async {
    final rows = await getCustomerKhataList();
    return rows.map(KhataCustomerSummary.fromMap).toList();
  }

  Future<List<KhataLedgerEntry>> getTypedCustomerKhataLedger(int customerId) async {
    final rows = await getCustomerKhataLedger(customerId);
    return rows.map(KhataLedgerEntry.fromMap).toList();
  }

  Future<EveningClosingSummary> getTypedEveningClosingReport(DateTime date) async {
    final raw = await getEveningClosingReport(date);
    return EveningClosingSummary.fromMap(raw);
  }

  Future<LifetimeBusinessSummary> getTypedLifetimeBusinessReport({
    String? locationFilter,
    String? staffFilter,
  }) async {
    final raw = await getLifetimeBusinessReport(
      locationFilter: locationFilter,
      staffFilter: staffFilter,
    );
    return LifetimeBusinessSummary.fromMap(raw);
  }
}
