import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  static const String dbName = 'hardware_shop.db';
  static const int dbVersion = 2;

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

  Future<Database> _initDb() async {
    final path = await getDatabaseFullPath();
    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
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
}
