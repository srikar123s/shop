import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/firebase_options.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/product.dart';
import 'package:shop/models/shop_profile.dart';
import 'package:sqflite/sqflite.dart';

enum SyncStatus {
  notConfigured,
  connecting,
  connected,
  syncing,
  offline,
  error,
}

class ShopSyncService extends ChangeNotifier {
  ShopSyncService._();
  static final ShopSyncService instance = ShopSyncService._();

  static const String _prefKeyShopProfile = 'shop_sync_profile';
  static const String _prefKeyDeviceId = 'shop_sync_device_id';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  ShopProfile? _currentShop;
  SyncStatus _status = SyncStatus.notConfigured;
  String _statusMessage = 'Cloud sync not initialized';
  DateTime? _lastSyncTime;
  String? _deviceId;
  bool _isFirebaseAvailable = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _customersSub;

  ShopProfile? get currentShop => _currentShop;
  SyncStatus get status => _status;
  String get statusMessage => _statusMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isConnected => _status == SyncStatus.connected || _status == SyncStatus.syncing;
  bool get hasShop => _currentShop != null && _currentShop!.shopCode.isNotEmpty;
  bool get isFirebaseAvailable => _isFirebaseAvailable;
  String get deviceId => _deviceId ?? 'unknown';

  /// Initializes the sync service, loads local shop profile, and tests Firebase.
  Future<void> initialize() async {
    _status = SyncStatus.connecting;
    _statusMessage = 'Connecting to shop services...';
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(_prefKeyDeviceId);
      if (_deviceId == null) {
        _deviceId = 'dev_${Random().nextInt(899999) + 100000}';
        await prefs.setString(_prefKeyDeviceId, _deviceId!);
      }

      final profileJson = prefs.getString(_prefKeyShopProfile);
      if (profileJson != null && profileJson.isNotEmpty) {
        _currentShop = ShopProfile.fromJson(profileJson);
      }

      // Check / initialize Firebase
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        _isFirebaseAvailable = true;
      } catch (fbErr) {
        try {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp();
          }
          _isFirebaseAvailable = true;
        } catch (e2) {
          _isFirebaseAvailable = false;
          debugPrint('Firebase not initialized yet: $e2');
        }
      }

      if (_currentShop != null && _isFirebaseAvailable) {
        _status = SyncStatus.connected;
        _statusMessage = 'Synced with ${_currentShop!.shopName}';
        _startRealtimeListeners();
      } else if (_currentShop != null) {
        _status = SyncStatus.offline;
        _statusMessage = 'Offline (Firebase pending setup)';
      } else {
        _status = SyncStatus.notConfigured;
        _statusMessage = 'No shop linked yet';
      }
    } catch (e) {
      _status = SyncStatus.error;
      _statusMessage = 'Sync error: $e';
    }
    notifyListeners();
  }

  /// Generates a random readable 6-character Shop Code e.g. "SH-8429"
  String generateShopCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final randomDigits = List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'SH-$randomDigits';
  }

  /// Create a new shop in cloud (for owner)
  Future<ShopProfile> createShop({
    required String shopName,
    required String ownerName,
    required String ownerPhone,
    String address = '',
    String gstin = '',
    double defaultGstRate = 18.0,
  }) async {
    _status = SyncStatus.syncing;
    _statusMessage = 'Registering new shop...';
    notifyListeners();

    final code = generateShopCode();
    final profile = ShopProfile(
      shopCode: code,
      shopName: shopName.trim(),
      ownerName: ownerName.trim(),
      ownerPhone: ownerPhone.trim(),
      address: address.trim(),
      gstin: gstin.trim(),
      defaultGstRate: defaultGstRate,
      role: 'owner',
      staffName: ownerName.trim().isNotEmpty ? ownerName.trim() : 'Owner',
      createdAt: DateTime.now(),
      lastSyncedAt: DateTime.now(),
      isCloudEnabled: _isFirebaseAvailable,
    );

    // Save locally
    _currentShop = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyShopProfile, profile.toJson());

    // Save to Firestore if available
    if (_isFirebaseAvailable) {
      try {
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('shops').doc(code).set({
          ...profile.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByDevice': _deviceId,
        });

        // Push existing local items into the newly created cloud shop
        await uploadLocalDataToCloud();

        _status = SyncStatus.connected;
        _statusMessage = 'Shop created and live synced!';
        _startRealtimeListeners();
      } catch (e) {
        debugPrint('Error uploading shop to Firestore: $e');
        _status = SyncStatus.offline;
        _statusMessage = 'Created locally. Cloud sync offline ($e)';
      }
    } else {
      _status = SyncStatus.offline;
      _statusMessage = 'Shop created in local mode';
    }

    notifyListeners();
    return profile;
  }

  /// Join an existing shop via Shop Code (for staff/cashier)
  Future<bool> joinShop({
    required String shopCode,
    required String staffName,
  }) async {
    _status = SyncStatus.syncing;
    _statusMessage = 'Connecting to shop $shopCode...';
    notifyListeners();

    final normalizedCode = shopCode.trim().toUpperCase();

    if (!_isFirebaseAvailable) {
      _status = SyncStatus.error;
      _statusMessage = 'Firebase not connected. Cannot find shop online.';
      notifyListeners();
      return false;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('shops').doc(normalizedCode).get();

      if (!doc.exists || doc.data() == null) {
        _status = SyncStatus.error;
        _statusMessage = 'Shop code "$normalizedCode" not found! Please check and try again.';
        notifyListeners();
        return false;
      }

      final data = doc.data()!;
      final profile = ShopProfile.fromMap(data).copyWith(
        role: 'staff',
        staffName: staffName.trim().isNotEmpty ? staffName.trim() : 'Staff',
        lastSyncedAt: DateTime.now(),
        isCloudEnabled: true,
      );

      _currentShop = profile;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyShopProfile, profile.toJson());

      // Download all existing products, customers, and orders from cloud
      await downloadCloudDataToLocal();

      _status = SyncStatus.connected;
      _statusMessage = 'Successfully joined ${profile.shopName}!';
      _startRealtimeListeners();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error joining shop: $e');
      _status = SyncStatus.error;
      _statusMessage = 'Could not join shop: $e';
      notifyListeners();
      return false;
    }
  }

  /// Disconnect / Leave current shop
  Future<void> leaveShop() async {
    _stopRealtimeListeners();
    _currentShop = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyShopProfile);
    _status = SyncStatus.notConfigured;
    _statusMessage = 'No shop linked';
    notifyListeners();
  }

  /// Uploads all local SQLite products, customers, and orders to Firestore
  Future<void> uploadLocalDataToCloud() async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    final db = await _dbHelper.database;

    // 1. Products
    final products = await db.query('products');
    final productBatch = firestore.batch();
    for (final p in products) {
      final docRef = firestore.collection('shops').doc(shopCode).collection('products').doc('${p['id']}');
      productBatch.set(docRef, {
        'id': p['id'],
        'name': p['name'],
        'category': p['category'],
        'is_active': p['is_active'],
        'configuration': p['configuration'],
        'created_at': p['created_at'],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
    }
    await productBatch.commit();

    // 2. Customers
    final customers = await db.query('customers');
    final custBatch = firestore.batch();
    for (final c in customers) {
      final docRef = firestore.collection('shops').doc(shopCode).collection('customers').doc('${c['id']}');
      custBatch.set(docRef, {
        'id': c['id'],
        'name': c['name'],
        'phone': c['phone'],
        'address': c['address'],
        'created_at': c['created_at'],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
    }
    await custBatch.commit();

    // 3. Orders with items
    final orders = await db.query('orders');
    for (final o in orders) {
      final orderId = o['id'] as int;
      final items = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      
      final itemsPayload = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemId = item['id'] as int;
        final options = await db.query('order_item_options', where: 'order_item_id = ?', whereArgs: [itemId]);
        final optionsMap = <String, String>{};
        for (final opt in options) {
          optionsMap[opt['option_name'] as String] = opt['option_value'] as String;
        }

        itemsPayload.add({
          'id': item['id'],
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'],
          'unit': item['unit'],
          'unit_price': item['unit_price'],
          'status': item['status'],
          'is_other_item': item['is_other_item'],
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': item['product_snapshot'],
          'options': optionsMap,
        });
      }

      await firestore.collection('shops').doc(shopCode).collection('orders').doc('$orderId').set({
        'id': o['id'],
        'customer_id': o['customer_id'],
        'customer_name_snapshot': o['customer_name_snapshot'],
        'created_at': o['created_at'],
        'status': o['status'],
        'notes': o['notes'],
        'estimate_total': o['estimate_total'],
        'items': itemsPayload,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
    }

    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  /// Downloads all cloud products, customers, and orders into local SQLite
  Future<void> downloadCloudDataToLocal() async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    final db = await _dbHelper.database;

    // 1. Sync Products
    final productSnaps = await firestore.collection('shops').doc(shopCode).collection('products').get();
    for (final doc in productSnaps.docs) {
      final data = doc.data();
      await db.insert('products', {
        'id': data['id'],
        'name': data['name'],
        'category': data['category'],
        'is_active': data['is_active'] ?? 1,
        'configuration': data['configuration'],
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 2. Sync Customers
    final custSnaps = await firestore.collection('shops').doc(shopCode).collection('customers').get();
    for (final doc in custSnaps.docs) {
      final data = doc.data();
      await db.insert('customers', {
        'id': data['id'],
        'name': data['name'],
        'phone': data['phone'],
        'address': data['address'],
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 3. Sync Orders
    final orderSnaps = await firestore.collection('shops').doc(shopCode).collection('orders').get();
    for (final doc in orderSnaps.docs) {
      final data = doc.data();
      final orderId = data['id'] as int;

      await db.insert('orders', {
        'id': orderId,
        'customer_id': data['customer_id'],
        'customer_name_snapshot': data['customer_name_snapshot'],
        'created_at': data['created_at'],
        'status': data['status'],
        'notes': data['notes'],
        'estimate_total': data['estimate_total'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Re-populate order items
      final rawItems = data['items'] as List<dynamic>? ?? [];
      for (final rawItem in rawItems) {
        final item = rawItem as Map<String, dynamic>;
        final itemId = item['id'] as int? ?? Random().nextInt(1000000);
        await db.insert('order_items', {
          'id': itemId,
          'order_id': orderId,
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'] ?? 0,
          'unit': item['unit'],
          'unit_price': item['unit_price'],
          'status': item['status'],
          'is_other_item': item['is_other_item'] ?? 0,
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': item['product_snapshot'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final rawOptions = item['options'] as Map<String, dynamic>? ?? {};
        for (final optEntry in rawOptions.entries) {
          await db.insert('order_item_options', {
            'order_item_id': itemId,
            'option_name': optEntry.key,
            'option_value': optEntry.value.toString(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }

    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  /// Push a single newly created or updated order to the cloud in real-time
  Future<void> syncOrder(int orderId) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final shopCode = _currentShop!.shopCode;
      final db = await _dbHelper.database;

      final orderRows = await db.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (orderRows.isEmpty) return;
      final o = orderRows.first;

      final items = await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
      final itemsPayload = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemId = item['id'] as int;
        final options = await db.query('order_item_options', where: 'order_item_id = ?', whereArgs: [itemId]);
        final optionsMap = <String, String>{};
        for (final opt in options) {
          optionsMap[opt['option_name'] as String] = opt['option_value'] as String;
        }

        itemsPayload.add({
          'id': item['id'],
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'],
          'unit': item['unit'],
          'unit_price': item['unit_price'],
          'status': item['status'],
          'is_other_item': item['is_other_item'],
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': item['product_snapshot'],
          'options': optionsMap,
        });
      }

      await firestore.collection('shops').doc(shopCode).collection('orders').doc('$orderId').set({
        'id': o['id'],
        'customer_id': o['customer_id'],
        'customer_name_snapshot': o['customer_name_snapshot'],
        'created_at': o['created_at'],
        'status': o['status'],
        'notes': o['notes'],
        'estimate_total': o['estimate_total'],
        'items': itemsPayload,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));

      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing order $orderId: $e');
    }
  }

  /// Push a single product to cloud
  Future<void> syncProduct(Product product) async {
    if (_currentShop == null || !_isFirebaseAvailable || product.id == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final shopCode = _currentShop!.shopCode;
      await firestore.collection('shops').doc(shopCode).collection('products').doc('${product.id}').set({
        ...product.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing product ${product.id}: $e');
    }
  }

  /// Push a single customer to cloud
  Future<void> syncCustomer(Customer customer) async {
    if (_currentShop == null || !_isFirebaseAvailable || customer.id == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final shopCode = _currentShop!.shopCode;
      await firestore.collection('shops').doc(shopCode).collection('customers').doc('${customer.id}').set({
        ...customer.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing customer ${customer.id}: $e');
    }
  }

  /// Start live listeners for real-time collaboration
  void _startRealtimeListeners() {
    _stopRealtimeListeners();
    if (_currentShop == null || !_isFirebaseAvailable) return;

    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;

    // 1. Orders live stream
    _ordersSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('orders')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          // Ignore echo if we just pushed it from this device
          if (data['lastUpdatedByDevice'] == _deviceId) continue;

          final orderId = data['id'] as int;
          await db.insert('orders', {
            'id': orderId,
            'customer_id': data['customer_id'],
            'customer_name_snapshot': data['customer_name_snapshot'],
            'created_at': data['created_at'],
            'status': data['status'],
            'notes': data['notes'],
            'estimate_total': data['estimate_total'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          final rawItems = data['items'] as List<dynamic>? ?? [];
          for (final rawItem in rawItems) {
            final item = rawItem as Map<String, dynamic>;
            final itemId = item['id'] as int? ?? Random().nextInt(1000000);
            await db.insert('order_items', {
              'id': itemId,
              'order_id': orderId,
              'product_id': item['product_id'],
              'item_name': item['item_name'],
              'quantity_ordered': item['quantity_ordered'],
              'quantity_given': item['quantity_given'] ?? 0,
              'unit': item['unit'],
              'unit_price': item['unit_price'],
              'status': item['status'],
              'is_other_item': item['is_other_item'] ?? 0,
              'procurement_status': item['procurement_status'],
              'details': item['details'],
              'notes': item['notes'],
              'product_snapshot': item['product_snapshot'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);

            final rawOptions = item['options'] as Map<String, dynamic>? ?? {};
            for (final optEntry in rawOptions.entries) {
              await db.insert('order_item_options', {
                'order_item_id': itemId,
                'option_name': optEntry.key,
                'option_value': optEntry.value.toString(),
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });

    // 2. Products live stream
    _productsSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('products')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;

          await db.insert('products', {
            'id': data['id'],
            'name': data['name'],
            'category': data['category'],
            'is_active': data['is_active'] ?? 1,
            'configuration': data['configuration'],
            'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });

    // 3. Customers live stream
    _customersSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('customers')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;

          await db.insert('customers', {
            'id': data['id'],
            'name': data['name'],
            'phone': data['phone'],
            'address': data['address'],
            'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });
  }

  void _stopRealtimeListeners() {
    _ordersSub?.cancel();
    _ordersSub = null;
    _productsSub?.cancel();
    _productsSub = null;
    _customersSub?.cancel();
    _customersSub = null;
  }

  @override
  void dispose() {
    _stopRealtimeListeners();
    super.dispose();
  }
}

