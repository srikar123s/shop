import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/firebase_options.dart';
import 'package:shop/models/customer.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/models/shop_profile.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:sqflite/sqflite.dart';

enum SyncStatus {
  notConfigured,
  connecting,
  pendingApproval,
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paymentsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deviceSub;

  StaffDevice? _myDevicePermissions;

  ShopProfile? get currentShop => _currentShop;
  SyncStatus get status => _status;
  String get statusMessage => _statusMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isConnected =>
      !ShopCustomizationService.instance.isPureOfflineMode &&
      (_status == SyncStatus.connected || _status == SyncStatus.syncing);
  bool get isPendingApproval =>
      !ShopCustomizationService.instance.isPureOfflineMode &&
      (_status == SyncStatus.pendingApproval ||
          (_currentShop != null &&
              !_currentShop!.isOwner &&
              _currentShop!.isPending));
  bool get hasShop =>
      !ShopCustomizationService.instance.isPureOfflineMode &&
      _currentShop != null &&
      _currentShop!.shopCode.isNotEmpty;
  bool get isFirebaseAvailable => _isFirebaseAvailable;
  String get deviceId => _deviceId ?? 'unknown';

  bool get canChangePrice =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canChangePrice ?? true);
  bool get canManageProducts =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canManageProducts ?? true);
  bool get canCloseOrders =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canCloseOrders ?? true);
  bool get canChangeShortcuts =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canChangeShortcuts ?? true);
  bool get canViewBillTotals =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canViewBillTotals ?? true);

  String get currentUserOrDeviceName {
    final shop = _currentShop;
    if (shop != null) {
      if (shop.isOwner) {
        return shop.ownerName.trim().isNotEmpty ? shop.ownerName.trim() : 'Srikar';
      } else {
        return shop.staffName.trim().isNotEmpty ? shop.staffName.trim() : 'Staff';
      }
    }
    return 'Srikar';
  }


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
        try {
          final auth = FirebaseAuth.instance;
          if (auth.currentUser == null) {
            await auth.signInAnonymously();
          }
          if (auth.currentUser != null) {
            _deviceId = auth.currentUser!.uid;
            await prefs.setString(_prefKeyDeviceId, _deviceId!);
          }
        } catch (authErr) {
          debugPrint('Firebase Auth anonymous sign-in: $authErr');
        }
      } catch (fbErr) {
        try {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp();
          }
          _isFirebaseAvailable = true;
        try {
          final auth = FirebaseAuth.instance;
          if (auth.currentUser == null) {
            await auth.signInAnonymously();
          }
          if (auth.currentUser != null) {
            _deviceId = auth.currentUser!.uid;
            await prefs.setString(_prefKeyDeviceId, _deviceId!);
          }
        } catch (authErr) {
          debugPrint('Firebase Auth anonymous sign-in: $authErr');
        }
        } catch (e2) {
          _isFirebaseAvailable = false;
          debugPrint('Firebase not initialized yet: $e2');
        }
      }

      if (_currentShop != null && _isFirebaseAvailable) {
        if (_currentShop!.isOwner) {
          _status = SyncStatus.connected;
          _statusMessage = 'Synced with ${_currentShop!.shopName}';
          unawaited(FirebaseFirestore.instance
              .collection('shops')
              .doc(_currentShop!.shopCode)
              .set({
            ..._currentShop!.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastUpdatedByDevice': _deviceId,
          }, SetOptions(merge: true)));
          _startRealtimeListeners();
          unawaited(_registerCurrentDevice());
        } else {
          // Staff Device
          if (_currentShop!.isPending) {
            _status = SyncStatus.pendingApproval;
            _statusMessage = 'Waiting for shop owner to accept request...';
            _listenForStaffApproval(_currentShop!.shopCode);
          } else {
            _status = SyncStatus.connected;
            _statusMessage = 'Synced with ${_currentShop!.shopName}';
            _startRealtimeListeners();
            unawaited(_registerCurrentDevice());
          }
        }
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

  String _cleanErrorMessage(dynamic e) {
    final str = e.toString();
    if (str.contains('permission-denied')) {
      return 'Firebase Rules locked: Please ensure the Firestore rules from firestore.rules are published in your Firebase Console.';
    }
    if (str.contains('unavailable') || str.contains('network')) {
      return 'Network offline. Please check your internet connection.';
    }
    return str;
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final profile = ShopProfile(
      shopCode: code,
      shopName: shopName.trim(),
      ownerUid: currentUid,
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
          'ownerUid': currentUid,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByDevice': _deviceId,
        });

        // Register owner device first so security rules authorize subcollection writes
        await _registerCurrentDevice();

        // Push existing local items into the newly created cloud shop
        await uploadLocalDataToCloud();

        _status = SyncStatus.connected;
        _statusMessage = 'Shop created and live synced!';
        _startRealtimeListeners();
      } catch (e) {
        debugPrint('Error uploading shop to Firestore: $e');
        _status = SyncStatus.offline;
        _statusMessage = _cleanErrorMessage(e);
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

    var normalizedCode = shopCode.trim().toUpperCase().replaceAll(' ', '');
    if (!normalizedCode.contains('-') && normalizedCode.startsWith('SH') && normalizedCode.length > 2) {
      normalizedCode = 'SH-${normalizedCode.substring(2)}';
    } else if (!normalizedCode.startsWith('SH-') && normalizedCode.length == 4) {
      normalizedCode = 'SH-$normalizedCode';
    }

    if (!_isFirebaseAvailable) {
      _status = SyncStatus.error;
      _statusMessage = 'Firebase not connected. Cannot find shop online.';
      notifyListeners();
      return false;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('shops').doc(normalizedCode).get();

      Map<String, dynamic> data;
      if (doc.exists && doc.data() != null) {
        data = doc.data()!;
      } else {
        // Fallback: check if subcollections exist under this shopCode
        final prodCheck = await firestore
            .collection('shops')
            .doc(normalizedCode)
            .collection('products')
            .limit(1)
            .get();
        if (prodCheck.docs.isNotEmpty) {
          data = {
            'shopCode': normalizedCode,
            'shopName': 'Shop ($normalizedCode)',
          };
        } else {
          _status = SyncStatus.error;
          _statusMessage = 'Shop code "$normalizedCode" not found! Please check and try again.';
          notifyListeners();
          return false;
        }
      }

      final profile = ShopProfile.fromMap(data).copyWith(
        role: 'staff',
        staffName: staffName.trim().isNotEmpty ? staffName.trim() : 'Staff',
        status: 'pending',
        lastSyncedAt: DateTime.now(),
        isCloudEnabled: true,
      );

      _currentShop = profile;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyShopProfile, profile.toJson());

      // Register device request as 'pending' in Firestore
      await firestore
          .collection('shops')
          .doc(normalizedCode)
          .collection('devices')
          .doc(_deviceId!)
          .set({
        'deviceId': _deviceId,
        'staffName': profile.staffName,
        'role': 'staff',
        'status': 'pending',
        'canChangePrice': false,
        'canManageProducts': false,
        'canCloseOrders': true,
        'canChangeShortcuts': false,
        'canViewBillTotals': true,
        'requestedAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _status = SyncStatus.pendingApproval;
      _statusMessage = 'Request sent to shop owner. Waiting for approval...';
      _listenForStaffApproval(normalizedCode);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error joining shop: $e');
      _status = SyncStatus.error;
      _statusMessage = _cleanErrorMessage(e);
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

    try {
      // 0. Ensure root Shop Profile document exists in Firestore!
      await firestore.collection('shops').doc(shopCode).set({
        ..._currentShop!.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));

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
        'price_updated_at': p['price_updated_at'],
        'needs_review': p['needs_review'] ?? 0,
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

        double unitPrice = 0.0;
        final rawSnap = item['product_snapshot'] as String?;
        if (rawSnap != null && rawSnap.isNotEmpty) {
          try {
            final snapMap = jsonDecode(rawSnap) as Map<String, dynamic>;
            unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }

        itemsPayload.add({
          'id': item['id'],
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'],
          'unit': item['unit'],
          'unit_price': unitPrice,
          'status': item['status'],
          'is_other_item': item['is_other_item'],
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': rawSnap ?? '{}',
          'options': optionsMap,
        });
      }

      final notes = o['notes'] as String?;
      final breakdown = BillBreakdown.fromJsonString(notes);
      final customerPhone =
          (o['customer_phone'] as String?) ?? breakdown?.customerPhone;
      final takenBy =
          (o['taken_by'] as String?) ?? breakdown?.takenBy ?? 'Store';

      final cloudDocId = (o['cloud_order_id'] as String?) ?? '${_deviceId}_$orderId';
      if (o['cloud_order_id'] == null) {
        await db.update('orders', {'cloud_order_id': cloudDocId}, where: 'id = ?', whereArgs: [orderId]);
      }

      await firestore.collection('shops').doc(shopCode).collection('orders').doc(cloudDocId).set({
        'id': o['id'],
        'cloud_order_id': cloudDocId,
        'customer_id': o['customer_id'],
        'customer_name_snapshot': o['customer_name_snapshot'],
        'customer_phone': customerPhone,
        'taken_by': takenBy,
        'created_at': o['created_at'],
        'status': o['status'],
        'notes': o['notes'],
        'estimate_total': o['estimate_total'],
        'paid_amount': o['paid_amount'] ?? 0.0,
        'payment_mode': o['payment_mode'] ?? 'unpaid',
        'payment_status': o['payment_status'] ?? 'unpaid',
        'items': itemsPayload,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
    }

    // 4. Payments
    final payments = await db.query('customer_payments');
    final payBatch = firestore.batch();
    for (final p in payments) {
      final payId = p['id'] as int;
      final cloudDocId = (p['cloud_payment_id'] as String?) ?? '${_deviceId}_$payId';
      if (p['cloud_payment_id'] == null) {
        await db.update('customer_payments', {'cloud_payment_id': cloudDocId}, where: 'id = ?', whereArgs: [payId]);
      }
      final docRef = firestore.collection('shops').doc(shopCode).collection('payments').doc(cloudDocId);
      payBatch.set(docRef, {
        'id': p['id'],
        'cloud_payment_id': cloudDocId,
        'customer_id': p['customer_id'],
        'amount': p['amount'],
        'payment_mode': p['payment_mode'],
        'notes': p['notes'],
        'created_at': p['created_at'],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));
    }
    await payBatch.commit();

      _lastSyncTime = DateTime.now();
      _status = SyncStatus.connected;
      _statusMessage = 'Synced with ${_currentShop!.shopName}';
      notifyListeners();
    } catch (e) {
      debugPrint('Error uploading local data to cloud: $e');
      _status = SyncStatus.offline;
      _statusMessage = _cleanErrorMessage(e);
      notifyListeners();
      rethrow;
    }
  }

  /// Downloads all cloud products, customers, and orders into local SQLite
  Future<void> downloadCloudDataToLocal() async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    final db = await _dbHelper.database;

    try {
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
        'price_updated_at': data['price_updated_at'],
        'needs_review': data['needs_review'] ?? 0,
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
      final rawNotes = data['notes'] as String?;
      final incomingBreakdown = BillBreakdown.fromJsonString(rawNotes);
      final incomingPhone = (data['customer_phone'] as String?) ??
          incomingBreakdown?.customerPhone;
      final incomingTakenBy =
          (data['taken_by'] as String?) ?? incomingBreakdown?.takenBy ?? 'Store';

      int localCustId = data['customer_id'] as int? ?? 1;
      final custName =
          data['customer_name_snapshot'] as String? ?? 'Customer';
      if (incomingPhone != null && incomingPhone.isNotEmpty) {
        final existingCust = await db.query('customers',
            where: 'phone = ?', whereArgs: [incomingPhone]);
        if (existingCust.isNotEmpty) {
          localCustId = existingCust.first['id'] as int;
        } else {
          localCustId = await db.insert('customers', {
            'name': custName,
            'phone': incomingPhone,
            'created_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          if (localCustId <= 0) {
            final existing = await db.query('customers',
                where: 'phone = ?', whereArgs: [incomingPhone]);
            localCustId = existing.isNotEmpty ? existing.first['id'] as int : 1;
          }
        }
      } else {
        final existingCust = await db.query('customers',
            where: 'LOWER(TRIM(name)) = ?',
            whereArgs: [custName.trim().toLowerCase()]);
        if (existingCust.isNotEmpty) {
          localCustId = existingCust.first['id'] as int;
        }
      }

      final cloudDocId = doc.id;
      final existingOrder = await db.query('orders', where: 'cloud_order_id = ?', whereArgs: [cloudDocId]);
      int targetOrderId;
      if (existingOrder.isNotEmpty) {
        targetOrderId = existingOrder.first['id'] as int;
        await db.update('orders', {
          'customer_id': localCustId,
          'customer_name_snapshot': custName,
          'customer_phone': incomingPhone,
          'taken_by': incomingTakenBy,
          'status': data['status'],
          'notes': data['notes'],
          'estimate_total': data['estimate_total'],
          'paid_amount': data['paid_amount'] ?? 0.0,
          'payment_mode': data['payment_mode'] ?? 'unpaid',
          'payment_status': data['payment_status'] ?? 'unpaid',
        }, where: 'id = ?', whereArgs: [targetOrderId]);
      } else {
        targetOrderId = await db.insert('orders', {
          'cloud_order_id': cloudDocId,
          'customer_id': localCustId,
          'customer_name_snapshot': custName,
          'customer_phone': incomingPhone,
          'taken_by': incomingTakenBy,
          'created_at': data['created_at'],
          'status': data['status'],
          'notes': data['notes'],
          'estimate_total': data['estimate_total'],
          'paid_amount': data['paid_amount'] ?? 0.0,
          'payment_mode': data['payment_mode'] ?? 'unpaid',
          'payment_status': data['payment_status'] ?? 'unpaid',
        });
      }

      // Re-populate order items cleanly (delete existing to avoid duplicate items/options accumulation)
      final existingItems = await db.query('order_items', columns: ['id'], where: 'order_id = ?', whereArgs: [targetOrderId]);
      for (final ei in existingItems) {
        final eid = ei['id'] as int;
        await db.delete('order_item_options', where: 'order_item_id = ?', whereArgs: [eid]);
      }
      await db.delete('order_items', where: 'order_id = ?', whereArgs: [targetOrderId]);

      final rawItems = data['items'] as List<dynamic>? ?? [];
      for (final rawItem in rawItems) {
        final item = (rawItem as Map).cast<String, dynamic>();
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final snapString = item['product_snapshot'] as String? ?? jsonEncode({
          'itemName': item['item_name'],
          'unitPrice': unitPrice,
          'options': item['options'] ?? {},
        });
        final localItemId = await db.insert('order_items', {
          'order_id': targetOrderId,
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'] ?? 0,
          'unit': item['unit'],
          'unit_price': unitPrice,
          'status': item['status'],
          'is_other_item': item['is_other_item'] ?? 0,
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': snapString,
        });

        final rawOptions = (item['options'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        for (final optEntry in rawOptions.entries) {
          await db.insert('order_item_options', {
            'order_item_id': localItemId,
            'option_name': optEntry.key,
            'option_value': optEntry.value.toString(),
          });
        }
      }
    }

    // 4. Sync Payments
    final paySnaps = await firestore.collection('shops').doc(shopCode).collection('payments').get();
    for (final doc in paySnaps.docs) {
      final data = doc.data();
      final cloudDocId = doc.id;
      final existingPay = await db.query('customer_payments', where: 'cloud_payment_id = ?', whereArgs: [cloudDocId]);
      if (existingPay.isNotEmpty) {
        await db.update('customer_payments', {
          'customer_id': data['customer_id'],
          'amount': data['amount'],
          'payment_mode': data['payment_mode'] ?? 'cash',
          'notes': data['notes'],
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [existingPay.first['id']]);
      } else {
        await db.insert('customer_payments', {
          'cloud_payment_id': cloudDocId,
          'customer_id': data['customer_id'],
          'amount': data['amount'],
          'payment_mode': data['payment_mode'] ?? 'cash',
          'notes': data['notes'],
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
        });
      }
    }

      _lastSyncTime = DateTime.now();
      _status = SyncStatus.connected;
      _statusMessage = 'Synced with ${_currentShop!.shopName}';
      notifyListeners();
    } catch (e) {
      debugPrint('Error downloading cloud data to local: $e');
      _status = SyncStatus.offline;
      _statusMessage = _cleanErrorMessage(e);
      notifyListeners();
      rethrow;
    }
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

        double unitPrice = 0.0;
        final rawSnap = item['product_snapshot'] as String?;
        if (rawSnap != null && rawSnap.isNotEmpty) {
          try {
            final snapMap = jsonDecode(rawSnap) as Map<String, dynamic>;
            unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }

        itemsPayload.add({
          'id': item['id'],
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'],
          'unit': item['unit'],
          'unit_price': unitPrice,
          'status': item['status'],
          'is_other_item': item['is_other_item'],
          'procurement_status': item['procurement_status'],
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': rawSnap ?? '{}',
          'options': optionsMap,
        });
      }

      final notes = o['notes'] as String?;
      final breakdown = BillBreakdown.fromJsonString(notes);
      final customerPhone =
          (o['customer_phone'] as String?) ?? breakdown?.customerPhone;
      final takenBy =
          (o['taken_by'] as String?) ?? breakdown?.takenBy ?? 'Store';

      final cloudDocId = (o['cloud_order_id'] as String?) ?? '${_deviceId}_$orderId';
      if (o['cloud_order_id'] == null) {
        await db.update('orders', {'cloud_order_id': cloudDocId}, where: 'id = ?', whereArgs: [orderId]);
      }

      await firestore.collection('shops').doc(shopCode).collection('orders').doc(cloudDocId).set({
        'id': o['id'],
        'cloud_order_id': cloudDocId,
        'customer_id': o['customer_id'],
        'customer_name_snapshot': o['customer_name_snapshot'],
        'customer_phone': customerPhone,
        'taken_by': takenBy,
        'created_at': o['created_at'],
        'status': o['status'],
        'notes': o['notes'],
        'estimate_total': o['estimate_total'],
        'paid_amount': o['paid_amount'] ?? 0.0,
        'payment_mode': o['payment_mode'] ?? 'unpaid',
        'payment_status': o['payment_status'] ?? 'unpaid',
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

  /// Push a single customer payment to cloud
  Future<void> syncPayment(int paymentId) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final shopCode = _currentShop!.shopCode;
      final db = await _dbHelper.database;

      final pRows = await db.query('customer_payments', where: 'id = ?', whereArgs: [paymentId]);
      if (pRows.isEmpty) return;
      final p = pRows.first;

      final cloudDocId = (p['cloud_payment_id'] as String?) ?? '${_deviceId}_$paymentId';
      if (p['cloud_payment_id'] == null) {
        await db.update('customer_payments', {'cloud_payment_id': cloudDocId}, where: 'id = ?', whereArgs: [paymentId]);
      }

      await firestore.collection('shops').doc(shopCode).collection('payments').doc(cloudDocId).set({
        'id': p['id'],
        'cloud_payment_id': cloudDocId,
        'customer_id': p['customer_id'],
        'amount': p['amount'],
        'payment_mode': p['payment_mode'],
        'notes': p['notes'],
        'created_at': p['created_at'],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      }, SetOptions(merge: true));

      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing payment $paymentId: $e');
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

          final rawNotes = data['notes'] as String?;
          final incomingBreakdown = BillBreakdown.fromJsonString(rawNotes);
          final incomingPhone = (data['customer_phone'] as String?) ??
              incomingBreakdown?.customerPhone;
          final incomingTakenBy = (data['taken_by'] as String?) ??
              incomingBreakdown?.takenBy ??
              'Store';

          int localCustId = data['customer_id'] as int? ?? 1;
          final custName =
              data['customer_name_snapshot'] as String? ?? 'Customer';
          if (incomingPhone != null && incomingPhone.isNotEmpty) {
            final existingCust = await db.query('customers',
                where: 'phone = ?', whereArgs: [incomingPhone]);
            if (existingCust.isNotEmpty) {
              localCustId = existingCust.first['id'] as int;
            } else {
              localCustId = await db.insert('customers', {
                'name': custName,
                'phone': incomingPhone,
                'created_at': DateTime.now().toIso8601String(),
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
              if (localCustId <= 0) {
                final existing = await db.query('customers',
                    where: 'phone = ?', whereArgs: [incomingPhone]);
                localCustId = existing.isNotEmpty ? existing.first['id'] as int : 1;
              }
            }
          } else {
            final existingCust = await db.query('customers',
                where: 'LOWER(TRIM(name)) = ?',
                whereArgs: [custName.trim().toLowerCase()]);
            if (existingCust.isNotEmpty) {
              localCustId = existingCust.first['id'] as int;
            }
          }

          final cloudDocId = change.doc.id;
          final existing = await db.query('orders', where: 'cloud_order_id = ?', whereArgs: [cloudDocId]);
          int targetOrderId;
          if (existing.isNotEmpty) {
            targetOrderId = existing.first['id'] as int;
            await db.update('orders', {
              'customer_id': localCustId,
              'customer_name_snapshot': custName,
              'customer_phone': incomingPhone,
              'taken_by': incomingTakenBy,
              'status': data['status'],
              'notes': data['notes'],
              'estimate_total': data['estimate_total'],
              'paid_amount': data['paid_amount'] ?? 0.0,
              'payment_mode': data['payment_mode'] ?? 'unpaid',
              'payment_status': data['payment_status'] ?? 'unpaid',
            }, where: 'id = ?', whereArgs: [targetOrderId]);
          } else {
            targetOrderId = await db.insert('orders', {
              'cloud_order_id': cloudDocId,
              'customer_id': localCustId,
              'customer_name_snapshot': custName,
              'customer_phone': incomingPhone,
              'taken_by': incomingTakenBy,
              'created_at': data['created_at'],
              'status': data['status'],
              'notes': data['notes'],
              'estimate_total': data['estimate_total'],
              'paid_amount': data['paid_amount'] ?? 0.0,
              'payment_mode': data['payment_mode'] ?? 'unpaid',
              'payment_status': data['payment_status'] ?? 'unpaid',
            });
          }

          // Re-populate order items cleanly (delete existing to avoid duplicate items/options accumulation)
          final existingStreamItems = await db.query('order_items', columns: ['id'], where: 'order_id = ?', whereArgs: [targetOrderId]);
          for (final ei in existingStreamItems) {
            final eid = ei['id'] as int;
            await db.delete('order_item_options', where: 'order_item_id = ?', whereArgs: [eid]);
          }
          await db.delete('order_items', where: 'order_id = ?', whereArgs: [targetOrderId]);

          final rawItems = data['items'] as List<dynamic>? ?? [];
          for (final rawItem in rawItems) {
            final item = (rawItem as Map).cast<String, dynamic>();
            final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
            final snapString = item['product_snapshot'] as String? ?? jsonEncode({
              'itemName': item['item_name'],
              'unitPrice': unitPrice,
              'options': item['options'] ?? {},
            });
            final localItemId = await db.insert('order_items', {
              'order_id': targetOrderId,
              'product_id': item['product_id'],
              'item_name': item['item_name'],
              'quantity_ordered': item['quantity_ordered'],
              'quantity_given': item['quantity_given'] ?? 0,
              'unit': item['unit'],
              'unit_price': unitPrice,
              'status': item['status'],
              'is_other_item': item['is_other_item'] ?? 0,
              'procurement_status': item['procurement_status'],
              'details': item['details'],
              'notes': item['notes'],
              'product_snapshot': snapString,
            });

            final rawOptions = (item['options'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            for (final optEntry in rawOptions.entries) {
              await db.insert('order_item_options', {
                'order_item_id': localItemId,
                'option_name': optEntry.key,
                'option_value': optEntry.value.toString(),
              });
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
            'price_updated_at': data['price_updated_at'],
            'needs_review': data['needs_review'] ?? 0,
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

    // 4. Payments live stream
    _paymentsSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('payments')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;

          final cloudDocId = change.doc.id;
          final existingPay = await db.query('customer_payments', where: 'cloud_payment_id = ?', whereArgs: [cloudDocId]);
          if (existingPay.isNotEmpty) {
            await db.update('customer_payments', {
              'customer_id': data['customer_id'],
              'amount': data['amount'],
              'payment_mode': data['payment_mode'] ?? 'cash',
              'notes': data['notes'],
              'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [existingPay.first['id']]);
          } else {
            await db.insert('customer_payments', {
              'cloud_payment_id': cloudDocId,
              'customer_id': data['customer_id'],
              'amount': data['amount'],
              'payment_mode': data['payment_mode'] ?? 'cash',
              'notes': data['notes'],
              'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });

    // 5. Device permissions live stream (for staff devices)
    if (_currentShop?.isOwner == false && _deviceId != null) {
      _deviceSub = firestore
          .collection('shops')
          .doc(shopCode)
          .collection('devices')
          .doc(_deviceId!)
          .snapshots()
          .listen((snap) async {
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          _myDevicePermissions = StaffDevice.fromMap(data);
          final devStatus = (data['status'] as String? ?? 'approved').toLowerCase();
          if (devStatus == 'rejected') {
            _status = SyncStatus.error;
            _statusMessage = 'Access revoked by shop owner.';
            await leaveShop();
          }
          notifyListeners();
        }
      });
    }
  }

  void _listenForStaffApproval(String shopCode) {
    if (_deviceId == null || !_isFirebaseAvailable) return;
    _deviceSub?.cancel();
    _deviceSub = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopCode)
        .collection('devices')
        .doc(_deviceId!)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || snap.data() == null) return;
      final data = snap.data()!;
      _myDevicePermissions = StaffDevice.fromMap(data);
      final devStatus = (data['status'] as String? ?? 'pending').toLowerCase();
      if (devStatus == 'approved') {
        if (_currentShop != null && _currentShop!.isPending) {
          _currentShop = _currentShop!.copyWith(status: 'approved');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKeyShopProfile, _currentShop!.toJson());
          _status = SyncStatus.connected;
          _statusMessage = 'Approved! Synced with ${_currentShop!.shopName}';
          await downloadCloudDataToLocal();
          _startRealtimeListeners();
          notifyListeners();
        }
      } else if (devStatus == 'rejected') {
        _status = SyncStatus.error;
        _statusMessage = 'Join request was declined by the shop owner.';
        await leaveShop();
        notifyListeners();
      }
    });
  }

  Future<void> _registerCurrentDevice() async {
    if (_currentShop == null || !_isFirebaseAvailable || _deviceId == null) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('devices')
          .doc(_deviceId!);

      final existing = await docRef.get();
      final isOwner = _currentShop!.isOwner;
      final effectiveName = isOwner
          ? (_currentShop!.ownerName.isNotEmpty ? _currentShop!.ownerName : 'Owner')
          : (_currentShop!.staffName.isNotEmpty ? _currentShop!.staffName : 'Staff');

      if (!existing.exists) {
        await docRef.set({
          'deviceId': _deviceId,
          'staffName': effectiveName,
          'role': _currentShop!.role,
          'status': isOwner ? 'approved' : _currentShop!.status,
          'canChangePrice': isOwner,
          'canManageProducts': isOwner,
          'canCloseOrders': true,
          'canChangeShortcuts': isOwner,
          'canViewBillTotals': true,
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await docRef.set({
          'deviceId': _deviceId,
          'staffName': effectiveName,
          'role': _currentShop!.role,
          if (isOwner) 'status': 'approved',
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error registering device: $e');
    }
  }

  Stream<List<StaffDevice>> streamConnectedDevices() {
    if (_currentShop == null || !_isFirebaseAvailable) {
      return Stream.value([]);
    }
    return FirebaseFirestore.instance
        .collection('shops')
        .doc(_currentShop!.shopCode)
        .collection('devices')
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              try {
                final map = Map<String, dynamic>.from(d.data());
                map['deviceId'] = d.id;
                return StaffDevice.fromMap(map);
              } catch (e) {
                debugPrint('Error parsing StaffDevice ${d.id}: $e');
                return StaffDevice(
                  deviceId: d.id,
                  staffName: (d.data()['staffName'] as String?) ?? 'Staff Device',
                  role: (d.data()['role'] as String?) ?? 'staff',
                  status: (d.data()['status'] as String?) ?? 'approved',
                );
              }
            }).toList());
  }

  Future<void> approveStaffDevice(String targetDeviceId) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('devices')
          .doc(targetDeviceId)
          .set({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error approving device: $e');
    }
  }

  Future<void> rejectStaffDevice(String targetDeviceId) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('devices')
          .doc(targetDeviceId)
          .delete();
    } catch (e) {
      debugPrint('Error rejecting device: $e');
    }
  }

  Future<void> revokeStaffDevice(String targetDeviceId) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('devices')
          .doc(targetDeviceId)
          .set({
        'status': 'rejected',
        'revokedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error revoking device: $e');
    }
  }

  Future<void> updateDevicePermission({
    required String targetDeviceId,
    required String permissionKey,
    required bool value,
  }) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('devices')
          .doc(targetDeviceId)
          .set({
        permissionKey: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating device permission: $e');
    }
  }

  Future<void> updateShopProfileDetails({
    String? shopName,
    String? phone,
    String? address,
    String? gstin,
    String? upiId,
    String? digitalStamp,
  }) async {
    if (_currentShop == null) return;
    _currentShop = _currentShop!.copyWith(
      shopName: shopName?.trim() ?? _currentShop!.shopName,
      ownerPhone: phone?.trim() ?? _currentShop!.ownerPhone,
      address: address?.trim() ?? _currentShop!.address,
      gstin: gstin?.trim() ?? _currentShop!.gstin,
      upiId: upiId?.trim() ?? _currentShop!.upiId,
      digitalStamp: digitalStamp?.trim() ?? _currentShop!.digitalStamp,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyShopProfile, _currentShop!.toJson());
    if (_isFirebaseAvailable) {
      try {
        final updateMap = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (shopName != null) updateMap['shopName'] = shopName.trim();
        if (phone != null) updateMap['ownerPhone'] = phone.trim();
        if (address != null) updateMap['address'] = address.trim();
        if (gstin != null) updateMap['gstin'] = gstin.trim();
        if (upiId != null) updateMap['upiId'] = upiId.trim();
        if (digitalStamp != null) updateMap['digitalStamp'] = digitalStamp.trim();

        await FirebaseFirestore.instance
            .collection('shops')
            .doc(_currentShop!.shopCode)
            .set(updateMap, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating shop profile details online: $e');
      }
    }
    notifyListeners();
  }

  Future<void> updateShopName(String newName) async {
    await updateShopProfileDetails(shopName: newName);
  }

  void _stopRealtimeListeners() {
    _ordersSub?.cancel();
    _ordersSub = null;
    _productsSub?.cancel();
    _productsSub = null;
    _customersSub?.cancel();
    _customersSub = null;
    _paymentsSub?.cancel();
    _paymentsSub = null;
    _deviceSub?.cancel();
    _deviceSub = null;
  }

  @override
  void dispose() {
    _stopRealtimeListeners();
    super.dispose();
  }
}


