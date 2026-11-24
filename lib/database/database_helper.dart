import 'dart:async';
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
  static const int dbVersion = 4;

  Database? _database;
  Future<Database>? _initDbFuture;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _initDbFuture ??= _initDb();
    _database = await _initDbFuture!;
    return _database!;
  }

  Future<String> getDatabaseFullPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, dbName);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initDbFuture = null;
  }

  Future<void> reopen() async {
    await close();
    _database = await _initDb();
  }

  Future<void> clearOrderHistory() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('order_item_options');
      await txn.delete('order_items');
      await txn.delete('orders');
      await txn.delete('customer_payments');
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
      await txn.delete('customer_payments');
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
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
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
      } catch (e) {
        debugPrint('Column customer_phone already exists: $e');
      }
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN taken_by TEXT');
      } catch (e) {
        debugPrint('Column taken_by already exists: $e');
      }
    }
    if (oldVersion < 4) {
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
        await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE products ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE products ADD COLUMN price_updated_at TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE order_items ADD COLUMN unit_price REAL NOT NULL DEFAULT 0.0');
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
        await db.execute('ALTER TABLE orders ADD COLUMN cloud_order_id TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_cloud_id ON orders(cloud_order_id)');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE customer_payments ADD COLUMN cloud_payment_id TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_cloud_id ON customer_payments(cloud_payment_id)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_unit_price ON order_items(unit_price)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_payments_customer_id ON customer_payments(customer_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id)');
      } catch (_) {}
      try {
        final items = await db.query('order_items', columns: ['id', 'product_snapshot'], where: 'unit_price = 0');
        for (final item in items) {
          final snapRaw = item['product_snapshot'] as String?;
          if (snapRaw != null && snapRaw.isNotEmpty) {
            try {
              final snapMap = jsonDecode(snapRaw) as Map<String, dynamic>;
              final price = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
              if (price > 0) {
                await db.update('order_items', {'unit_price': price}, where: 'id = ?', whereArgs: [item['id']]);
              }
            } catch (_) {}
          }
        }
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
        cloud_order_id TEXT UNIQUE,
        customer_id INTEGER NOT NULL,
        customer_name_snapshot TEXT NOT NULL,
        customer_phone TEXT,
        taken_by TEXT,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        estimate_total REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT NOT NULL DEFAULT 'unpaid',
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
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
        unit_price REAL NOT NULL DEFAULT 0.0,
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

    await db.execute('''
      CREATE TABLE customer_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_payment_id TEXT UNIQUE,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
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
      'CREATE INDEX idx_orders_customer_id ON orders(customer_id)',
    );
    await db.execute(
        'CREATE INDEX idx_order_items_order_id ON order_items(order_id)');
    await db.execute(
        'CREATE INDEX idx_order_items_unit_price ON order_items(unit_price)');
    await db.execute(
      'CREATE INDEX idx_order_item_options_item_id ON order_item_options(order_item_id)',
    );
    await db.execute(
      'CREATE INDEX idx_customer_payments_customer_id ON customer_payments(customer_id)',
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
      await db.insert('products', {
        ...product,
        'price_updated_at': now,
        'needs_review': 0,
      });
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
        oi.unit_price,
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

      double unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
      if (unitPrice == 0.0) {
        final snapRaw = row['product_snapshot'] as String?;
        if (snapRaw != null && snapRaw.isNotEmpty) {
          try {
            final snapMap = jsonDecode(snapRaw) as Map<String, dynamic>;
            unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }
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
      entry['totalQuantity'] = ((entry['totalQuantity'] as num?)?.toDouble() ?? 0.0) + qty;
      entry['totalRevenue'] = ((entry['totalRevenue'] as num?)?.toDouble() ?? 0.0) + revenue;
      if (orderId != null) {
        (entry['orderIds'] as Set<int>).add(orderId);
      }
    }

    final statList = statsMap.values.map((e) {
      return TopProductStat(
        itemName: e['itemName'] as String,
        productId: e['productId'] as int?,
        unit: e['unit'] as String,
        totalQuantity: (e['totalQuantity'] as num?)?.toDouble() ?? 0.0,
        totalRevenue: (e['totalRevenue'] as num?)?.toDouble() ?? 0.0,
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
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      final added = paidAmount - prevPaid;
      final customerId = order.first['customer_id'] as int?;
      if (added > 0.001 && customerId != null) {
        final now = DateTime.now().toIso8601String();
        newPaymentId = await txn.insert('customer_payments', {
          'customer_id': customerId,
          'amount': added,
          'payment_mode': paymentMode.toLowerCase(),
          'notes': 'Payment for Order #ORD-${orderId.toString().padLeft(4, "0")}',
          'created_at': now,
        });
      } else if (added < -0.001 && customerId != null) {
        // Compensating adjustment for payment reduction / refund
        final now = DateTime.now().toIso8601String();
        newPaymentId = await txn.insert('customer_payments', {
          'customer_id': customerId,
          'amount': added,
          'payment_mode': paymentMode.toLowerCase(),
          'notes': 'Refund/Adjustment for Order #ORD-${orderId.toString().padLeft(4, "0")}',
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
        where: "customer_id = ? AND estimate_total > paid_amount AND (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')",
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
        WHERE (LOWER(status) IN ('completed', 'closed', 'pending', 'partially completed') OR notes LIKE '%khata_debit%')
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
      WHERE (COALESCE(b.total_billed, 0.0) - COALESCE(p.total_paid, 0.0)).abs() > 0.01 
         OR COALESCE(b.total_billed, 0.0) > 0 
         OR COALESCE(p.total_paid, 0.0) > 0
         OR c.credit_limit > 0
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

  Future<Map<String, dynamic>> getEveningClosingReport(DateTime date) async {
    try {
      final db = await database;
      final startOfDay =
          DateTime(date.year, date.month, date.day).toIso8601String();
      final nextDay =
          DateTime(date.year, date.month, date.day + 1).toIso8601String();

      final orderRows = await db.query(
        'orders',
        where: 'created_at >= ? AND created_at < ?',
        whereArgs: [startOfDay, nextDay],
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
        final status = (row['status'] as String?)?.trim().toUpperCase() ?? '';

        totalSales += total;
        if (status == 'COMPLETED' || status == 'CLOSED') {
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

      // Direct Khata payments received today (avoiding double-counting today's order payments)
      final paymentRows = await db.query(
        'customer_payments',
        where: 'created_at >= ? AND created_at < ?',
        whereArgs: [startOfDay, nextDay],
      );

      final todayOrderIds = orderRows.map((r) => r['id'] as int).toSet();
      double directPayments = 0;
      for (final p in paymentRows) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final mode = (p['payment_mode'] as String?)?.toLowerCase() ?? '';
        final notes = (p['notes'] as String?) ?? '';

        bool alreadyCountedInTodayOrders = false;
        final match = RegExp(r'Order #ORD-(\d+)').firstMatch(notes);
        if (match != null) {
          final matchedOrderId = int.tryParse(match.group(1) ?? '');
          if (matchedOrderId != null && todayOrderIds.contains(matchedOrderId)) {
            alreadyCountedInTodayOrders = true;
          }
        }

        if (!alreadyCountedInTodayOrders) {
          directPayments += amt;
          if (mode == 'cash') cashSales += amt;
          if (mode == 'upi') upiSales += amt;
        }
      }

      TopProductStat? topItem;
      try {
        final topRows = await db.rawQuery('''
          SELECT oi.item_name, SUM(oi.quantity_ordered) as total_qty, oi.unit
          FROM order_items oi
          INNER JOIN orders o ON oi.order_id = o.id
          WHERE o.created_at >= ? AND o.created_at < ?
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
