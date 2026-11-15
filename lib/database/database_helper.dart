import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shop/models/top_product_stat.dart';
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
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        configuration TEXT NOT NULL,
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
    final sortField = sortBy == 'revenue' ? 'total_revenue' : 'total_quantity';

    final query = '''
      SELECT 
        oi.item_name,
        oi.product_id,
        oi.unit,
        SUM(COALESCE(oi.quantity_given, oi.quantity_ordered, 0)) as total_quantity,
        SUM(COALESCE(oi.quantity_given, oi.quantity_ordered, 0) * COALESCE(oi.unit_price, 0)) as total_revenue,
        COUNT(DISTINCT oi.order_id) as order_count
      FROM order_items oi
      JOIN orders o ON oi.order_id = o.id
      $whereClause
      GROUP BY oi.item_name
      ORDER BY $sortField DESC
      LIMIT $limit
    ''';

    final results = await db.rawQuery(query, whereArgs);
    return results.map((row) => TopProductStat.fromMap(row)).toList();
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
        COALESCE(SUM(o.estimate_total), 0) as total_billed,
        COALESCE(SUM(o.paid_amount), 0) as total_paid,
        (COALESCE(SUM(o.estimate_total), 0) - COALESCE(SUM(o.paid_amount), 0)) as balance_due,
        COUNT(DISTINCT o.id) as order_count
      FROM customers c
      LEFT JOIN orders o ON c.id = o.customer_id
      GROUP BY c.id
      HAVING balance_due > 0.01 OR total_billed > 0
      ORDER BY balance_due DESC, c.name ASC
    ''';
    return await db.rawQuery(query);
  }

  Future<Map<String, dynamic>> getEveningClosingReport(DateTime date) async {
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

    final topItems =
        await getTopSellingProducts(timeRange: 'today', limit: 1);
    final topItem = topItems.isNotEmpty ? topItems.first : null;

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
  }
}
