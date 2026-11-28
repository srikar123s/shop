part of 'shop_sync_service.dart';

extension ShopSyncRealtimeExtension on ShopSyncService {
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
      _scheduleDebouncedNotify();
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
            await _upsertSyncedProduct(db, data, docId: change.doc.id);
          } catch (e) {
            debugPrint('Error applying remote product ${change.doc.id}: $e');
          }
        }
      }
      _lastSyncTime = DateTime.now();
      _scheduleDebouncedNotify();
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
            await _upsertSyncedCustomer(db, data, docId: change.doc.id);
          } catch (e) {
            debugPrint('Error applying remote customer ${change.doc.id}: $e');
          }
        }
      }
      _lastSyncTime = DateTime.now();
      _scheduleDebouncedNotify();
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
      _scheduleDebouncedNotify();
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
          _notifySyncListeners();
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
          _notifySyncListeners();
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
          await prefs.setString(ShopSyncService._prefKeyShopProfile, _currentShop!.toJson());
          _notifySyncListeners();
        }
      }
      final devStatus = (data['status'] as String? ?? 'pending').toLowerCase();
      if (devStatus == 'approved') {
        if (_currentShop != null && _currentShop!.isPending) {
          _currentShop = _currentShop!.copyWith(status: 'approved');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(ShopSyncService._prefKeyShopProfile, _currentShop!.toJson());
          _status = SyncStatus.connected;
          _statusMessage = 'Approved! Synced with ${_currentShop!.shopName}';
          await downloadCloudDataToLocal();
          _startRealtimeListeners();
          _notifySyncListeners();
        }
      } else if (devStatus == 'rejected') {
        _status = SyncStatus.error;
        _statusMessage = 'Join request was declined by the shop owner.';
        await leaveShop();
        _notifySyncListeners();
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
      await prefs.setString(ShopSyncService._prefKeyShopProfile, _currentShop!.toJson());
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

    _notifySyncListeners();
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
    await prefs.setString(ShopSyncService._prefKeyShopProfile, _currentShop!.toJson());
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
    _notifySyncListeners();
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
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = null;
    StorageMonitorService.instance.stopListening();
  }

}
