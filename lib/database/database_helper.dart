import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shop/models/customer.dart';
import 'package:shop/models/report_summary.dart';
import 'package:shop/models/top_product_stat.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:sqflite/sqflite.dart';

part 'database_khata_dao.dart';
part 'database_analytics_dao.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String dbName = 'hardware_shop.db';
  static const int dbVersion = 12;

  static final math.Random _secureRandom = math.Random.secure();

  /// Generates a collision-resistant RFC-4122 UUIDv4 string without extra dependencies.
  static String generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @visibleForTesting
  static String? testDbPathOverride;

  Database? _database;
  Future<Database>? _initDbFuture;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _initDbFuture ??= _initDb();
    try {
      _database = await _initDbFuture!;
      return _database!;
    } catch (_) {
      _initDbFuture = null;
      _database = null;
      rethrow;
    }
  }

  Future<String> getDatabaseFullPath() async {
    if (testDbPathOverride != null && testDbPathOverride!.isNotEmpty) {
      return testDbPathOverride!;
    }
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

  /// Finds a customer ID matching [rawPhone] regardless of '+91', '0', spaces, or dashes.
  Future<int?> findCustomerIdByNormalizedPhone(
    DatabaseExecutor db,
    String rawPhone,
  ) async {
    final canonical = Customer.normalizePhoneDigits(rawPhone);
    if (canonical.length < 6) return null;
    final tail = canonical.length >= 6
        ? canonical.substring(canonical.length - 6)
        : canonical;
    final candidates = await db.query(
      'customers',
      columns: ['id', 'phone'],
      where:
          "COALESCE(is_active, 1) = 1 AND deleted_at IS NULL AND "
          "REPLACE(REPLACE(REPLACE(COALESCE(phone, ''), ' ', ''), '-', ''), '+', '') LIKE ?",
      whereArgs: ['%$tail%'],
      limit: 50,
    );
    for (final row in candidates) {
      final phoneStr = row['phone'] as String?;
      if (phoneStr == null) continue;
      for (final p in Customer.extractNumbers(phoneStr)) {
        if (Customer.phonesMatch(p, rawPhone)) {
          return row['id'] as int?;
        }
      }
    }
    return null;
  }

  /// Merges duplicate customer rows that share the same normalized phone number
  /// (e.g. '9392449356' and '+91 93924 49356'), preserving all orders & payments.
  Future<void> deduplicateCustomersByPhone(Database db) async {
    final customers = await db.query(
      'customers',
      columns: ['id', 'cloud_id', 'name', 'phone', 'address', 'credit_limit'],
      where:
          "COALESCE(is_active, 1) = 1 AND deleted_at IS NULL AND "
          "phone IS NOT NULL AND TRIM(phone) != ''",
      orderBy: 'id ASC',
    );
    if (customers.length < 2) return;

    final orderCounts = <int, int>{};
    for (final r in await db.rawQuery(
      'SELECT customer_id, COUNT(*) AS cnt FROM orders GROUP BY customer_id',
    )) {
      final cid = (r['customer_id'] as num?)?.toInt();
      if (cid != null) orderCounts[cid] = (r['cnt'] as num?)?.toInt() ?? 0;
    }

    final paymentCounts = <int, int>{};
    for (final r in await db.rawQuery(
      'SELECT customer_id, COUNT(*) AS cnt FROM customer_payments GROUP BY customer_id',
    )) {
      final cid = (r['customer_id'] as num?)?.toInt();
      if (cid != null) paymentCounts[cid] = (r['cnt'] as num?)?.toInt() ?? 0;
    }

    final byCanonical = <String, List<Map<String, Object?>>>{};
    for (final c in customers) {
      final phone = c['phone'] as String?;
      if (phone == null) continue;
      final nums = Customer.extractNumbers(phone);
      if (nums.isEmpty) continue;
      final canonical = Customer.normalizePhoneDigits(nums.first);
      if (canonical.length < 6) continue;
      byCanonical.putIfAbsent(canonical, () => []).add(c);
    }

    final mergedDupIds = <int>{};
    await db.transaction((txn) async {
      for (final group in byCanonical.values) {
        final active = group
            .where((c) => !mergedDupIds.contains((c['id'] as num).toInt()))
            .toList();
        if (active.length < 2) continue;

        active.sort((a, b) {
          final idA = (a['id'] as num).toInt();
          final idB = (b['id'] as num).toInt();
          final scoreA = (orderCounts[idA] ?? 0) + (paymentCounts[idA] ?? 0);
          final scoreB = (orderCounts[idB] ?? 0) + (paymentCounts[idB] ?? 0);
          if (scoreA != scoreB) return scoreB.compareTo(scoreA);
          return idA.compareTo(idB);
        });

        final primary = active.first;
        final primaryId = (primary['id'] as num).toInt();
        var mergedAddress = (primary['address'] as String?)?.trim();
        var mergedCredit = (primary['credit_limit'] as num?)?.toDouble() ?? 0.0;

        for (final dup in active.skip(1)) {
          final dupId = (dup['id'] as num).toInt();
          if (mergedDupIds.contains(dupId)) continue;
          mergedDupIds.add(dupId);

          await txn.update(
            'orders',
            {'customer_id': primaryId},
            where: 'customer_id = ?',
            whereArgs: [dupId],
          );
          await txn.update(
            'customer_payments',
            {'customer_id': primaryId},
            where: 'customer_id = ?',
            whereArgs: [dupId],
          );

          final dupAddr = (dup['address'] as String?)?.trim();
          if ((mergedAddress == null || mergedAddress.isEmpty) &&
              dupAddr != null &&
              dupAddr.isNotEmpty) {
            mergedAddress = dupAddr;
          }
          final dupCredit = (dup['credit_limit'] as num?)?.toDouble() ?? 0.0;
          if (dupCredit > mergedCredit) {
            mergedCredit = dupCredit;
          }

          final dupCloudId = (dup['cloud_id'] as String?)?.trim();
          if (dupCloudId != null && dupCloudId.isNotEmpty) {
            try {
              await txn.rawInsert('''
                INSERT OR REPLACE INTO sync_outbox
                (entity_type, local_id, cloud_id, retry_count, next_retry_at, last_error, created_at)
                VALUES (?, ?, ?, 0, ?, NULL, ?)
              ''', [
                'customer_delete',
                dupId,
                dupCloudId,
                DateTime.now().toIso8601String(),
                DateTime.now().toIso8601String(),
              ]);
            } catch (_) {}
          }

          await txn.delete(
            'customers',
            where: 'id = ?',
            whereArgs: [dupId],
          );
        }

        await txn.update(
          'customers',
          {
            'address': mergedAddress,
            'credit_limit': mergedCredit,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [primaryId],
        );
      }
    });
  }

  Future<void> clearOrderHistory() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('delivery_transactions');
      await txn.delete('delivery_locations');
      await txn.delete('delivery_partners');
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
      await txn.delete('delivery_transactions');
      await txn.delete('delivery_locations');
      await txn.delete('delivery_partners');
      await txn.delete('order_item_options');
      await txn.delete('order_items');
      await txn.delete('orders');
      await txn.delete('customer_payments');
      await txn.delete('product_options');
      await txn.delete('products');
      await txn.delete('customers');
      try {
        await txn.delete('sync_outbox');
      } catch (_) {}
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
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN order_number INTEGER');
      } catch (_) {}
      try {
        await db.execute('UPDATE orders SET order_number = id WHERE order_number IS NULL');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number)');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _createDeliveryTables(db);
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE delivery_partners ADD COLUMN cloud_partner_id TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_partners_cloud_id ON delivery_partners(cloud_partner_id)');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE delivery_transactions ADD COLUMN cloud_tx_id TEXT');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_tx_cloud_id ON delivery_transactions(cloud_tx_id)');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN delivery_partner_name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN box_count INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      await _createStorageManagementTables(db);
    }
    if (oldVersion < 10) {
      try {
        await db.execute(
          'ALTER TABLE customers ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
        );
      } catch (_) {}
    }
    if (oldVersion < 11) {
      const ddlStatements = [
        'ALTER TABLE customers ADD COLUMN cloud_id TEXT',
        'ALTER TABLE customers ADD COLUMN updated_at TEXT',
        'ALTER TABLE customers ADD COLUMN deleted_at TEXT',
        'ALTER TABLE products ADD COLUMN cloud_id TEXT',
        'ALTER TABLE products ADD COLUMN updated_at TEXT',
        'ALTER TABLE products ADD COLUMN deleted_at TEXT',
        'ALTER TABLE orders ADD COLUMN updated_at TEXT',
        'ALTER TABLE orders ADD COLUMN deleted_at TEXT',
        'ALTER TABLE customer_payments ADD COLUMN updated_at TEXT',
        'ALTER TABLE customer_payments ADD COLUMN deleted_at TEXT',
        'ALTER TABLE delivery_partners ADD COLUMN updated_at TEXT',
        'ALTER TABLE delivery_partners ADD COLUMN deleted_at TEXT',
        'ALTER TABLE delivery_transactions ADD COLUMN updated_at TEXT',
        'ALTER TABLE delivery_transactions ADD COLUMN deleted_at TEXT',
      ];
      for (final sql in ddlStatements) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }

      await _createSyncOutboxTable(db);

      try {
        await db.execute('''
          DELETE FROM order_item_options
          WHERE id NOT IN (
            SELECT MIN(id)
            FROM order_item_options
            GROUP BY order_item_id, LOWER(option_name), LOWER(option_value)
          )
        ''');
        await db.execute('''
          DELETE FROM order_item_options
          WHERE order_item_id NOT IN (SELECT id FROM order_items)
        ''');
      } catch (_) {}

      try {
        await deduplicateCustomersByPhone(db);
      } catch (e) {
        debugPrint('v11 migration customer dedup skipped: $e');
      }

      final nowIso = DateTime.now().toIso8601String();
      try {
        final custs = await db.query('customers', columns: ['id', 'cloud_id', 'updated_at', 'created_at']);
        for (final c in custs) {
          final updates = <String, Object?>{};
          if ((c['cloud_id'] as String?)?.isNotEmpty != true) {
            updates['cloud_id'] = generateUuidV4();
          }
          if ((c['updated_at'] as String?)?.isNotEmpty != true) {
            updates['updated_at'] = (c['created_at'] as String?) ?? nowIso;
          }
          if (updates.isNotEmpty) {
            await db.update('customers', updates, where: 'id = ?', whereArgs: [c['id']]);
          }
        }
      } catch (_) {}

      try {
        final prods = await db.query('products', columns: ['id', 'cloud_id', 'updated_at', 'price_updated_at', 'created_at']);
        for (final p in prods) {
          final updates = <String, Object?>{};
          if ((p['cloud_id'] as String?)?.isNotEmpty != true) {
            updates['cloud_id'] = generateUuidV4();
          }
          if ((p['updated_at'] as String?)?.isNotEmpty != true) {
            updates['updated_at'] =
                (p['price_updated_at'] as String?) ?? (p['created_at'] as String?) ?? nowIso;
          }
          if (updates.isNotEmpty) {
            await db.update('products', updates, where: 'id = ?', whereArgs: [p['id']]);
          }
        }
      } catch (_) {}

      try {
        await db.execute(
          'UPDATE orders SET updated_at = COALESCE(updated_at, created_at, ?)',
          [nowIso],
        );
        await db.execute(
          'UPDATE customer_payments SET updated_at = COALESCE(updated_at, created_at, ?)',
          [nowIso],
        );
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE storage_archives ADD COLUMN gcs_path TEXT');
      } catch (_) {}
    }
    await _createPerformanceIndexes(db);
  }

  Future<void> _createSyncOutboxTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        local_id INTEGER,
        cloud_id TEXT NOT NULL,
        payload_json TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT NOT NULL,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_outbox_entity_cloud ON sync_outbox(entity_type, cloud_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_due ON sync_outbox(next_retry_at, retry_count)',
    );
  }

  Future<void> _createPerformanceIndexes(Database db) async {
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customer_payments_created_at ON customer_payments(created_at)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_order_items_proc_status ON order_items(procurement_status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_cloud_id ON customers(cloud_id)',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_cloud_id ON products(cloud_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_updated_at ON customers(updated_at)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_updated_at ON products(updated_at)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_updated_at ON orders(updated_at)',
      );
    } catch (e) {
      debugPrint('Error creating performance indexes: $e');
    }
  }

  Future<void> _createStorageManagementTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS storage_archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        archive_id TEXT NOT NULL UNIQUE,
        rule_applied TEXT NOT NULL,
        date_range_start TEXT NOT NULL,
        date_range_end TEXT NOT NULL,
        record_count INTEGER NOT NULL DEFAULT 0,
        archived_doc_ids_json TEXT NOT NULL,
        checksum TEXT,
        gcs_path TEXT,
        compressed_gzip_base64 TEXT NOT NULL,
        verified INTEGER NOT NULL DEFAULT 0,
        restored_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS storage_audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        job_id TEXT,
        archive_id TEXT,
        rule_applied TEXT,
        status TEXT NOT NULL,
        records_archived INTEGER NOT NULL DEFAULT 0,
        records_deleted INTEGER NOT NULL DEFAULT 0,
        bytes_before INTEGER NOT NULL DEFAULT 0,
        bytes_after INTEGER NOT NULL DEFAULT 0,
        reclaimed_bytes INTEGER NOT NULL DEFAULT 0,
        message TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createDeliveryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_partners (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_partner_id TEXT UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        vehicle_info TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_tx_id TEXT UNIQUE,
        partner_id INTEGER NOT NULL,
        tx_type TEXT NOT NULL,
        location TEXT,
        total_boxes INTEGER NOT NULL DEFAULT 0,
        rate_breakdown_json TEXT,
        earned_amount REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        cut_amount REAL NOT NULL DEFAULT 0.0,
        payment_mode TEXT NOT NULL DEFAULT 'none',
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY(partner_id) REFERENCES delivery_partners(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_delivery_tx_partner_id ON delivery_transactions(partner_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_delivery_tx_created_at ON delivery_transactions(created_at)',
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        credit_limit REAL NOT NULL DEFAULT 0.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        needs_review INTEGER NOT NULL DEFAULT 0,
        configuration TEXT NOT NULL,
        price_updated_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
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
        order_number INTEGER,
        cloud_order_id TEXT UNIQUE,
        customer_id INTEGER NOT NULL,
        customer_name_snapshot TEXT NOT NULL,
        customer_phone TEXT,
        taken_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT,
        status TEXT NOT NULL,
        notes TEXT,
        estimate_total REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        payment_mode TEXT NOT NULL DEFAULT 'unpaid',
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        delivery_partner_name TEXT,
        box_count INTEGER NOT NULL DEFAULT 0,
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
        updated_at TEXT,
        deleted_at TEXT,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
      )
    ''');

    await _createDeliveryTables(db);
    await _createStorageManagementTables(db);
    await _createSyncOutboxTable(db);

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
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number)',
    );
    await _createPerformanceIndexes(db);
    await _seedInitialProducts(db);
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
        'cloud_id': generateUuidV4(),
        'price_updated_at': now,
        'updated_at': now,
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

  /// Pure FIFO Days-Sales-Outstanding calculator from chronological order & payment rows.
  @visibleForTesting
  static double? computeAverageDsoFromRows(
    List<Map<String, Object?>> orders,
    List<Map<String, Object?>> payments,
  ) {
    final ordersByCust = <int, List<({DateTime createdAt, double total})>>{};
    for (final o in orders) {
      final cid = (o['customer_id'] as num?)?.toInt();
      final total = (o['estimate_total'] as num?)?.toDouble() ?? 0.0;
      final dt = DateTime.tryParse(o['created_at'] as String? ?? '');
      if (cid == null || total <= 0.01 || dt == null) continue;
      ordersByCust.putIfAbsent(cid, () => []).add((createdAt: dt, total: total));
    }

    final paymentsByCust = <int, List<({DateTime createdAt, double amount})>>{};
    for (final p in payments) {
      final cid = (p['customer_id'] as num?)?.toInt();
      final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      final dt = DateTime.tryParse(p['created_at'] as String? ?? '');
      if (cid == null || amt <= 0.01 || dt == null) continue;
      paymentsByCust.putIfAbsent(cid, () => []).add((createdAt: dt, amount: amt));
    }

    double weightedDayRupees = 0.0;
    double totalAllocated = 0.0;

    for (final entry in ordersByCust.entries) {
      final custOrders = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final custPays = paymentsByCust[entry.key];
      if (custPays == null || custPays.isEmpty) continue;
      custPays.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      var oIdx = 0;
      var pIdx = 0;
      var oRem = custOrders[0].total;
      var pRem = custPays[0].amount;

      while (oIdx < custOrders.length && pIdx < custPays.length) {
        final alloc = math.min(oRem, pRem);
        if (alloc > 0.001) {
          final hours =
              custPays[pIdx].createdAt.difference(custOrders[oIdx].createdAt).inHours;
          final days = hours <= 0 ? 0.0 : (hours / 24.0).clamp(0.0, 365.0);
          weightedDayRupees += days * alloc;
          totalAllocated += alloc;
        }
        oRem -= alloc;
        pRem -= alloc;
        if (oRem <= 0.001) {
          oIdx++;
          if (oIdx < custOrders.length) oRem = custOrders[oIdx].total;
        }
        if (pRem <= 0.001) {
          pIdx++;
          if (pIdx < custPays.length) pRem = custPays[pIdx].amount;
        }
      }
    }

    if (totalAllocated <= 0.01) return null;
    return weightedDayRupees / totalAllocated;
  }

}
