import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shop/models/top_product_stat.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String dbName = 'hardware_shop.db';
  static const int dbVersion = 3;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDb();
    return _database!;
  }

  Future<String> getDatabaseFullPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, dbName);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> reopen() async {
    _database = await _initDb();
  }

  Future<void> clearOrderHistory() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_item_options');
      await txn.delete('order_items');
      await txn.delete('orders');
    });
  }

  Future<void> clearProductsCatalog() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('product_options');
      await txn.delete('products');
    });
  }

  Future<void> resetAllShopData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_item_options');
      await txn.delete('order_items');
      await txn.delete('orders');
      await txn.delete('product_options');
      await txn.delete('products');
      await txn.delete('customers');
    });
    await _seedInitialProducts(db);
  }

  Future<Database> _initDb() async {
    final path = await getDatabaseFullPath();
    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE orders ADD COLUMN customer_phone TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE orders ADD COLUMN taken_by TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE orders ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE orders ADD COLUMN payment_mode TEXT NOT NULL DEFAULT 'unpaid'");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE orders ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'unpaid'");
        } catch (_) {}
        try {
          await db.execute("ALTER TABLE customers ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0");
        } catch (_) {}
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customer_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer_id INTEGER NOT NULL,
              amount REAL NOT NULL,
              payment_mode TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(customer_id) REFERENCES customers(id)
            )
          ''');
        } catch (_) {}
        try {
          await db.execute(
            "UPDATE orders SET taken_by = 'Srikar' WHERE taken_by IS NULL OR taken_by = '' OR taken_by = 'Store'",
          );
        } catch (_) {}
        try {
          // Deduplicate order_item_options
          await db.execute('''
            DELETE FROM order_item_options
            WHERE id NOT IN (
              SELECT MIN(id)
              FROM order_item_options
              GROUP BY order_item_id, LOWER(option_name), LOWER(option_value)
            )
          ''');
        } catch (_) {}
        try {
          // Clean up orphan options
          await db.execute('''
            DELETE FROM order_item_options
            WHERE order_item_id NOT IN (SELECT id FROM order_items)
          ''');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE products ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE products ADD COLUMN price_updated_at TEXT');
        } catch (_) {}
        await _seedInitialProducts(db);
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE orders ADD COLUMN estimate_total REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN customer_phone TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN taken_by TEXT');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        credit_limit REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        needs_review INTEGER NOT NULL DEFAULT 0,
        configuration TEXT NOT NULL,
        price_updated_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE product_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        option_type TEXT NOT NULL,
        option_value TEXT NOT NULL,
        display_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        customer_name_snapshot TEXT NOT NULL,
        customer_phone TEXT,
        taken_by TEXT,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        estimate_total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        item_name TEXT NOT NULL,
        quantity_ordered REAL NOT NULL,
        quantity_given REAL NOT NULL,
        unit TEXT NOT NULL,
        status TEXT NOT NULL,
        is_other_item INTEGER NOT NULL DEFAULT 0,
        procurement_status TEXT NOT NULL,
        details TEXT,
        notes TEXT,
        product_snapshot TEXT NOT NULL,
        FOREIGN KEY(order_id) REFERENCES orders(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE order_item_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_item_id INTEGER NOT NULL,
        option_name TEXT NOT NULL,
        option_value TEXT NOT NULL,
        FOREIGN KEY(order_item_id) REFERENCES order_items(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_customers_name ON customers(name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX idx_products_name ON products(name COLLATE NOCASE)',
    );
    await db
        .execute('CREATE INDEX idx_orders_created_at ON orders(created_at)');
    await db.execute(
        'CREATE INDEX idx_order_items_order_id ON order_items(order_id)');
    await db.execute(
      'CREATE INDEX idx_order_item_options_item_id ON order_item_options(order_item_id)',
    );
  }

  Future<void> _seedInitialProducts(Database db) async {
    final existing = await db.query('products', limit: 1);
    if (existing.isNotEmpty) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final sampleProducts = <Map<String, Object?>>[
      {
        'name': 'Paints',
        'category': 'Paints',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'colour',
              'label': 'Select Colour',
              'type': 'select',
              'values': ['Red', 'Blue', 'Green', 'White', 'Yellow']
            },
            {
              'key': 'size',
              'label': 'Select Size',
              'type': 'select',
              'values': ['1L', '4L', '10L', '20L']
            }
          ],
          'defaultUnit': 'Can',
          'unitOptions': ['Can']
        }),
        'created_at': now,
      },
      {
        'name': 'Distempers',
        'category': 'Distempers',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'colour',
              'label': 'Select Colour',
              'type': 'select',
              'values': ['White', 'Blue', 'Green']
            },
            {
              'key': 'size',
              'label': 'Select Size',
              'type': 'select',
              'values': ['1L', '4L', '10L']
            }
          ],
          'defaultUnit': 'Can',
          'unitOptions': ['Can']
        }),
        'created_at': now,
      },
      {
        'name': 'Sponges',
        'category': 'Sponges',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'type',
              'label': 'Select Type',
              'type': 'select',
              'values': ['Small', 'Medium', 'Large']
            }
          ],
          'defaultUnit': 'Piece',
          'unitOptions': ['Piece', 'Packet']
        }),
        'created_at': now,
      },
      {
        'name': 'Welding Rods',
        'category': 'Welding Rods',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'brand',
              'label': 'Select Brand',
              'type': 'select',
              'values': ['Brand A', 'Brand B']
            },
            {
              'key': 'type',
              'label': 'Select Type',
              'type': 'select',
              'values': ['2.5mm', '3.15mm', '4mm']
            }
          ],
          'defaultUnit': 'Box',
          'unitOptions': ['Box']
        }),
        'created_at': now,
      },
      {
        'name': 'Cut-off Wheels',
        'category': 'Cut-off Wheels',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'brand',
              'label': 'Select Brand',
              'type': 'select',
              'values': ['Brand A', 'Brand B']
            },
            {
              'key': 'size',
              'label': 'Select Size',
              'type': 'select',
              'values': ['4 inch', '7 inch', '14 inch']
            },
            {
              'key': 'type',
              'label': 'Select Type',
              'type': 'select',
              'values': ['Steel', 'General']
            }
          ],
          'defaultUnit': 'Piece',
          'unitOptions': ['Piece', 'Box']
        }),
        'created_at': now,
      },
      {
        'name': 'Nails',
        'category': 'Nails',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'size',
              'label': 'Select Size',
              'type': 'select',
              'values': ['1 inch', '2 inch', '3 inch']
            },
            {
              'key': 'weight',
              'label': 'Select Weight',
              'type': 'select',
              'values': ['1kg', '5kg', '10kg']
            }
          ],
          'defaultUnit': 'Bag',
          'unitOptions': ['Bag', 'Kg']
        }),
        'created_at': now,
      },
      {
        'name': 'Metal Paste',
        'category': 'Metal Paste',
        'is_active': 1,
        'configuration': jsonEncode({
          'steps': [
            {
              'key': 'weight',
              'label': 'Select Weight',
              'type': 'select',
              'values': ['100g', '250g', '500g', '1kg']
            }
          ],
          'defaultUnit': 'Piece',
          'unitOptions': ['Piece']
        }),
        'created_at': now,
      },
    ];

    for (final product in sampleProducts) {
      await db.insert('products', product);
    }
  }

  Future<List<TopProductStat>> getTopSellingProducts({
    String timeRange = 'all',
    String sortBy = 'quantity',
    int limit = 20,
  }) async {
    final db = await database;
    DateTime? since;
    final now = DateTime.now();
    if (timeRange == 'today') {
      since = DateTime(now.year, now.month, now.day);
    } else if (timeRange == 'week') {
      since = now.subtract(const Duration(days: 7));
    } else if (timeRange == 'month') {
      since = DateTime(now.year, now.month, 1);
    }

    final whereClause = since != null ? 'WHERE o.created_at >= ?' : '';
    final whereArgs = since != null ? [since.toIso8601String()] : <String>[];

    final query = '''
      SELECT 
        oi.item_name,
        oi.product_id,
        oi.unit,
        oi.quantity_given,
        oi.quantity_ordered,
        oi.product_snapshot,
        oi.order_id
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      $whereClause
    ''';

    final results = await db.rawQuery(query, whereArgs);
    final statsMap = <String, Map<String, dynamic>>{};

    for (final row in results) {
      final name = (row['item_name'] as String?)?.trim() ?? 'Unknown Item';
      final qtyGiven = (row['quantity_given'] as num?)?.toDouble() ?? 0.0;
      final qtyOrdered = (row['quantity_ordered'] as num?)?.toDouble() ?? 0.0;
      final qty = qtyGiven > 0 ? qtyGiven : qtyOrdered;
      final unit = (row['unit'] as String?) ?? 'Piece';
      final orderId = row['order_id'] as int?;
      final prodId = row['product_id'] as int?;

      double unitPrice = 0.0;
      final snapRaw = row['product_snapshot'] as String?;
      if (snapRaw != null && snapRaw.isNotEmpty) {
        try {
          final snapMap = jsonDecode(snapRaw) as Map<String, dynamic>;
          unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
        } catch (_) {}
      }
      final revenue = qty * unitPrice;

      if (!statsMap.containsKey(name)) {
        statsMap[name] = {
          'itemName': name,
          'productId': prodId,
          'unit': unit,
          'totalQuantity': 0.0,
          'totalRevenue': 0.0,
          'orderIds': <int>{},
        };
      }

      final entry = statsMap[name]!;
      entry['totalQuantity'] = (entry['totalQuantity'] as double) + qty;
      entry['totalRevenue'] = (entry['totalRevenue'] as double) + revenue;
      if (orderId != null) {
        (entry['orderIds'] as Set<int>).add(orderId);
      }
    }

    final statList = statsMap.values.map((e) {
      return TopProductStat(
        itemName: e['itemName'] as String,
        productId: e['productId'] as int?,
        unit: e['unit'] as String,
        totalQuantity: e['totalQuantity'] as double,
        totalRevenue: e['totalRevenue'] as double,
        orderCount: (e['orderIds'] as Set<int>).length,
      );
    }).toList();

    if (sortBy == 'revenue') {
      statList.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    } else {
      statList.sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
    }

    if (statList.length > limit) {
      return statList.sublist(0, limit);
    }
    return statList;
  }

  Future<void> recordOrderPayment({
    required int orderId,
    required double paidAmount,
    required String paymentMode,
  }) async {
    final db = await database;
    final order =
        await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
    if (order.isEmpty) return;
    final total = (order.first['estimate_total'] as num?)?.toDouble() ?? 0.0;
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
  }

  Future<void> recordCustomerKhataPayment({
    required int customerId,
    required double amount,
    required String paymentMode,
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert('customer_payments', {
        'customer_id': customerId,
        'amount': amount,
        'payment_mode': paymentMode,
        'notes': notes,
        'created_at': now,
      });

      // Apply payment to oldest pending/partial orders first
      final unpaidOrders = await txn.query(
        'orders',
        where: 'customer_id = ? AND estimate_total > paid_amount',
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

          await txn.update(
            'orders',
            {
              'paid_amount': newPaid,
              'payment_status': newStatus,
              'payment_mode': paymentMode,
            },
            where: 'id = ?',
            whereArgs: [orderId],
          );
          remainingToApply -= payingForThis;
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCustomerKhataList() async {
    final db = await database;
    final query = '''
      SELECT 
        c.id as customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        COALESCE(c.credit_limit, 0.0) as credit_limit,
        COALESCE((
          SELECT SUM(o.estimate_total) 
          FROM orders o 
          WHERE o.customer_id = c.id 
            AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
        ), 0.0) as total_billed,
        COALESCE((
          SELECT SUM(p.amount) 
          FROM customer_payments p 
          WHERE p.customer_id = c.id
        ), 0.0) as total_paid,
        (
          SELECT COUNT(o.id) 
          FROM orders o 
          WHERE o.customer_id = c.id 
            AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
        ) as order_count,
        (
          SELECT MAX(o.created_at) 
          FROM orders o 
          WHERE o.customer_id = c.id 
            AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
        ) as last_order_date,
        (
          SELECT MAX(p.created_at) 
          FROM customer_payments p 
          WHERE p.customer_id = c.id
        ) as last_payment_date,
        (
          SELECT p.payment_mode 
          FROM customer_payments p 
          WHERE p.customer_id = c.id 
          ORDER BY p.created_at DESC 
          LIMIT 1
        ) as last_payment_mode,
        MIN(CASE WHEN o.estimate_total > (o.paid_amount + 0.01) AND (LOWER(o.status) IN ('completed', 'closed')) THEN o.created_at ELSE NULL END) as oldest_unpaid_date
      FROM customers c
      LEFT JOIN orders o ON c.id = o.customer_id
      GROUP BY c.id
      HAVING (
        COALESCE((
          SELECT SUM(o.estimate_total) 
          FROM orders o 
          WHERE o.customer_id = c.id 
            AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
        ), 0.0) - 
        COALESCE((
          SELECT SUM(p.amount) 
          FROM customer_payments p 
          WHERE p.customer_id = c.id
        ), 0.0)
      ) > 0.01 
      OR (
        SELECT SUM(o.estimate_total) 
        FROM orders o 
        WHERE o.customer_id = c.id 
          AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
      ) > 0 
      OR credit_limit > 0
      ORDER BY (
        COALESCE((
          SELECT SUM(o.estimate_total) 
          FROM orders o 
          WHERE o.customer_id = c.id 
            AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
        ), 0.0) - 
        COALESCE((
          SELECT SUM(p.amount) 
          FROM customer_payments p 
          WHERE p.customer_id = c.id
        ), 0.0)
      ) DESC, c.name ASC
    ''';
    final rows = await db.rawQuery(query);
    final now = DateTime.now();

    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      final billed = (map['total_billed'] as num?)?.toDouble() ?? 0.0;
      final paid = (map['total_paid'] as num?)?.toDouble() ?? 0.0;
      final due = (billed - paid) > 0.01 ? (billed - paid) : 0.0;
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

  /// Updates a customer's maximum credit limit (Khata limit)
  Future<void> updateCustomerCreditLimit(int customerId, double creditLimit) async {
    final db = await database;
    await db.update(
      'customers',
      {'credit_limit': creditLimit},
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
              AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
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
    final isOver = limit > 0 && finalDue > limit;
    final available = limit > 0 ? (limit - finalDue) : 0.0;
    return {
      'credit_limit': limit,
      'balance_due': finalDue,
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
        AND (LOWER(o.status) IN ('completed', 'closed') OR o.notes LIKE '%khata_debit%')
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

      String subtitle;
      if (notes.isNotEmpty && notes.contains('khata_debit')) {
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
        'id': o['id'],
        'order_id': o['id'],
        'title': 'Bill #${o['id']}',
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
      running += (entry['debit'] as double) - (entry['credit'] as double);
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

    final customerOrders = await db.query(
      'orders',
      columns: ['id'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at ASC, id ASC',
    );

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
    return await db.insert('orders', {
      'customer_id': customerId,
      'status': 'COMPLETED',
      'created_at': now,
      'notes': jsonEncode({'type': 'khata_debit', 'description': description}),
      'taken_by': takenBy ?? ShopSyncService.instance.currentUserOrDeviceName,
      'estimate_total': amount,
      'paid_amount': 0.0,
      'payment_mode': 'Khata',
      'payment_status': 'unpaid',
    });
  }

  /// Calculates aggregated Khata metrics for the business dashboard
  Future<Map<String, dynamic>> getKhataSummaryMetrics() async {
    final list = await getCustomerKhataList();
    double totalDue = 0;
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

      totalDue += due;
      totalBilled += billed;
      totalPaid += paid;

      if (isOver) {
        overLimitCustomersCount++;
      }

      if (due > 0.01) {
        dueCustomersCount++;
        if (days >= 30) {
          overdue30Days += due;
        }
      } else {
        settledCustomersCount++;
      }
    }

    // Today's collections
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    final paymentsToday = await db.query(
      'customer_payments',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startOfDay, endOfDay],
    );

    double collectedToday = 0;
    for (final p in paymentsToday) {
      collectedToday += (p['amount'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'totalMarketDue': totalDue,
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

  Future<Map<String, dynamic>> getEveningClosingReport(DateTime date) async {
    try {
      final db = await database;
      final startOfDay =
          DateTime(date.year, date.month, date.day).toIso8601String();
      final endOfDay =
          DateTime(date.year, date.month, date.day, 23, 59, 59).toIso8601String();

      final orderRows = await db.query(
        'orders',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [startOfDay, endOfDay],
      );

      double totalSales = 0;
      double cashSales = 0;
      double upiSales = 0;
      double creditSales = 0;
      int completedCount = 0;
      int pendingCount = 0;

      for (final row in orderRows) {
        final total = (row['estimate_total'] as num?)?.toDouble() ?? 0.0;
        final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final mode = (row['payment_mode'] as String?)?.toLowerCase() ?? 'unpaid';
        final status = (row['status'] as String?) ?? '';

        totalSales += total;
        if (status == 'Completed' || status == 'Closed') {
          completedCount++;
        } else {
          pendingCount++;
        }

        if (mode == 'cash') {
          cashSales += paid;
        } else if (mode == 'upi') {
          upiSales += paid;
        }
        final due = total - paid;
        if (due > 0) {
          creditSales += due;
        }
      }

      // Direct Khata payments received today
      final paymentRows = await db.query(
        'customer_payments',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [startOfDay, endOfDay],
      );

      double directPayments = 0;
      for (final p in paymentRows) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final mode = (p['payment_mode'] as String?)?.toLowerCase() ?? '';
        directPayments += amt;
        if (mode == 'cash') cashSales += amt;
        if (mode == 'upi') upiSales += amt;
      }

      TopProductStat? topItem;
      try {
        final topItems =
            await getTopSellingProducts(timeRange: 'today', limit: 1);
        if (topItems.isNotEmpty) {
          topItem = topItems.first;
        }
      } catch (e) {
        debugPrint('Top product calculation error in evening report: $e');
      }

      return {
        'date': date,
        'totalOrders': orderRows.length,
        'completedOrders': completedCount,
        'pendingOrders': pendingCount,
        'totalSales': totalSales,
        'cashSales': cashSales,
        'upiSales': upiSales,
        'creditSales': creditSales,
        'directPayments': directPayments,
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
        'creditSales': 0.0,
        'directPayments': 0.0,
        'topItemName': 'None',
        'topItemQty': 0,
        'topItemUnit': '',
      };
    }
  }
}
