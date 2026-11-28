part of 'shop_sync_service.dart';

/// Delivery partner, location, and ledger cloud synchronization.
extension DeliverySyncAdapter on ShopSyncService {
  // =========================================================================
  // DELIVERY PARTNERS, LOCATIONS & TRANSACTIONS CLOUD SYNC
  // =========================================================================

  String generateCloudId(String prefix) {
    return '${prefix}_${DatabaseHelper.generateUuidV4()}';
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
      _scheduleDebouncedNotify();
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
      _scheduleDebouncedNotify();
    });
  }

  Future<void> _pushDeliveryPartnerDoc(DeliveryPartner partner) async {
    final cloudId = partner.cloudPartnerId;
    if (cloudId == null || cloudId.isEmpty) return;
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
  }

  Future<void> syncDeliveryPartner(DeliveryPartner partner) async {
    if (_currentShop == null) return;
    final cloudId = partner.cloudPartnerId;
    if (cloudId == null || cloudId.isEmpty) return;
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'delivery_partner',
        localId: partner.id,
        cloudId: cloudId,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushDeliveryPartnerDoc(partner);
      await _removeOutboxEntry('delivery_partner', cloudId);
    } catch (e) {
      debugPrint('Error syncing delivery partner: $e');
      await enqueueOutboxEntry(
        entityType: 'delivery_partner',
        localId: partner.id,
        cloudId: cloudId,
        error: e.toString(),
      );
    }
  }

  Future<void> deleteDeliveryPartnerFromCloud(String cloudPartnerId) async {
    if (_currentShop == null || cloudPartnerId.isEmpty) return;
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'delivery_partner_delete',
        cloudId: cloudPartnerId,
        error: 'Offline',
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_partners')
          .doc(cloudPartnerId)
          .delete();
      await _removeOutboxEntry('delivery_partner_delete', cloudPartnerId);
    } catch (e) {
      debugPrint('Error deleting delivery partner from cloud: $e');
      await enqueueOutboxEntry(
        entityType: 'delivery_partner_delete',
        cloudId: cloudPartnerId,
        error: e.toString(),
      );
    }
  }

  Future<void> _pushDeliveryLocationDoc(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
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
  }

  Future<void> syncDeliveryLocation(String name) async {
    final clean = name.trim();
    if (_currentShop == null || clean.isEmpty) return;
    final docId = clean.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'delivery_location',
        cloudId: docId,
        payload: {'name': clean},
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushDeliveryLocationDoc(clean);
      await _removeOutboxEntry('delivery_location', docId);
    } catch (e) {
      debugPrint('Error syncing delivery location: $e');
      await enqueueOutboxEntry(
        entityType: 'delivery_location',
        cloudId: docId,
        payload: {'name': clean},
        error: e.toString(),
      );
    }
  }

  Future<void> _pushDeliveryTxDoc(
    DeliveryTransaction tx, {
    required String partnerCloudId,
    required String partnerName,
  }) async {
    final cloudTxId = tx.cloudTxId;
    if (cloudTxId == null || cloudTxId.isEmpty) return;
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
  }

  Future<void> syncDeliveryTransaction(
    DeliveryTransaction tx, {
    required String partnerCloudId,
    required String partnerName,
  }) async {
    if (_currentShop == null) return;
    final cloudTxId = tx.cloudTxId;
    if (cloudTxId == null || cloudTxId.isEmpty) return;
    final metaPayload = {
      'partnerCloudId': partnerCloudId,
      'partnerName': partnerName,
    };
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'delivery_tx',
        localId: tx.id,
        cloudId: cloudTxId,
        payload: metaPayload,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushDeliveryTxDoc(
        tx,
        partnerCloudId: partnerCloudId,
        partnerName: partnerName,
      );
      await _removeOutboxEntry('delivery_tx', cloudTxId);
    } catch (e) {
      debugPrint('Error syncing delivery transaction: $e');
      await enqueueOutboxEntry(
        entityType: 'delivery_tx',
        localId: tx.id,
        cloudId: cloudTxId,
        payload: metaPayload,
        error: e.toString(),
      );
    }
  }

  Future<void> deleteDeliveryTransactionFromCloud(String cloudTxId) async {
    if (_currentShop == null || cloudTxId.isEmpty) return;
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'delivery_tx_delete',
        cloudId: cloudTxId,
        error: 'Offline',
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShop!.shopCode)
          .collection('delivery_transactions')
          .doc(cloudTxId)
          .delete();
      await _removeOutboxEntry('delivery_tx_delete', cloudTxId);
    } catch (e) {
      debugPrint('Error deleting delivery transaction from cloud: $e');
      await enqueueOutboxEntry(
        entityType: 'delivery_tx_delete',
        cloudId: cloudTxId,
        error: e.toString(),
      );
    }
  }
}
