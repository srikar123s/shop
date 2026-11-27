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
import 'package:shop/models/delivery_partner.dart';
import 'package:shop/models/order.dart';
import 'package:shop/models/product.dart';
import 'package:shop/models/shop_profile.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/fcm_service.dart';
import 'package:shop/services/shop_customization_service.dart';
import 'package:shop/services/storage_monitor_service.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deliveryPartnersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deliveryLocationsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _deliveryTxSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deviceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _shopDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  DateTime _realtimeListenersStartedAt = DateTime.now();

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
  bool get isOwner =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true;

  bool get canChangePrice =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canChangePrice ?? false);
  bool get canManageProducts =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canManageProducts ?? false);
  bool get canCloseOrders =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canCloseOrders ?? true);
  bool get canChangeShortcuts =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canChangeShortcuts ?? false);
  bool get canViewBillTotals =>
      ShopCustomizationService.instance.isPureOfflineMode ||
      _currentShop == null ||
      _currentShop?.isOwner == true ||
      (_myDevicePermissions?.canViewBillTotals ?? true);

  String get currentUserOrDeviceName {
    final shop = _currentShop;
    if (shop != null) {
      if (shop.isOwner) {
        return shop.ownerName.trim().isNotEmpty ? shop.ownerName.trim() : 'Srikar';
      } else {
        return shop.staffName.trim().isNotEmpty ? shop.staffName.trim() : 'Partner Device';
      }
    }
    return 'Srikar';
  }


  Future<void> _ensureFirebaseInitializedAndSignedIn(SharedPreferences prefs) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _isFirebaseAvailable = true;
    } catch (_) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
        _isFirebaseAvailable = true;
      } catch (e2) {
        _isFirebaseAvailable = false;
        debugPrint('Firebase not initialized yet: $e2');
        return;
      }
    }

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
  }

  Future<void> _syncPublicInviteDoc(
    FirebaseFirestore firestore,
    ShopProfile shop,
  ) async {
    await firestore.collection('shop_invites').doc(shop.shopCode).set({
      'shopCode': shop.shopCode,
      'shopName': shop.shopName,
      'ownerName': shop.ownerName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

      await _ensureFirebaseInitializedAndSignedIn(prefs);

      if (_currentShop != null && _isFirebaseAvailable) {
        if (_currentShop!.isOwner) {
          _status = SyncStatus.connected;
          _statusMessage = 'Synced with ${_currentShop!.shopName}';
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          if (_currentShop!.ownerUid.isEmpty && currentUid.isNotEmpty) {
            _currentShop = _currentShop!.copyWith(ownerUid: currentUid);
            await prefs.setString(_prefKeyShopProfile, _currentShop!.toJson());
          }
          final shopRef =
              FirebaseFirestore.instance.collection('shops').doc(_currentShop!.shopCode);
          unawaited(shopRef.get().then((snap) async {
            if (!snap.exists) {
              await shopRef.set({
                ..._currentShop!.toMap(),
                if ((_currentShop!.ownerUid).isNotEmpty)
                  'ownerUid': _currentShop!.ownerUid
                else if (currentUid.isNotEmpty)
                  'ownerUid': currentUid,
                'updatedAt': FieldValue.serverTimestamp(),
                'lastUpdatedByDevice': _deviceId,
              }, SetOptions(merge: true));
            }
            await _syncPublicInviteDoc(FirebaseFirestore.instance, _currentShop!);
          }).catchError((e) {
            debugPrint('Error verifying root shop profile on init: $e');
          }));
          _startRealtimeListeners();
          unawaited(_registerCurrentDevice().catchError((e) {
            debugPrint('Error registering current device on init: $e');
          }));
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
            unawaited(_registerCurrentDevice().catchError((e) {
              debugPrint('Error registering staff device on init: $e');
            }));
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

    String code = generateShopCode();
    final prefs = await SharedPreferences.getInstance();
    if (_isFirebaseAvailable) {
      if (FirebaseAuth.instance.currentUser == null) {
        await _ensureFirebaseInitializedAndSignedIn(prefs);
      }
      final firestore = FirebaseFirestore.instance;
      for (int i = 0; i < 5; i++) {
        try {
          final existing = await firestore.collection('shop_invites').doc(code).get();
          if (!existing.exists) break;
          code = generateShopCode();
        } catch (_) {
          break;
        }
      }
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isNotEmpty && (_deviceId == null || _deviceId!.startsWith('dev_'))) {
      _deviceId = currentUid;
      await prefs.setString(_prefKeyDeviceId, _deviceId!);
    }
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
    await prefs.setString(_prefKeyShopProfile, profile.toJson());

    // Save to Firestore if available
    if (_isFirebaseAvailable) {
      try {
        final firestore = FirebaseFirestore.instance;
        final notifSettings = await AppNotificationService.instance.exportNotificationSettingsMap();
        await firestore.collection('shops').doc(code).set({
          ...profile.toMap(),
          'ownerUid': currentUid,
          'notification_settings': notifSettings,
          'lastUpdatedNotifDevice': _deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByDevice': _deviceId,
        });
        await _syncPublicInviteDoc(firestore, profile);

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
      final prefs = await SharedPreferences.getInstance();
      if (FirebaseAuth.instance.currentUser == null) {
        await _ensureFirebaseInitializedAndSignedIn(prefs);
      }
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null && currentUid.isNotEmpty) {
        _deviceId = currentUid;
        await prefs.setString(_prefKeyDeviceId, currentUid);
      }

      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic> data;
      try {
        final inviteDoc =
            await firestore.collection('shop_invites').doc(normalizedCode).get();
        if (inviteDoc.exists && inviteDoc.data() != null) {
          data = inviteDoc.data()!;
        } else {
          // Legacy shops created before shop_invites exist on server: let device create check exists(/shops/{code})
          data = {
            'shopCode': normalizedCode,
            'shopName': 'Shop ($normalizedCode)',
          };
        }
      } catch (_) {
        data = {
          'shopCode': normalizedCode,
          'shopName': 'Shop ($normalizedCode)',
        };
      }

      final profile = ShopProfile.fromMap(data).copyWith(
        role: 'staff',
        staffName: staffName.trim().isNotEmpty ? staffName.trim() : 'Staff',
        status: 'pending',
        lastSyncedAt: DateTime.now(),
        isCloudEnabled: true,
      );

      // Register device request as 'pending' in Firestore first so non-existent shop codes
      // are rejected by server rules before saving local ShopProfile.
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

      _currentShop = profile;
      await prefs.setString(_prefKeyShopProfile, profile.toJson());

      _status = SyncStatus.pendingApproval;
      _statusMessage = 'Request sent to shop owner. Waiting for approval...';
      _listenForStaffApproval(normalizedCode);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error joining shop: $e');
      _status = SyncStatus.error;
      final str = e.toString();
      _statusMessage = str.contains('permission-denied')
          ? 'Shop code "$normalizedCode" not found or join request rejected. Please verify the shop code.'
          : _cleanErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Disconnect / Leave current shop
  Future<void> leaveShop() async {
    if (_currentShop != null) {
      unawaited(FCMService.instance.unsubscribeFromShopTopic(_currentShop!.shopCode).catchError((e) {
        debugPrint('[ShopSyncService] Error unsubscribing from FCM topic: $e');
      }));
    }
    _stopRealtimeListeners();
    _currentShop = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyShopProfile);
    _status = SyncStatus.notConfigured;
    _statusMessage = 'No shop linked';
    notifyListeners();
  }

  /// Allocates the next shop-wide sequential order number via Cloud Firestore
  /// WITHOUT opening or holding any SQLite transaction lock. Returns null when
  /// offline, unconfigured, or timed out so local inserts stay instant.
  Future<int?> allocateCloudOrderNumber({int localMaxHint = 0}) async {
    if (_currentShop == null || !_isFirebaseAvailable) {
      return null;
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final shopRef = firestore.collection('shops').doc(_currentShop!.shopCode);
      final nextNumber = await firestore.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(shopRef);
        int cloudLast = 0;
        if (snapshot.exists && snapshot.data() != null) {
          cloudLast = (snapshot.data()!['last_order_number'] as num?)?.toInt() ?? 0;
        }
        final next = max(cloudLast, localMaxHint) + 1;
        transaction.set(shopRef, {
          'last_order_number': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return next;
      }).timeout(const Duration(seconds: 4));

      return nextNumber;
    } catch (e) {
      debugPrint('Error getting cloud sequential order number (fallback to local): $e');
      return null;
    }
  }

  /// Generates the next sequential order number across all connected devices in the shop.
  /// Prefer [allocateCloudOrderNumber] before starting a SQLite transaction so network I/O
  /// never blocks SQLite's write lock.
  Future<int> getNextSequentialOrderNumber([DatabaseExecutor? executor]) async {
    final db = executor ?? await _dbHelper.database;
    int localMax = 0;
    try {
      final maxRows = await db.rawQuery(
        'SELECT MAX(COALESCE(order_number, id)) as max_num FROM orders',
      );
      if (maxRows.isNotEmpty && maxRows.first['max_num'] != null) {
        localMax = (maxRows.first['max_num'] as num).toInt();
      }
    } catch (e) {
      debugPrint('Error getting local max order number: $e');
    }

    // Only attempt Firestore transaction if caller did not pass an open Transaction
    if (executor == null) {
      final cloudNext = await allocateCloudOrderNumber(localMaxHint: localMax);
      if (cloudNext != null) {
        return cloudNext;
      }
    }
    return localMax + 1;
  }

  /// Resolves a synced order's customer locally without spawning duplicate
  /// Walk-in customers on short/pseudo phones (e.g. 'Counter Sale') or linking
  /// unrelated local customers via remote integer IDs.
  static Future<int> resolveOrCreateOrderCustomer(
    DatabaseExecutor db, {
    required String custName,
    String? rawPhone,
  }) async {
    final trimmedPhone = rawPhone?.trim() ?? '';
    final canonicalDigits = Customer.normalizePhoneDigits(trimmedPhone);
    final hasValidPhone = canonicalDigits.length >= 6;
    final cleanName = custName.trim().isNotEmpty ? custName.trim() : 'Customer';

    if (hasValidPhone) {
      final matchedId = await DatabaseHelper.instance
          .findCustomerIdByNormalizedPhone(db, trimmedPhone);
      if (matchedId != null) {
        return matchedId;
      }
      final insertedId = await db.insert('customers', {
        'name': cleanName,
        'phone': trimmedPhone,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (insertedId > 0) {
        return insertedId;
      }
      return (await DatabaseHelper.instance
              .findCustomerIdByNormalizedPhone(db, trimmedPhone)) ??
          1;
    }

    final existingCust = await db.query(
      'customers',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = ?',
      whereArgs: [cleanName.toLowerCase()],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (existingCust.isNotEmpty) {
      return (existingCust.first['id'] as num).toInt();
    }

    return db.insert('customers', {
      'name': cleanName,
      'phone': null,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _upsertSyncedProduct(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    final prodId = (data['id'] as num?)?.toInt();
    final name = (data['name'] as String? ?? '').trim();
    if (name.isEmpty) return;

    Map<String, Object?>? existingRow;
    if (prodId != null) {
      final byId = await db.query('products', where: 'id = ?', whereArgs: [prodId], limit: 1);
      if (byId.isNotEmpty) existingRow = byId.first;
    }
    if (existingRow == null) {
      final byName = await db.query(
        'products',
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [name.toLowerCase()],
        limit: 1,
      );
      if (byName.isNotEmpty) existingRow = byName.first;
    }

    if (existingRow != null) {
      final localPriceUpdated = existingRow['price_updated_at'] as String?;
      final cloudPriceUpdated = data['price_updated_at'] as String?;
      if (localPriceUpdated != null) {
        final localTime = DateTime.tryParse(localPriceUpdated);
        final cloudTime = cloudPriceUpdated != null ? DateTime.tryParse(cloudPriceUpdated) : null;
        if (cloudTime == null || (localTime != null && localTime.isAfter(cloudTime))) {
          if (canManageProducts) {
            final localProd = Product.fromMap(existingRow);
            unawaited(syncProduct(localProd).catchError((e) {
              debugPrint('Error pushing newer local product to cloud: $e');
            }));
          }
          return;
        }
      }

      await db.update(
        'products',
        {
          'name': name,
          'category': data['category'] ?? existingRow['category'] ?? name,
          'is_active': data['is_active'] ?? 1,
          'configuration': data['configuration'] ?? existingRow['configuration'] ?? '{}',
          'price_updated_at': data['price_updated_at'],
          'needs_review': data['needs_review'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [existingRow['id']],
      );
      return;
    }

    final insertMap = <String, Object?>{
      if (prodId != null) 'id': prodId,
      'name': name,
      'category': data['category'] ?? name,
      'is_active': data['is_active'] ?? 1,
      'configuration': data['configuration'] ?? '{}',
      'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      'price_updated_at': data['price_updated_at'],
      'needs_review': data['needs_review'] ?? 0,
    };
    await db.insert('products', insertMap);
  }

  Future<void> _upsertSyncedCustomer(
    DatabaseExecutor db,
    Map<String, dynamic> data,
  ) async {
    final rawName = (data['name'] as String? ?? '').trim();
    if (rawName.isEmpty) return;
    final rawPhone = (data['phone'] as String?)?.trim();
    final cloudCreditLimit = (data['credit_limit'] as num?)?.toDouble();

    int? existingId;
    if (rawPhone != null && Customer.normalizePhoneDigits(rawPhone).length >= 6) {
      existingId = await DatabaseHelper.instance
          .findCustomerIdByNormalizedPhone(db, rawPhone);
    }
    final custId = (data['id'] as num?)?.toInt();
    if (existingId == null && custId != null) {
      final byId = await db.query('customers', where: 'id = ?', whereArgs: [custId], limit: 1);
      if (byId.isNotEmpty) {
        final localName = (byId.first['name'] as String? ?? '').trim().toLowerCase();
        if (localName == rawName.toLowerCase() || (rawPhone == null || rawPhone.isEmpty)) {
          existingId = custId;
        }
      }
    }
    if (existingId == null && (rawPhone == null || Customer.normalizePhoneDigits(rawPhone).length < 6)) {
      final byName = await db.query(
        'customers',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [rawName.toLowerCase()],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        existingId = (byName.first['id'] as num).toInt();
      }
    }

    if (existingId != null) {
      final updates = <String, Object?>{
        'name': rawName,
        'phone': (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null,
        'address': data['address'],
      };
      if (cloudCreditLimit != null) {
        updates['credit_limit'] = cloudCreditLimit;
      }
      await db.update('customers', updates, where: 'id = ?', whereArgs: [existingId]);
      return;
    }

    final insertMap = <String, Object?>{
      'name': rawName,
      'phone': (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null,
      'address': data['address'],
      'credit_limit': cloudCreditLimit ?? 0.0,
      'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
    };
    if (custId != null) {
      final idTaken = await db.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [custId], limit: 1);
      if (idTaken.isEmpty) {
        insertMap['id'] = custId;
      }
    }
    await db.insert('customers', insertMap);
  }

  /// Uploads all local SQLite products, customers, and orders to Firestore
  Future<void> uploadLocalDataToCloud() async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    final db = await _dbHelper.database;

    try {
      // 0. Ensure root Shop Profile document exists in Firestore (owner only)
      if (_currentShop!.isOwner) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        await firestore.collection('shops').doc(shopCode).set({
          ..._currentShop!.toMap(),
          'ownerUid': _currentShop!.ownerUid.isNotEmpty ? _currentShop!.ownerUid : currentUid,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByDevice': _deviceId,
        }, SetOptions(merge: true));
        await _syncPublicInviteDoc(firestore, _currentShop!);
      }

      // 1. Products (owner / permitted devices only; chunked into batches of 400)
      if (canManageProducts) {
        final products = await db.query('products');
        for (var i = 0; i < products.length; i += 400) {
          final productBatch = firestore.batch();
          final end = (i + 400 < products.length) ? i + 400 : products.length;
          for (var j = i; j < end; j++) {
            final p = products[j];
            final docRef = firestore.collection('shops').doc(shopCode).collection('products').doc('${p['id']}');
            final prodMap = <String, dynamic>{
              'id': p['id'],
              'name': p['name'],
              'is_active': p['is_active'],
              'configuration': p['configuration'],
              'created_at': p['created_at'],
              'updatedAt': FieldValue.serverTimestamp(),
              'lastUpdatedByDevice': _deviceId,
            };
            final cat = p['category'] as String?;
            if (cat != null && cat.isNotEmpty) prodMap['category'] = cat;
            final priceUpd = p['price_updated_at'] as String?;
            if (priceUpd != null && priceUpd.isNotEmpty) {
              prodMap['price_updated_at'] = priceUpd;
            }
            final needsRev = (p['needs_review'] as num?)?.toInt() ?? 0;
            if (needsRev != 0) prodMap['needs_review'] = needsRev;
            productBatch.set(docRef, prodMap, SetOptions(merge: true));
          }
          await productBatch.commit();
        }
      }

      // 2. Customers (chunked into batches of 400)
      final customers = await db.query('customers');
      for (var i = 0; i < customers.length; i += 400) {
        final custBatch = firestore.batch();
        final end = (i + 400 < customers.length) ? i + 400 : customers.length;
        for (var j = i; j < end; j++) {
          final c = customers[j];
          final docRef = firestore.collection('shops').doc(shopCode).collection('customers').doc('${c['id']}');
          final custMap = <String, dynamic>{
            'id': c['id'],
            'name': c['name'],
            'credit_limit': (c['credit_limit'] as num?)?.toDouble() ?? 0.0,
            'created_at': c['created_at'],
            'updatedAt': FieldValue.serverTimestamp(),
            'lastUpdatedByDevice': _deviceId,
          };
          final cPhone = c['phone'] as String?;
          if (cPhone != null && cPhone.trim().isNotEmpty) {
            custMap['phone'] = cPhone;
          }
          final cAddr = c['address'] as String?;
          if (cAddr != null && cAddr.trim().isNotEmpty) {
            custMap['address'] = cAddr;
          }
          custBatch.set(docRef, custMap, SetOptions(merge: true));
        }
        await custBatch.commit();
      }

    // 3. Orders with items
    final orders = await db.query('orders');
    int maxSeenLocalOrderNum = 0;
    for (final o in orders) {
      final orderId = o['id'] as int;
      final orderNumber = (o['order_number'] as num?)?.toInt() ?? orderId;
      if (orderNumber > maxSeenLocalOrderNum) {
        maxSeenLocalOrderNum = orderNumber;
      }
      final itemsPayload = await _buildCompactOrderItemsPayload(db, orderId);

      final cloudDocId = (o['cloud_order_id'] as String?) ?? '${_deviceId}_$orderId';
      if (o['cloud_order_id'] == null) {
        await db.update('orders', {'cloud_order_id': cloudDocId}, where: 'id = ?', whereArgs: [orderId]);
      }

      await firestore
          .collection('shops')
          .doc(shopCode)
          .collection('orders')
          .doc(cloudDocId)
          .set(
            _buildCompactOrderPayload(
              o: o,
              orderNumber: orderNumber,
              cloudDocId: cloudDocId,
              itemsPayload: itemsPayload,
            ),
            SetOptions(merge: true),
          );
    }

    if (maxSeenLocalOrderNum > 0) {
      try {
        final shopDocRef = firestore.collection('shops').doc(shopCode);
        final shopSnap = await shopDocRef.get();
        final currentCloudLast = (shopSnap.data()?['last_order_number'] as num?)?.toInt() ?? 0;
        if (maxSeenLocalOrderNum > currentCloudLast) {
          await shopDocRef.set({'last_order_number': maxSeenLocalOrderNum}, SetOptions(merge: true));
        }
      } catch (_) {}
    }

    // 4. Payments (chunked into batches of 400 with customer phone resolution snapshot)
    final payments = await db.query('customer_payments');
    final custMap = {for (final c in customers) c['id'] as int: c};
    for (var i = 0; i < payments.length; i += 400) {
      final payBatch = firestore.batch();
      final end = (i + 400 < payments.length) ? i + 400 : payments.length;
      for (var j = i; j < end; j++) {
        final p = payments[j];
        final payId = p['id'] as int;
        final cloudDocId = (p['cloud_payment_id'] as String?) ?? '${_deviceId}_$payId';
        if (p['cloud_payment_id'] == null) {
          await db.update('customer_payments', {'cloud_payment_id': cloudDocId}, where: 'id = ?', whereArgs: [payId]);
        }
        final cInfo = custMap[p['customer_id'] as int?];
        final docRef = firestore.collection('shops').doc(shopCode).collection('payments').doc(cloudDocId);
        final payMap = <String, dynamic>{
          'id': p['id'],
          'cloud_payment_id': cloudDocId,
          'customer_id': p['customer_id'],
          'amount': p['amount'],
          'payment_mode': p['payment_mode'],
          'created_at': p['created_at'],
          'updatedAt': FieldValue.serverTimestamp(),
          'lastUpdatedByDevice': _deviceId,
        };
        final cPhone = cInfo?['phone'] as String?;
        if (cPhone != null && cPhone.trim().isNotEmpty) {
          payMap['customer_phone'] = cPhone;
        }
        final cName = cInfo?['name'] as String?;
        if (cName != null && cName.trim().isNotEmpty) {
          payMap['customer_name'] = cName;
        }
        final pNotes = p['notes'] as String?;
        if (pNotes != null && pNotes.trim().isNotEmpty) {
          payMap['notes'] = pNotes;
        }
        payBatch.set(docRef, payMap, SetOptions(merge: true));
      }
      await payBatch.commit();
    }

      // 5. Delivery Partners, Locations & Transactions
      await _uploadDeliveryDataToCloud(db, firestore, shopCode);

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

  Future<({int? targetOrderId, bool isNew})> _upsertSyncedOrder(
    Database db,
    String cloudDocId,
    Map<String, dynamic> data,
  ) async {
    final rawNotes = data['notes'] as String?;
    final incomingBreakdown = BillBreakdown.fromJsonString(rawNotes);
    final incomingPhone =
        (data['customer_phone'] as String?) ?? incomingBreakdown?.customerPhone;
    final incomingTakenBy =
        (data['taken_by'] as String?) ?? incomingBreakdown?.takenBy ?? 'Store';
    final custName = data['customer_name_snapshot'] as String? ?? 'Customer';
    final cloudOrderNum =
        (data['order_number'] as num?)?.toInt() ?? (data['id'] as num?)?.toInt();

    return db.transaction((txn) async {
      final localCustId = await resolveOrCreateOrderCustomer(
        txn,
        custName: custName,
        rawPhone: incomingPhone,
      );

      final existingOrder = await txn.query(
        'orders',
        where: 'cloud_order_id = ?',
        whereArgs: [cloudDocId],
      );
      final isNew = existingOrder.isEmpty;
      int targetOrderId;
      if (existingOrder.isNotEmpty) {
        targetOrderId = existingOrder.first['id'] as int;
        final updateMap = <String, dynamic>{
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
          'delivery_partner_name': data['delivery_partner_name'],
          'box_count': (data['box_count'] as num?)?.toInt() ?? 0,
        };
        if (cloudOrderNum != null && cloudOrderNum > 0) {
          updateMap['order_number'] = cloudOrderNum;
        }
        await txn.update('orders', updateMap, where: 'id = ?', whereArgs: [targetOrderId]);
      } else {
        targetOrderId = await txn.insert('orders', {
          'cloud_order_id': cloudDocId,
          'order_number': cloudOrderNum,
          'customer_id': localCustId,
          'customer_name_snapshot': custName,
          'customer_phone': incomingPhone,
          'taken_by': incomingTakenBy,
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'status': data['status'],
          'notes': data['notes'],
          'estimate_total': data['estimate_total'],
          'paid_amount': data['paid_amount'] ?? 0.0,
          'payment_mode': data['payment_mode'] ?? 'unpaid',
          'payment_status': data['payment_status'] ?? 'unpaid',
          'delivery_partner_name': data['delivery_partner_name'],
          'box_count': (data['box_count'] as num?)?.toInt() ?? 0,
        });
      }

      final existingItems = await txn.query(
        'order_items',
        columns: ['id'],
        where: 'order_id = ?',
        whereArgs: [targetOrderId],
      );
      for (final ei in existingItems) {
        final eid = ei['id'] as int;
        await txn.delete('order_item_options', where: 'order_item_id = ?', whereArgs: [eid]);
      }
      await txn.delete('order_items', where: 'order_id = ?', whereArgs: [targetOrderId]);

      final rawItems = data['items'] as List<dynamic>? ?? [];
      for (final rawItem in rawItems) {
        final item = (rawItem as Map).cast<String, dynamic>();
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final snapString = item['product_snapshot'] as String? ??
            jsonEncode({
              'itemName': item['item_name'],
              'unitPrice': unitPrice,
              'options': item['options'] ?? {},
            });
        final localItemId = await txn.insert('order_items', {
          'order_id': targetOrderId,
          'product_id': item['product_id'],
          'item_name': item['item_name'],
          'quantity_ordered': item['quantity_ordered'],
          'quantity_given': item['quantity_given'] ?? 0,
          'unit': item['unit'],
          'unit_price': unitPrice,
          'status': item['status'],
          'is_other_item': item['is_other_item'] ?? 0,
          'procurement_status': item['procurement_status'] ?? 'notRequired',
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': snapString,
        });

        final rawOptions =
            (item['options'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        for (final optEntry in rawOptions.entries) {
          await txn.insert('order_item_options', {
            'order_item_id': localItemId,
            'option_name': optEntry.key,
            'option_value': optEntry.value.toString(),
          });
        }
      }

      return (targetOrderId: targetOrderId, isNew: isNew);
    });
  }

  Future<void> _upsertSyncedPayment(
    Database db,
    String cloudDocId,
    Map<String, dynamic> data,
  ) async {
    final incomingPhone = (data['customer_phone'] as String? ?? '').trim();
    final incomingName = (data['customer_name'] as String? ?? '').trim();
    final rawCustId = (data['customer_id'] as num?)?.toInt();

    await db.transaction((txn) async {
      int? localCustId;
      if (incomingPhone.isNotEmpty &&
          Customer.normalizePhoneDigits(incomingPhone).length >= 6) {
        localCustId = await DatabaseHelper.instance
            .findCustomerIdByNormalizedPhone(txn, incomingPhone);
      }
      if (localCustId == null && incomingName.isNotEmpty) {
        final byName = await txn.query(
          'customers',
          columns: ['id'],
          where: 'LOWER(TRIM(name)) = ?',
          whereArgs: [incomingName.toLowerCase()],
          limit: 1,
        );
        if (byName.isNotEmpty) {
          localCustId = (byName.first['id'] as num).toInt();
        }
      }
      if (localCustId == null && rawCustId != null) {
        final byId = await txn.query(
          'customers',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [rawCustId],
          limit: 1,
        );
        if (byId.isNotEmpty) {
          localCustId = rawCustId;
        }
      }
      localCustId ??= await resolveOrCreateOrderCustomer(
        txn,
        custName: incomingName.isNotEmpty ? incomingName : 'Customer',
        rawPhone: incomingPhone,
      );

      final existingPay = await txn.query(
        'customer_payments',
        where: 'cloud_payment_id = ?',
        whereArgs: [cloudDocId],
      );
      final payPayload = <String, Object?>{
        'customer_id': localCustId,
        'amount': data['amount'],
        'payment_mode': data['payment_mode'] ?? 'cash',
        'notes': data['notes'],
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      };
      if (existingPay.isNotEmpty) {
        await txn.update(
          'customer_payments',
          payPayload,
          where: 'id = ?',
          whereArgs: [existingPay.first['id']],
        );
      } else {
        await txn.insert('customer_payments', {
          'cloud_payment_id': cloudDocId,
          ...payPayload,
        });
      }
    });
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
        await _upsertSyncedProduct(db, doc.data());
      }

      // 2. Sync Customers
      final custSnaps = await firestore.collection('shops').doc(shopCode).collection('customers').get();
      for (final doc in custSnaps.docs) {
        await _upsertSyncedCustomer(db, doc.data());
      }

      // 3. Sync Orders
      final orderSnaps = await firestore.collection('shops').doc(shopCode).collection('orders').get();
      for (final doc in orderSnaps.docs) {
        await _upsertSyncedOrder(db, doc.id, doc.data());
      }

      // 4. Sync Payments
      final paySnaps = await firestore.collection('shops').doc(shopCode).collection('payments').get();
      for (final doc in paySnaps.docs) {
        await _upsertSyncedPayment(db, doc.id, doc.data());
      }

      // 5. Sync Notification Timers & Shop Profile from Cloud Shop Document
      try {
        final rootShopDoc = await firestore.collection('shops').doc(shopCode).get();
        final rootData = rootShopDoc.data();
        if (rootShopDoc.exists && rootData != null) {
          if (_currentShop != null && !_currentShop!.isOwner) {
            final hydrated = ShopProfile.fromMap(rootData).copyWith(
              role: _currentShop!.role,
              staffName: _currentShop!.staffName,
              status: _currentShop!.status,
              isCloudEnabled: true,
              lastSyncedAt: DateTime.now(),
            );
            _currentShop = hydrated;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefKeyShopProfile, hydrated.toJson());
          }
          if (rootData['notification_settings'] is Map) {
            final notifMap = (rootData['notification_settings'] as Map).cast<String, dynamic>();
            await AppNotificationService.instance.applyCloudNotificationSettings(notifMap);
          }
        }
      } catch (err) {
        debugPrint('Error syncing shop/notification settings from cloud: $err');
      }

      // 6. Sync Delivery Partners, Locations & Transactions
      await _downloadDeliveryDataFromCloud(db, firestore, shopCode);

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

  Future<List<Map<String, dynamic>>> _buildCompactOrderItemsPayload(
    Database db,
    int orderId,
  ) async {
    final items =
        await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    final itemsPayload = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = item['id'] as int;
      final options = await db.query(
        'order_item_options',
        where: 'order_item_id = ?',
        whereArgs: [itemId],
      );
      final optionsMap = <String, String>{};
      for (final opt in options) {
        optionsMap[opt['option_name'] as String] = opt['option_value'] as String;
      }

      double unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      if (unitPrice == 0.0) {
        final rawSnap = item['product_snapshot'] as String?;
        if (rawSnap != null && rawSnap.isNotEmpty) {
          try {
            final snapMap = jsonDecode(rawSnap) as Map<String, dynamic>;
            unitPrice = (snapMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }
      }

      // Omit redundant product_snapshot (reconstructed on download) & empty/null fields
      final itemMap = <String, dynamic>{
        'id': item['id'],
        'item_name': item['item_name'],
        'quantity_ordered': item['quantity_ordered'],
        'quantity_given': item['quantity_given'] ?? 0,
        'unit': item['unit'],
        'unit_price': unitPrice,
        'status': item['status'],
      };
      if (item['product_id'] != null) itemMap['product_id'] = item['product_id'];
      if (((item['is_other_item'] as num?)?.toInt() ?? 0) != 0) {
        itemMap['is_other_item'] = 1;
      }
      final proc = item['procurement_status'] as String?;
      if (proc != null && proc.isNotEmpty) itemMap['procurement_status'] = proc;
      final details = item['details'] as String?;
      if (details != null && details.isNotEmpty) itemMap['details'] = details;
      final itemNotes = item['notes'] as String?;
      if (itemNotes != null && itemNotes.isNotEmpty) itemMap['notes'] = itemNotes;
      if (optionsMap.isNotEmpty) itemMap['options'] = optionsMap;

      itemsPayload.add(itemMap);
    }
    return itemsPayload;
  }

  Map<String, dynamic> _buildCompactOrderPayload({
    required Map<String, Object?> o,
    required int orderNumber,
    required String cloudDocId,
    required List<Map<String, dynamic>> itemsPayload,
  }) {
    final notes = o['notes'] as String?;
    final breakdown = BillBreakdown.fromJsonString(notes);
    final customerPhone =
        (o['customer_phone'] as String?) ?? breakdown?.customerPhone;
    final takenBy =
        (o['taken_by'] as String?) ?? breakdown?.takenBy ?? 'Store';

    final map = <String, dynamic>{
      'id': o['id'],
      'order_number': orderNumber,
      'cloud_order_id': cloudDocId,
      'customer_id': o['customer_id'],
      'customer_name_snapshot': o['customer_name_snapshot'],
      'taken_by': takenBy,
      'created_at': o['created_at'],
      'status': o['status'],
      'estimate_total': o['estimate_total'],
      'payment_mode': o['payment_mode'] ?? 'unpaid',
      'payment_status': o['payment_status'] ?? 'unpaid',
      'items': itemsPayload,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedByDevice': _deviceId,
    };
    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      map['customer_phone'] = customerPhone;
    }
    if (notes != null && notes.trim().isNotEmpty) {
      map['notes'] = notes;
    }
    final paidAmt = (o['paid_amount'] as num?)?.toDouble() ?? 0.0;
    if (paidAmt != 0.0) {
      map['paid_amount'] = paidAmt;
    }
    final delivPartner = (o['delivery_partner_name'] as String?)?.trim();
    if (delivPartner != null && delivPartner.isNotEmpty) {
      map['delivery_partner_name'] = delivPartner;
    }
    final boxCount = (o['box_count'] as num?)?.toInt() ?? 0;
    if (boxCount > 0) {
      map['box_count'] = boxCount;
    }
    return map;
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

      final itemsPayload = await _buildCompactOrderItemsPayload(db, orderId);

      final orderNumber = (o['order_number'] as num?)?.toInt() ?? orderId;
      final cloudDocId = (o['cloud_order_id'] as String?) ?? '${_deviceId}_$orderId';
      if (o['cloud_order_id'] == null) {
        await db.update('orders', {'cloud_order_id': cloudDocId}, where: 'id = ?', whereArgs: [orderId]);
      }

      await firestore
          .collection('shops')
          .doc(shopCode)
          .collection('orders')
          .doc(cloudDocId)
          .set(
            _buildCompactOrderPayload(
              o: o,
              orderNumber: orderNumber,
              cloudDocId: cloudDocId,
              itemsPayload: itemsPayload,
            ),
            SetOptions(merge: true),
          );

      if (orderNumber > 0) {
        unawaited(firestore.runTransaction((txn) async {
          final shopRef = firestore.collection('shops').doc(shopCode);
          final snap = await txn.get(shopRef);
          final cur = (snap.data()?['last_order_number'] as num?)?.toInt() ?? 0;
          if (orderNumber > cur) {
            txn.set(shopRef, {'last_order_number': orderNumber}, SetOptions(merge: true));
          }
        }).catchError((_) {}));
      }

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

      String? custPhone;
      String? custName;
      final cid = p['customer_id'] as int?;
      if (cid != null) {
        final cRows = await db.query(
          'customers',
          columns: ['name', 'phone'],
          where: 'id = ?',
          whereArgs: [cid],
          limit: 1,
        );
        if (cRows.isNotEmpty) {
          custPhone = (cRows.first['phone'] as String?)?.trim();
          custName = (cRows.first['name'] as String?)?.trim();
        }
      }

      final payMap = <String, dynamic>{
        'id': p['id'],
        'cloud_payment_id': cloudDocId,
        'customer_id': p['customer_id'],
        'amount': p['amount'],
        'payment_mode': p['payment_mode'],
        'notes': p['notes'],
        'created_at': p['created_at'],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedByDevice': _deviceId,
      };
      if (custPhone != null && custPhone.isNotEmpty) {
        payMap['customer_phone'] = custPhone;
      }
      if (custName != null && custName.isNotEmpty) {
        payMap['customer_name'] = custName;
      }

      await firestore.collection('shops').doc(shopCode).collection('payments').doc(cloudDocId).set(
            payMap,
            SetOptions(merge: true),
          );

      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing payment $paymentId: $e');
    }
  }

  /// Push a single product to cloud
  Future<void> syncProduct(Product product) async {
    if (_currentShop == null || !_isFirebaseAvailable || product.id == null || !canManageProducts) return;
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
    _realtimeListenersStartedAt = DateTime.now();

    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;

    // Auto-subscribe this device to the shop's multi-device FCM cloud push channel
    unawaited(FCMService.instance.subscribeToShopTopic(shopCode).catchError((e) {
      debugPrint('[ShopSyncService] Error subscribing to FCM shop topic: $e');
    }));
    StorageMonitorService.instance.startListening(shopCode);

    // 1. Orders live stream
    _ordersSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('orders')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;
          try {
            final res = await _upsertSyncedOrder(db, change.doc.id, data);
            if (res.isNew &&
                !snapshot.metadata.isFromCache &&
                data['lastUpdatedByDevice'] != _deviceId) {
              final rawNotes = data['notes'] as String?;
              final incomingBreakdown = BillBreakdown.fromJsonString(rawNotes);
              final incomingTakenBy = (data['taken_by'] as String?) ??
                  incomingBreakdown?.takenBy ??
                  'Store';
              final custName =
                  data['customer_name_snapshot'] as String? ?? 'Customer';
              final cloudOrderNum = (data['order_number'] as num?)?.toInt() ??
                  (data['id'] as num?)?.toInt();
              final createdAt = DateTime.tryParse(data['created_at'] as String? ?? '');
              final isRecentOrder = createdAt == null ||
                  DateTime.now().difference(createdAt).inMinutes.abs() <= 15;
              if (isRecentOrder) {
                final estTotal = (data['estimate_total'] as num?)?.toDouble() ?? 0.0;
                final totalStr = estTotal > 0 ? ' (₹ ${estTotal.toStringAsFixed(0)})' : '';
                final formattedOrderNum =
                    (cloudOrderNum != null && cloudOrderNum > 0)
                        ? '#ORD-${cloudOrderNum.toString().padLeft(4, '0')} '
                        : '';
                unawaited(AppNotificationService.instance.showLiveOrderNotification(
                  title: '📋 New Order from $incomingTakenBy',
                  body:
                      '${formattedOrderNum}for $custName$totalStr received from connected device.',
                ));
              }
            }
          } catch (e) {
            debugPrint('Error applying remote order ${change.doc.id}: $e');
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
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;
          try {
            await _upsertSyncedProduct(db, data);
          } catch (e) {
            debugPrint('Error applying remote product ${change.doc.id}: $e');
          }
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
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;
          try {
            await _upsertSyncedCustomer(db, data);
          } catch (e) {
            debugPrint('Error applying remote customer ${change.doc.id}: $e');
          }
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
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data == null) continue;
          if (data['lastUpdatedByDevice'] == _deviceId) continue;
          try {
            await _upsertSyncedPayment(db, change.doc.id, data);
          } catch (e) {
            debugPrint('Error applying remote payment ${change.doc.id}: $e');
          }
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });

    // 5. Delivery Partners, Locations & Transactions live streams
    _startDeliveryRealtimeListeners(firestore, shopCode);

    // 6. Device permissions live stream (for staff devices)
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

    // 6. Shop notification schedule live stream (synchronizes alert times across all devices)
    _shopDocSub = firestore
        .collection('shops')
        .doc(shopCode)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || snap.data() == null) return;
      final data = snap.data()!;
      if (data['notification_settings'] is Map) {
        if (data['lastUpdatedNotifDevice'] != _deviceId) {
          final notifMap = (data['notification_settings'] as Map).cast<String, dynamic>();
          await AppNotificationService.instance.applyCloudNotificationSettings(notifMap);
        }
      }
    });

    // 7. Multi-device live broadcast alert stream (ignore historical queue entries)
    _notifSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('outbound_notifications')
        .where(
          'created_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            _realtimeListenersStartedAt.subtract(const Duration(minutes: 2)),
          ),
        )
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['sender_device_id'] != _deviceId) {
            unawaited(AppNotificationService.instance.showLiveOrderNotification(
              title: data['title'] ?? 'Shop Alert',
              body: data['body'] ?? '',
            ));
          }
        }
      }
    }, onError: (e) {
      debugPrint('[ShopSyncService] Outbound notifications stream error: $e');
    });
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
      if (!snap.exists || snap.data() == null) {
        if (_currentShop != null && _currentShop!.isPending) {
          _status = SyncStatus.error;
          _statusMessage = 'Device registration was removed or rejected by owner.';
          await leaveShop();
          notifyListeners();
        }
        return;
      }
      final data = snap.data()!;
      _myDevicePermissions = StaffDevice.fromMap(data);
      final remoteDeviceName = (data['staffName'] as String?)?.trim();
      if (remoteDeviceName != null &&
          remoteDeviceName.isNotEmpty &&
          _currentShop != null) {
        if (!_currentShop!.isOwner &&
            _currentShop!.staffName != remoteDeviceName) {
          _currentShop = _currentShop!.copyWith(staffName: remoteDeviceName);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKeyShopProfile, _currentShop!.toJson());
          notifyListeners();
        }
      }
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
          .set({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

  /// Updates the name of a primary (master) or secondary (partner) device
  Future<void> updateDeviceName({
    required String targetDeviceId,
    required String newName,
  }) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;
    if (_currentShop == null) return;

    final isMe = targetDeviceId == _deviceId;

    // 1. If this is the current device, update local profile and SharedPreferences
    if (isMe) {
      if (_currentShop!.isOwner) {
        _currentShop = _currentShop!.copyWith(ownerName: cleanName);
      } else {
        _currentShop = _currentShop!.copyWith(staffName: cleanName);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyShopProfile, _currentShop!.toJson());
    }

    // 2. If Firebase is available, update Firestore
    if (_isFirebaseAvailable) {
      try {
        await FirebaseFirestore.instance
            .collection('shops')
            .doc(_currentShop!.shopCode)
            .collection('devices')
            .doc(targetDeviceId)
            .set({
          'staffName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // If the owner renamed their own primary device, update ownerName on the root shop document
        if (_currentShop!.isOwner && isMe) {
          await FirebaseFirestore.instance
              .collection('shops')
              .doc(_currentShop!.shopCode)
              .set({
            'ownerName': cleanName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Error updating device name in Firestore: $e');
      }
    }

    notifyListeners();
  }

  Future<void> updateShopProfileDetails({
    String? shopName,
    String? phone,
    String? address,
    String? gstin,
    String? upiId,
    String? digitalStamp,
  }) async {
    if (_currentShop == null || !_currentShop!.isOwner) return;
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

        final firestore = FirebaseFirestore.instance;
        await firestore
            .collection('shops')
            .doc(_currentShop!.shopCode)
            .set(updateMap, SetOptions(merge: true));
        if (shopName != null) {
          await _syncPublicInviteDoc(firestore, _currentShop!);
        }
      } catch (e) {
        debugPrint('Error updating shop profile details online: $e');
      }
    }
    notifyListeners();
  }

  Future<void> updateShopName(String newName) async {
    await updateShopProfileDetails(shopName: newName);
  }

  /// Synchronizes active notification schedule (custom alert times) to Firestore for all connected devices
  Future<void> syncNotificationSettingsToCloud() async {
    if (_currentShop == null || !_currentShop!.isOwner || !_isFirebaseAvailable || _deviceId == null) return;
    try {
      final notifSettings = await AppNotificationService.instance.exportNotificationSettingsMap();
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .set({
        'notification_settings': notifSettings,
        'lastUpdatedNotifDevice': _deviceId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[ShopSyncService] Synced notification settings to cloud for shop ${_currentShop!.shopCode}');
    } catch (e) {
      debugPrint('[ShopSyncService] Error syncing notification settings to cloud: $e');
    }
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
    _deliveryPartnersSub?.cancel();
    _deliveryPartnersSub = null;
    _deliveryLocationsSub?.cancel();
    _deliveryLocationsSub = null;
    _deliveryTxSub?.cancel();
    _deliveryTxSub = null;
    _deviceSub?.cancel();
    _deviceSub = null;
    _shopDocSub?.cancel();
    _shopDocSub = null;
    _notifSub?.cancel();
    _notifSub = null;
    StorageMonitorService.instance.stopListening();
  }

  @override
  void dispose() {
    _stopRealtimeListeners();
    super.dispose();
  }

  // =========================================================================
  // DELIVERY PARTNERS, LOCATIONS & TRANSACTIONS CLOUD SYNC
  // =========================================================================

  String generateCloudId(String prefix) {
    final dev = (_deviceId ?? 'dev').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final rand = Random().nextInt(999999).toString().padLeft(6, '0');
    return '${prefix}_${dev}_${DateTime.now().microsecondsSinceEpoch}_$rand';
  }

  String _compactTxType(String raw) {
    switch (raw) {
      case 'per_box':
        return 'b';
      case 'line':
        return 'l';
      default:
        return 'p';
    }
  }

  String _expandTxType(dynamic raw) {
    switch (raw?.toString()) {
      case 'b':
      case 'per_box':
        return 'per_box';
      case 'l':
      case 'line':
        return 'line';
      default:
        return 'payout';
    }
  }

  String _compactPayMode(String raw) {
    if (raw == 'cash') return 'c';
    if (raw == 'upi') return 'u';
    return '';
  }

  String _expandPayMode(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s == 'c' || s == 'cash') return 'cash';
    if (s == 'u' || s == 'upi') return 'upi';
    return 'none';
  }

  String? _compactRateTiersJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return null;
    try {
      final list = jsonDecode(rawJson) as List<dynamic>;
      final parts = <String>[];
      for (final item in list) {
        if (item is Map) {
          final b = (item['boxes'] as num?)?.toInt() ?? 0;
          final r = (item['rate'] as num?)?.toDouble() ?? 0.0;
          if (b > 0 && r > 0) {
            final rStr = r == r.roundToDouble() ? r.toInt().toString() : r.toString();
            parts.add('${b}x$rStr');
          }
        }
      }
      return parts.isEmpty ? null : parts.join(',');
    } catch (_) {
      return null;
    }
  }

  String? _expandRateTiers(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    if (s.startsWith('[')) return s; // Already JSON
    final tiers = <Map<String, dynamic>>[];
    for (final part in s.split(',')) {
      final seg = part.split('x');
      if (seg.length == 2) {
        final b = int.tryParse(seg[0].trim()) ?? 0;
        final r = double.tryParse(seg[1].trim()) ?? 0.0;
        if (b > 0 && r > 0) {
          tiers.add({'boxes': b, 'rate': r});
        }
      }
    }
    return tiers.isEmpty ? null : jsonEncode(tiers);
  }

  int _toEpochMs(dynamic isoOrMs) {
    if (isoOrMs is num) return isoOrMs.toInt();
    if (isoOrMs is String) {
      return DateTime.tryParse(isoOrMs)?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  String _fromEpochMsToIso(dynamic val) {
    if (val is num) {
      return DateTime.fromMillisecondsSinceEpoch(val.toInt()).toIso8601String();
    }
    if (val is String && val.isNotEmpty) return val;
    return DateTime.now().toIso8601String();
  }

  Map<String, dynamic> _buildCompactPartnerPayload({
    required String name,
    String? phone,
    String? vehicleInfo,
    String? notes,
    int isActive = 1,
    required dynamic createdAt,
  }) {
    final map = <String, dynamic>{
      'n': name,
      'c': _toEpochMs(createdAt),
    };
    if (phone != null && phone.trim().isNotEmpty) map['p'] = phone.trim();
    if (vehicleInfo != null && vehicleInfo.trim().isNotEmpty) {
      map['v'] = vehicleInfo.trim();
    }
    if (notes != null && notes.trim().isNotEmpty) map['nt'] = notes.trim();
    if (isActive != 1) map['a'] = isActive;
    if (_deviceId != null) map['d'] = _deviceId;
    return map;
  }

  Map<String, dynamic> _buildCompactTxPayload({
    required String partnerCloudId,
    required String partnerName,
    required String txType,
    String? location,
    int totalBoxes = 0,
    String? rateBreakdownJson,
    double earnedAmount = 0.0,
    double paidAmount = 0.0,
    double cutAmount = 0.0,
    String paymentMode = 'none',
    String? description,
    required dynamic createdAt,
  }) {
    final map = <String, dynamic>{
      'pc': partnerCloudId,
      'pn': partnerName,
      't': _compactTxType(txType),
      'c': _toEpochMs(createdAt),
    };
    if (location != null && location.trim().isNotEmpty) {
      map['l'] = location.trim();
    }
    if (totalBoxes > 0) map['bx'] = totalBoxes;
    final compactTiers = _compactRateTiersJson(rateBreakdownJson);
    if (compactTiers != null) map['rt'] = compactTiers;
    if (earnedAmount > 0) map['e'] = earnedAmount;
    if (paidAmount > 0) map['pa'] = paidAmount;
    if (cutAmount > 0) map['ca'] = cutAmount;
    final pm = _compactPayMode(paymentMode);
    if (pm.isNotEmpty) map['pm'] = pm;
    if (description != null && description.trim().isNotEmpty) {
      map['ds'] = description.trim();
    }
    if (_deviceId != null) map['d'] = _deviceId;
    return map;
  }

  Future<void> _uploadDeliveryDataToCloud(
    Database db,
    FirebaseFirestore firestore,
    String shopCode,
  ) async {
    final partners = await db.query('delivery_partners');
    final partnerCloudIdById = <int, String>{};
    final partnerNameById = <int, String>{};

    for (var i = 0; i < partners.length; i += 400) {
      final batch = firestore.batch();
      final end = (i + 400 < partners.length) ? i + 400 : partners.length;
      for (var j = i; j < end; j++) {
        final p = partners[j];
        final localId = (p['id'] as num).toInt();
        var cloudId = p['cloud_partner_id'] as String?;
        if (cloudId == null || cloudId.isEmpty) {
          cloudId = generateCloudId('dp');
          await db.update(
            'delivery_partners',
            {'cloud_partner_id': cloudId},
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
        partnerCloudIdById[localId] = cloudId;
        partnerNameById[localId] = (p['name'] as String?) ?? 'Partner';

        final ref = firestore
            .collection('shops')
            .doc(shopCode)
            .collection('delivery_partners')
            .doc(cloudId);
        batch.set(
          ref,
          _buildCompactPartnerPayload(
            name: (p['name'] as String?) ?? 'Partner',
            phone: p['phone'] as String?,
            vehicleInfo: p['vehicle_info'] as String?,
            notes: p['notes'] as String?,
            isActive: (p['is_active'] as num?)?.toInt() ?? 1,
            createdAt: p['created_at'],
          ),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    final locations = await db.query('delivery_locations');
    for (var i = 0; i < locations.length; i += 400) {
      final batch = firestore.batch();
      final end = (i + 400 < locations.length) ? i + 400 : locations.length;
      for (var j = i; j < end; j++) {
        final loc = locations[j];
        final name = (loc['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final docId = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        final ref = firestore
            .collection('shops')
            .doc(shopCode)
            .collection('delivery_locations')
            .doc(docId);
        batch.set(
          ref,
          {'n': name, 'c': _toEpochMs(loc['created_at'])},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    final txs = await db.query('delivery_transactions');
    for (var i = 0; i < txs.length; i += 400) {
      final batch = firestore.batch();
      final end = (i + 400 < txs.length) ? i + 400 : txs.length;
      for (var j = i; j < end; j++) {
        final tx = txs[j];
        final localId = (tx['id'] as num).toInt();
        final partnerId = (tx['partner_id'] as num).toInt();
        var cloudTxId = tx['cloud_tx_id'] as String?;
        if (cloudTxId == null || cloudTxId.isEmpty) {
          cloudTxId = generateCloudId('dtx');
          await db.update(
            'delivery_transactions',
            {'cloud_tx_id': cloudTxId},
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
        final ref = firestore
            .collection('shops')
            .doc(shopCode)
            .collection('delivery_transactions')
            .doc(cloudTxId);
        batch.set(
          ref,
          _buildCompactTxPayload(
            partnerCloudId: partnerCloudIdById[partnerId] ?? '',
            partnerName: partnerNameById[partnerId] ?? '',
            txType: (tx['tx_type'] as String?) ?? 'per_box',
            location: tx['location'] as String?,
            totalBoxes: (tx['total_boxes'] as num?)?.toInt() ?? 0,
            rateBreakdownJson: tx['rate_breakdown_json'] as String?,
            earnedAmount: (tx['earned_amount'] as num?)?.toDouble() ?? 0.0,
            paidAmount: (tx['paid_amount'] as num?)?.toDouble() ?? 0.0,
            cutAmount: (tx['cut_amount'] as num?)?.toDouble() ?? 0.0,
            paymentMode: (tx['payment_mode'] as String?) ?? 'none',
            description: tx['description'] as String?,
            createdAt: tx['created_at'],
          ),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> _downloadDeliveryDataFromCloud(
    Database db,
    FirebaseFirestore firestore,
    String shopCode,
  ) async {
    final partnerSnaps = await firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_partners')
        .get();
    for (final doc in partnerSnaps.docs) {
      await _upsertCloudDeliveryPartner(db, doc.id, doc.data());
    }

    final locSnaps = await firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_locations')
        .get();
    for (final doc in locSnaps.docs) {
      final data = doc.data();
      final name = ((data['n'] ?? data['name']) as String?)?.trim() ?? '';
      if (name.isNotEmpty) {
        await db.rawInsert(
          'INSERT OR IGNORE INTO delivery_locations (name, created_at) VALUES (?, ?)',
          [name, _fromEpochMsToIso(data['c'] ?? data['created_at'])],
        );
      }
    }

    final txSnaps = await firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_transactions')
        .get();
    for (final doc in txSnaps.docs) {
      await _upsertCloudDeliveryTransaction(db, doc.id, doc.data());
    }
  }

  Future<int> _upsertCloudDeliveryPartner(
    Database db,
    String cloudId,
    Map<String, dynamic> data,
  ) async {
    final name =
        ((data['n'] ?? data['name']) as String?)?.trim() ?? 'Delivery Partner';
    final existing = await db.query(
      'delivery_partners',
      where: 'cloud_partner_id = ? OR LOWER(TRIM(name)) = ?',
      whereArgs: [cloudId, name.toLowerCase()],
      limit: 1,
    );
    final payload = {
      'cloud_partner_id': cloudId,
      'name': name,
      'phone': data['p'] ?? data['phone'],
      'vehicle_info': data['v'] ?? data['vehicle_info'],
      'notes': data['nt'] ?? data['notes'],
      'is_active': ((data['a'] ?? data['is_active']) as num?)?.toInt() ?? 1,
      'created_at': _fromEpochMsToIso(data['c'] ?? data['created_at']),
    };
    if (existing.isNotEmpty) {
      final id = (existing.first['id'] as num).toInt();
      await db.update(
        'delivery_partners',
        payload,
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert('delivery_partners', payload);
  }

  Future<void> _upsertCloudDeliveryTransaction(
    Database db,
    String cloudTxId,
    Map<String, dynamic> data,
  ) async {
    final partnerCloudId =
        ((data['pc'] ?? data['partner_cloud_id']) as String? ?? '').trim();
    final partnerName =
        ((data['pn'] ?? data['partner_name']) as String? ?? '').trim();

    int? localPartnerId;
    if (partnerCloudId.isNotEmpty) {
      final rows = await db.query(
        'delivery_partners',
        columns: ['id'],
        where: 'cloud_partner_id = ?',
        whereArgs: [partnerCloudId],
        limit: 1,
      );
      if (rows.isNotEmpty) localPartnerId = (rows.first['id'] as num).toInt();
    }
    if (localPartnerId == null && partnerName.isNotEmpty) {
      final rows = await db.query(
        'delivery_partners',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [partnerName.toLowerCase()],
        limit: 1,
      );
      if (rows.isNotEmpty) localPartnerId = (rows.first['id'] as num).toInt();
    }
    localPartnerId ??= await db.insert('delivery_partners', {
      'cloud_partner_id': partnerCloudId.isNotEmpty ? partnerCloudId : null,
      'name': partnerName.isNotEmpty ? partnerName : 'Delivery Partner',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    final loc = ((data['l'] ?? data['location']) as String?)?.trim() ?? '';
    if (loc.isNotEmpty) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO delivery_locations (name, created_at) VALUES (?, ?)',
        [loc, DateTime.now().toIso8601String()],
      );
    }

    final payload = {
      'cloud_tx_id': cloudTxId,
      'partner_id': localPartnerId,
      'tx_type': _expandTxType(data['t'] ?? data['tx_type']),
      'location': loc.isEmpty ? null : loc,
      'total_boxes': ((data['bx'] ?? data['total_boxes']) as num?)?.toInt() ?? 0,
      'rate_breakdown_json':
          _expandRateTiers(data['rt'] ?? data['rate_breakdown_json']),
      'earned_amount':
          ((data['e'] ?? data['earned_amount']) as num?)?.toDouble() ?? 0.0,
      'paid_amount':
          ((data['pa'] ?? data['paid_amount']) as num?)?.toDouble() ?? 0.0,
      'cut_amount':
          ((data['ca'] ?? data['cut_amount']) as num?)?.toDouble() ?? 0.0,
      'payment_mode': _expandPayMode(data['pm'] ?? data['payment_mode']),
      'description': data['ds'] ?? data['description'],
      'created_at': _fromEpochMsToIso(data['c'] ?? data['created_at']),
    };

    final existing = await db.query(
      'delivery_transactions',
      columns: ['id'],
      where: 'cloud_tx_id = ?',
      whereArgs: [cloudTxId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'delivery_transactions',
        payload,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('delivery_transactions', payload);
    }
  }

  void _startDeliveryRealtimeListeners(
    FirebaseFirestore firestore,
    String shopCode,
  ) {
    _deliveryPartnersSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_partners')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (change.type == DocumentChangeType.removed) {
          await db.delete(
            'delivery_partners',
            where: 'cloud_partner_id = ?',
            whereArgs: [change.doc.id],
          );
        } else if (data != null &&
            (data['d'] ?? data['lastUpdatedByDevice']) != _deviceId) {
          await _upsertCloudDeliveryPartner(db, change.doc.id, data);
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });

    _deliveryLocationsSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_locations')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data != null && change.type != DocumentChangeType.removed) {
          final name = ((data['n'] ?? data['name']) as String?)?.trim() ?? '';
          if (name.isNotEmpty) {
            await db.rawInsert(
              'INSERT OR IGNORE INTO delivery_locations (name, created_at) VALUES (?, ?)',
              [name, _fromEpochMsToIso(data['c'] ?? data['created_at'])],
            );
          }
        }
      }
    });

    _deliveryTxSub = firestore
        .collection('shops')
        .doc(shopCode)
        .collection('delivery_transactions')
        .snapshots()
        .listen((snapshot) async {
      final db = await _dbHelper.database;
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (change.type == DocumentChangeType.removed) {
          await db.delete(
            'delivery_transactions',
            where: 'cloud_tx_id = ?',
            whereArgs: [change.doc.id],
          );
        } else if (data != null &&
            (data['d'] ?? data['lastUpdatedByDevice']) != _deviceId) {
          await _upsertCloudDeliveryTransaction(db, change.doc.id, data);
        }
      }
      _lastSyncTime = DateTime.now();
      notifyListeners();
    });
  }

  Future<void> syncDeliveryPartner(DeliveryPartner partner) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final cloudId = partner.cloudPartnerId;
    if (cloudId == null || cloudId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_partners')
          .doc(cloudId)
          .set(
            _buildCompactPartnerPayload(
              name: partner.name,
              phone: partner.phone,
              vehicleInfo: partner.vehicleInfo,
              notes: partner.notes,
              isActive: partner.isActive ? 1 : 0,
              createdAt: partner.createdAt.toIso8601String(),
            ),
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error syncing delivery partner: $e');
    }
  }

  Future<void> deleteDeliveryPartnerFromCloud(String cloudPartnerId) async {
    if (_currentShop == null || !_isFirebaseAvailable || cloudPartnerId.isEmpty) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_partners')
          .doc(cloudPartnerId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting delivery partner from cloud: $e');
    }
  }

  Future<void> syncDeliveryLocation(String name) async {
    if (_currentShop == null || !_isFirebaseAvailable || name.trim().isEmpty) {
      return;
    }
    try {
      final clean = name.trim();
      final docId = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_locations')
          .doc(docId)
          .set(
            {'n': clean, 'c': DateTime.now().millisecondsSinceEpoch},
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error syncing delivery location: $e');
    }
  }

  Future<void> syncDeliveryTransaction(
    DeliveryTransaction tx, {
    required String partnerCloudId,
    required String partnerName,
  }) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final cloudTxId = tx.cloudTxId;
    if (cloudTxId == null || cloudTxId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_transactions')
          .doc(cloudTxId)
          .set(
            _buildCompactTxPayload(
              partnerCloudId: partnerCloudId,
              partnerName: partnerName,
              txType: deliveryTxTypeToDb(tx.txType),
              location: tx.location,
              totalBoxes: tx.totalBoxes,
              rateBreakdownJson: tx.toMap()['rate_breakdown_json'] as String?,
              earnedAmount: tx.earnedAmount,
              paidAmount: tx.paidAmount,
              cutAmount: tx.cutAmount,
              paymentMode: tx.paymentMode,
              description: tx.description,
              createdAt: tx.createdAt.toIso8601String(),
            ),
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error syncing delivery transaction: $e');
    }
  }

  Future<void> deleteDeliveryTransactionFromCloud(String cloudTxId) async {
    if (_currentShop == null || !_isFirebaseAvailable || cloudTxId.isEmpty) {
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_transactions')
          .doc(cloudTxId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting delivery transaction from cloud: $e');
    }
  }
}


