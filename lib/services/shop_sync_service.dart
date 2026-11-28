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

part 'shop_sync_outbox.dart';
part 'delivery_sync_adapter.dart';
part 'shop_sync_entities.dart';
part 'shop_sync_realtime.dart';

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
  static const String _prefKeyDeltaCursorPrefix = 'shop_sync_delta_cursor_';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  ShopProfile? _currentShop;
  SyncStatus _status = SyncStatus.notConfigured;
  String _statusMessage = 'Cloud sync not initialized';
  DateTime? _lastSyncTime;
  String? _deviceId;
  bool _isFirebaseAvailable = false;
  Timer? _notifyDebounceTimer;
  bool _isFlushingOutbox = false;

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

  /// Whether the active Firebase session is still an unlinked anonymous account.
  bool get isAnonymousSession {
    try {
      return FirebaseAuth.instance.currentUser?.isAnonymous ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Whether an owner account has linked a durable Phone or Google recovery credential.
  bool get hasRecoveryAccountLinked {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return false;
      return user.providerData.any(
        (p) => p.providerId != 'firebase' && p.providerId != 'anonymous',
      );
    } catch (_) {
      return false;
    }
  }

  /// Human-readable label of the linked recovery method (phone number or email).
  String? get recoveryAccountLabel {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return null;
      if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty) {
        return user.phoneNumber!.trim();
      }
      if (user.email != null && user.email!.trim().isNotEmpty) {
        return user.email!.trim();
      }
      for (final p in user.providerData) {
        if (p.phoneNumber != null && p.phoneNumber!.trim().isNotEmpty) {
          return p.phoneNumber!.trim();
        }
        if (p.email != null && p.email!.trim().isNotEmpty) {
          return p.email!.trim();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Links a durable Firebase [credential] (e.g. PhoneAuthProvider / GoogleAuthProvider)
  /// onto the existing anonymous UID so zero-friction onboarding keeps the exact
  /// same `ownerUid` while gaining device-loss recovery.
  Future<void> linkOwnerRecoveryCredential(AuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No active Firebase session to link');
    }
    final result = await user.linkWithCredential(credential);
    final linked = result.user;
    final shop = _currentShop;
    if (linked != null && shop != null && shop.isOwner) {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(shop.shopCode)
          .set({
            'recoveryLinked': true,
            'recoveryLabel': recoveryAccountLabel ?? '',
            'recoveryUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
    notifyListeners();
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
          unawaited(flushSyncOutbox().catchError((e) {
            debugPrint('Error flushing outbox on init: $e');
            return 0;
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
            unawaited(flushSyncOutbox().catchError((e) {
              debugPrint('Error flushing outbox on init: $e');
              return 0;
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
      final nowIso = DateTime.now().toIso8601String();
      final insertedId = await db.insert('customers', {
        'cloud_id': DatabaseHelper.generateUuidV4(),
        'name': cleanName,
        'phone': trimmedPhone,
        'is_active': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
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
      where:
          'COALESCE(is_active, 1) = 1 AND deleted_at IS NULL AND LOWER(TRIM(name)) = ?',
      whereArgs: [cleanName.toLowerCase()],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (existingCust.isNotEmpty) {
      return (existingCust.first['id'] as num).toInt();
    }

    final nowIso = DateTime.now().toIso8601String();
    return db.insert('customers', {
      'cloud_id': DatabaseHelper.generateUuidV4(),
      'name': cleanName,
      'phone': null,
      'is_active': 1,
      'created_at': nowIso,
      'updated_at': nowIso,
    });
  }

  void _notifySyncListeners() => notifyListeners();

  void _scheduleDebouncedNotify() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      notifyListeners();
    });
  }

  Future<void> _upsertSyncedProduct(
    DatabaseExecutor db,
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final rawCloudId = (data['cloud_id'] as String?)?.trim();
    final cloudId = (rawCloudId != null && rawCloudId.isNotEmpty)
        ? rawCloudId
        : (docId != null && docId.contains('-') ? docId : null);
    final prodId = (data['id'] as num?)?.toInt();
    final name = (data['name'] as String? ?? '').trim();
    final deletedAtStr = data['deleted_at']?.toString();
    final isTombstone = deletedAtStr != null && deletedAtStr.isNotEmpty;

    Map<String, Object?>? existingRow;
    if (cloudId != null && cloudId.isNotEmpty) {
      final byCloud = await db.query(
        'products',
        where: 'cloud_id = ?',
        whereArgs: [cloudId],
        limit: 1,
      );
      if (byCloud.isNotEmpty) existingRow = byCloud.first;
    }
    if (existingRow == null && name.isNotEmpty) {
      final byName = await db.query(
        'products',
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [name.toLowerCase()],
        limit: 1,
      );
      if (byName.isNotEmpty) existingRow = byName.first;
    }
    if (existingRow == null && prodId != null && rawCloudId == null) {
      final byId = await db.query('products', where: 'id = ?', whereArgs: [prodId], limit: 1);
      if (byId.isNotEmpty) {
        final localName = (byId.first['name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty || localName == name.toLowerCase()) {
          existingRow = byId.first;
        }
      }
    }

    if (isTombstone) {
      if (existingRow != null) {
        await db.update(
          'products',
          {
            'is_active': 0,
            'deleted_at': deletedAtStr,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existingRow['id']],
        );
      }
      return;
    }

    if (name.isEmpty) return;

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

      final resolvedCloudId = (existingRow['cloud_id'] as String?)?.isNotEmpty == true
          ? existingRow['cloud_id'] as String
          : (cloudId ?? DatabaseHelper.generateUuidV4());
      await db.update(
        'products',
        {
          'cloud_id': resolvedCloudId,
          'name': name,
          'category': data['category'] ?? existingRow['category'] ?? name,
          'is_active': data['is_active'] ?? 1,
          'configuration': data['configuration'] ?? existingRow['configuration'] ?? '{}',
          'price_updated_at': data['price_updated_at'],
          'updated_at': DateTime.now().toIso8601String(),
          'deleted_at': null,
          'needs_review': data['needs_review'] ?? 0,
        },
        where: 'id = ?',
        whereArgs: [existingRow['id']],
      );
      return;
    }

    final resolvedCloudId = cloudId ?? DatabaseHelper.generateUuidV4();
    final nowIso = DateTime.now().toIso8601String();
    final insertMap = <String, Object?>{
      if (prodId != null && rawCloudId == null) 'id': prodId,
      'cloud_id': resolvedCloudId,
      'name': name,
      'category': data['category'] ?? name,
      'is_active': data['is_active'] ?? 1,
      'configuration': data['configuration'] ?? '{}',
      'created_at': data['created_at'] ?? nowIso,
      'price_updated_at': data['price_updated_at'],
      'updated_at': nowIso,
      'needs_review': data['needs_review'] ?? 0,
    };
    await db.insert('products', insertMap);
  }

  Future<void> _upsertSyncedCustomer(
    DatabaseExecutor db,
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final rawCloudId = (data['cloud_id'] as String?)?.trim();
    final cloudId = (rawCloudId != null && rawCloudId.isNotEmpty)
        ? rawCloudId
        : (docId != null && docId.contains('-') ? docId : null);
    final rawName = (data['name'] as String? ?? '').trim();
    final rawPhone = (data['phone'] as String?)?.trim();
    final cloudCreditLimit = (data['credit_limit'] as num?)?.toDouble();
    final deletedAtStr = data['deleted_at']?.toString();
    final isTombstone = deletedAtStr != null && deletedAtStr.isNotEmpty;

    int? existingId;
    String? existingCloudId;
    if (cloudId != null && cloudId.isNotEmpty) {
      final byCloud = await db.query(
        'customers',
        columns: ['id', 'cloud_id'],
        where: 'cloud_id = ?',
        whereArgs: [cloudId],
        limit: 1,
      );
      if (byCloud.isNotEmpty) {
        existingId = (byCloud.first['id'] as num).toInt();
        existingCloudId = byCloud.first['cloud_id'] as String?;
      }
    }
    if (existingId == null &&
        rawPhone != null &&
        Customer.normalizePhoneDigits(rawPhone).length >= 6) {
      existingId = await DatabaseHelper.instance
          .findCustomerIdByNormalizedPhone(db, rawPhone);
    }
    final custId = (data['id'] as num?)?.toInt();
    if (existingId == null && custId != null && rawCloudId == null) {
      final byId = await db.query('customers', where: 'id = ?', whereArgs: [custId], limit: 1);
      if (byId.isNotEmpty) {
        final localName = (byId.first['name'] as String? ?? '').trim().toLowerCase();
        if (localName == rawName.toLowerCase() || (rawPhone == null || rawPhone.isEmpty)) {
          existingId = custId;
          existingCloudId = byId.first['cloud_id'] as String?;
        }
      }
    }
    if (existingId == null &&
        rawName.isNotEmpty &&
        (rawPhone == null || Customer.normalizePhoneDigits(rawPhone).length < 6)) {
      final byName = await db.query(
        'customers',
        columns: ['id', 'cloud_id'],
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [rawName.toLowerCase()],
        limit: 1,
      );
      if (byName.isNotEmpty) {
        existingId = (byName.first['id'] as num).toInt();
        existingCloudId = byName.first['cloud_id'] as String?;
      }
    }

    if (isTombstone) {
      if (existingId != null) {
        await db.update(
          'customers',
          {
            'is_active': 0,
            'deleted_at': deletedAtStr,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }
      return;
    }

    if (rawName.isEmpty) return;

    final nowIso = DateTime.now().toIso8601String();
    if (existingId != null) {
      final resolvedCloudId = (existingCloudId != null && existingCloudId.isNotEmpty)
          ? existingCloudId
          : (cloudId ?? DatabaseHelper.generateUuidV4());
      final updates = <String, Object?>{
        'cloud_id': resolvedCloudId,
        'name': rawName,
        'phone': (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null,
        'address': data['address'],
        'is_active': data['is_active'] ?? 1,
        'deleted_at': null,
        'updated_at': nowIso,
      };
      if (cloudCreditLimit != null) {
        updates['credit_limit'] = cloudCreditLimit;
      }
      await db.update('customers', updates, where: 'id = ?', whereArgs: [existingId]);
      return;
    }

    final insertMap = <String, Object?>{
      'cloud_id': cloudId ?? DatabaseHelper.generateUuidV4(),
      'name': rawName,
      'phone': (rawPhone != null && rawPhone.isNotEmpty) ? rawPhone : null,
      'address': data['address'],
      'credit_limit': cloudCreditLimit ?? 0.0,
      'is_active': data['is_active'] ?? 1,
      'created_at': data['created_at'] ?? nowIso,
      'updated_at': nowIso,
    };
    if (custId != null && rawCloudId == null) {
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

      // 1. Products (owner / permitted devices only; chunked into batches of 400; UUID key)
      if (canManageProducts) {
        final products = await db.query('products');
        for (var i = 0; i < products.length; i += 400) {
          final productBatch = firestore.batch();
          final end = (i + 400 < products.length) ? i + 400 : products.length;
          for (var j = i; j < end; j++) {
            final p = products[j];
            var cloudId = (p['cloud_id'] as String?)?.trim() ?? '';
            if (cloudId.isEmpty) {
              cloudId = DatabaseHelper.generateUuidV4();
              await db.update('products', {'cloud_id': cloudId}, where: 'id = ?', whereArgs: [p['id']]);
            }
            final docRef = firestore.collection('shops').doc(shopCode).collection('products').doc(cloudId);
            final prodMap = <String, dynamic>{
              'id': p['id'],
              'cloud_id': cloudId,
              'name': p['name'],
              'is_active': p['is_active'],
              'configuration': p['configuration'],
              'created_at': p['created_at'],
              if (p['deleted_at'] != null) 'deleted_at': p['deleted_at'],
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

      // 2. Customers (chunked into batches of 400; UUID key)
      final customers = await db.query('customers');
      for (var i = 0; i < customers.length; i += 400) {
        final custBatch = firestore.batch();
        final end = (i + 400 < customers.length) ? i + 400 : customers.length;
        for (var j = i; j < end; j++) {
          final c = customers[j];
          var cloudId = (c['cloud_id'] as String?)?.trim() ?? '';
          if (cloudId.isEmpty) {
            cloudId = DatabaseHelper.generateUuidV4();
            await db.update('customers', {'cloud_id': cloudId}, where: 'id = ?', whereArgs: [c['id']]);
          }
          final docRef = firestore.collection('shops').doc(shopCode).collection('customers').doc(cloudId);
          final custMap = <String, dynamic>{
            'id': c['id'],
            'cloud_id': cloudId,
            'name': c['name'],
            'is_active': c['is_active'] ?? 1,
            'credit_limit': (c['credit_limit'] as num?)?.toDouble() ?? 0.0,
            'created_at': c['created_at'],
            if (c['deleted_at'] != null) 'deleted_at': c['deleted_at'],
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

  /// Downloads cloud products, customers, orders, and payments into local SQLite.
  /// Uses incremental `updatedAt` delta cursors when available unless [fullResync] is true.
  Future<void> downloadCloudDataToLocal({bool fullResync = false}) async {
    if (_currentShop == null || !_isFirebaseAvailable) return;
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    final db = await _dbHelper.database;

    try {
      await flushSyncOutbox();

      final prefs = await SharedPreferences.getInstance();
      final cursorKey = '$_prefKeyDeltaCursorPrefix$shopCode';
      final cursorStr = fullResync ? null : prefs.getString(cursorKey);
      final parsedCursor = cursorStr != null ? DateTime.tryParse(cursorStr)?.toUtc() : null;
      final deltaSince = parsedCursor?.subtract(const Duration(minutes: 2));
      DateTime? maxObservedServerUpdatedAt = parsedCursor;

      void trackServerCursor(QuerySnapshot<Map<String, dynamic>> snap) {
        for (final doc in snap.docs) {
          final ts = doc.data()['updatedAt'];
          if (ts is Timestamp) {
            final serverTime = ts.toDate().toUtc();
            if (maxObservedServerUpdatedAt == null ||
                serverTime.isAfter(maxObservedServerUpdatedAt!)) {
              maxObservedServerUpdatedAt = serverTime;
            }
          }
        }
      }

      Future<QuerySnapshot<Map<String, dynamic>>> fetchDeltaOrAll(
        String collectionName,
      ) async {
        final col = firestore.collection('shops').doc(shopCode).collection(collectionName);
        if (deltaSince != null) {
          try {
            return await col
                .where('updatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(deltaSince.toUtc()))
                .get();
          } catch (_) {
            // Fall back to full fetch if query or index fails
          }
        }
        return col.get();
      }

      // 1. Sync Products
      final productSnaps = await fetchDeltaOrAll('products');
      trackServerCursor(productSnaps);
      for (final doc in productSnaps.docs) {
        await _upsertSyncedProduct(db, doc.data(), docId: doc.id);
      }

      // 2. Sync Customers
      final custSnaps = await fetchDeltaOrAll('customers');
      trackServerCursor(custSnaps);
      for (final doc in custSnaps.docs) {
        await _upsertSyncedCustomer(db, doc.data(), docId: doc.id);
      }

      // 3. Sync Orders
      final orderSnaps = await fetchDeltaOrAll('orders');
      trackServerCursor(orderSnaps);
      for (final doc in orderSnaps.docs) {
        await _upsertSyncedOrder(db, doc.id, doc.data());
      }

      // 4. Sync Payments
      final paySnaps = await fetchDeltaOrAll('payments');
      trackServerCursor(paySnaps);
      for (final doc in paySnaps.docs) {
        await _upsertSyncedPayment(db, doc.id, doc.data());
      }

      // Advance delta cursor strictly using server-assigned `updatedAt` timestamps
      // (never local device clock) so fast device clocks cannot skip server writes.
      if (maxObservedServerUpdatedAt != null) {
        await prefs.setString(
          cursorKey,
          maxObservedServerUpdatedAt!.toIso8601String(),
        );
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

  @override
  void dispose() {
    _notifyDebounceTimer?.cancel();
    _stopRealtimeListeners();
    super.dispose();
  }
}
