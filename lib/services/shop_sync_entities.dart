part of 'shop_sync_service.dart';

extension ShopSyncEntitiesExtension on ShopSyncService {
  Future<List<Map<String, dynamic>>> _buildCompactOrderItemsPayload(
    Database db,
    int orderId,
  ) async {
    final items =
        await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
    final itemIds = items
        .map((r) => (r['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final optionsByItemId = <int, List<Map<String, Object?>>>{};
    for (var i = 0; i < itemIds.length; i += 400) {
      final chunk = itemIds.sublist(
        i,
        i + 400 > itemIds.length ? itemIds.length : i + 400,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT order_item_id, option_name, option_value '
        'FROM order_item_options WHERE order_item_id IN ($placeholders)',
        chunk,
      );
      for (final opt in rows) {
        final key = (opt['order_item_id'] as num?)?.toInt();
        if (key != null) {
          optionsByItemId.putIfAbsent(key, () => []).add(opt);
        }
      }
    }

    final itemsPayload = <Map<String, dynamic>>[];
    for (final item in items) {
      final itemId = item['id'] as int;
      final options = optionsByItemId[itemId] ?? const <Map<String, Object?>>[];
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

  Future<void> _pushOrderDoc(int orderId) async {
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
  }

  /// Push a single newly created or updated order to the cloud in real-time
  Future<void> syncOrder(int orderId) async {
    if (_currentShop == null) return;
    final cloudIdHint = 'order_$orderId';
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'order',
        localId: orderId,
        cloudId: cloudIdHint,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushOrderDoc(orderId);
      await _removeOutboxEntry('order', cloudIdHint);
      _lastSyncTime = DateTime.now();
      _notifySyncListeners();
    } catch (e) {
      debugPrint('Error syncing order $orderId: $e');
      await enqueueOutboxEntry(
        entityType: 'order',
        localId: orderId,
        cloudId: cloudIdHint,
        error: e.toString(),
      );
    }
  }

  Future<void> _pushPaymentDoc(int paymentId) async {
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
  }

  /// Push a single customer payment to cloud
  Future<void> syncPayment(int paymentId) async {
    if (_currentShop == null) return;
    final cloudIdHint = 'payment_$paymentId';
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'payment',
        localId: paymentId,
        cloudId: cloudIdHint,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushPaymentDoc(paymentId);
      await _removeOutboxEntry('payment', cloudIdHint);
      _lastSyncTime = DateTime.now();
      _notifySyncListeners();
    } catch (e) {
      debugPrint('Error syncing payment $paymentId: $e');
      await enqueueOutboxEntry(
        entityType: 'payment',
        localId: paymentId,
        cloudId: cloudIdHint,
        error: e.toString(),
      );
    }
  }

  Future<String> _ensureProductCloudId(Product product) async {
    if (product.cloudId != null && product.cloudId!.isNotEmpty) {
      return product.cloudId!;
    }
    final db = await _dbHelper.database;
    if (product.id != null) {
      final rows = await db.query(
        'products',
        columns: ['cloud_id'],
        where: 'id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      final existing = rows.isNotEmpty ? rows.first['cloud_id'] as String? : null;
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = DatabaseHelper.generateUuidV4();
      await db.update('products', {'cloud_id': generated}, where: 'id = ?', whereArgs: [product.id]);
      return generated;
    }
    return DatabaseHelper.generateUuidV4();
  }

  Future<String> _pushProductDoc(Product product) async {
    final cloudId = await _ensureProductCloudId(product);
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    await firestore.collection('shops').doc(shopCode).collection('products').doc(cloudId).set({
      ...product.toMap(),
      'cloud_id': cloudId,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedByDevice': _deviceId,
    }, SetOptions(merge: true));
    return cloudId;
  }

  Future<void> _pushProductTombstone(String cloudId) async {
    await FirebaseFirestore.instance
        .collection('shops')
        .doc(_currentShop!.shopCode)
        .collection('products')
        .doc(cloudId)
        .set({
      'cloud_id': cloudId,
      'is_active': 0,
      'deleted_at': DateTime.now().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedByDevice': _deviceId,
    }, SetOptions(merge: true));
  }

  /// Push a single product to cloud
  Future<void> syncProduct(Product product) async {
    if (_currentShop == null || product.id == null || !canManageProducts) return;
    final cloudId = await _ensureProductCloudId(product);
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'product',
        localId: product.id,
        cloudId: cloudId,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushProductDoc(product.copyWith(cloudId: cloudId));
      await _removeOutboxEntry('product', cloudId);
      _lastSyncTime = DateTime.now();
      _notifySyncListeners();
    } catch (e) {
      debugPrint('Error syncing product ${product.id}: $e');
      await enqueueOutboxEntry(
        entityType: 'product',
        localId: product.id,
        cloudId: cloudId,
        error: e.toString(),
      );
    }
  }

  /// Push a batch of products to cloud via chunked WriteBatch (up to 400 per batch)
  Future<void> syncProductsBatch(List<Product> products) async {
    if (_currentShop == null || products.isEmpty || !canManageProducts) return;
    final shopCode = _currentShop!.shopCode;
    final firestore = _isFirebaseAvailable ? FirebaseFirestore.instance : null;
    for (var i = 0; i < products.length; i += 400) {
      final chunk = products.sublist(
        i,
        i + 400 > products.length ? products.length : i + 400,
      );
      if (firestore == null) {
        for (final p in chunk) {
          if (p.id == null) continue;
          final cloudId = await _ensureProductCloudId(p);
          await enqueueOutboxEntry(
            entityType: 'product',
            localId: p.id,
            cloudId: cloudId,
            error: 'Offline',
          );
        }
        continue;
      }
      try {
        final batch = firestore.batch();
        for (final p in chunk) {
          if (p.id == null) continue;
          final cloudId = await _ensureProductCloudId(p);
          final ref = firestore.collection('shops').doc(shopCode).collection('products').doc(cloudId);
          batch.set(ref, {
            ...p.toMap(),
            'cloud_id': cloudId,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastUpdatedByDevice': _deviceId,
          }, SetOptions(merge: true));
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Error batch syncing products: $e');
        for (final p in chunk) {
          if (p.id == null) continue;
          final cloudId = await _ensureProductCloudId(p);
          await enqueueOutboxEntry(
            entityType: 'product',
            localId: p.id,
            cloudId: cloudId,
            error: e.toString(),
          );
        }
      }
    }
    _lastSyncTime = DateTime.now();
    _scheduleDebouncedNotify();
  }

  Future<void> deleteProductFromCloud(String cloudId) async {
    if (_currentShop == null || cloudId.isEmpty || !canManageProducts) return;
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'product_delete',
        cloudId: cloudId,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushProductTombstone(cloudId);
      await _removeOutboxEntry('product_delete', cloudId);
    } catch (e) {
      debugPrint('Error syncing product tombstone $cloudId: $e');
      await enqueueOutboxEntry(
        entityType: 'product_delete',
        cloudId: cloudId,
        error: e.toString(),
      );
    }
  }

  Future<String> _ensureCustomerCloudId(Customer customer) async {
    if (customer.cloudId != null && customer.cloudId!.isNotEmpty) {
      return customer.cloudId!;
    }
    final db = await _dbHelper.database;
    if (customer.id != null) {
      final rows = await db.query(
        'customers',
        columns: ['cloud_id'],
        where: 'id = ?',
        whereArgs: [customer.id],
        limit: 1,
      );
      final existing = rows.isNotEmpty ? rows.first['cloud_id'] as String? : null;
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = DatabaseHelper.generateUuidV4();
      await db.update('customers', {'cloud_id': generated}, where: 'id = ?', whereArgs: [customer.id]);
      return generated;
    }
    return DatabaseHelper.generateUuidV4();
  }

  Future<String> _pushCustomerDoc(Customer customer) async {
    final cloudId = await _ensureCustomerCloudId(customer);
    final firestore = FirebaseFirestore.instance;
    final shopCode = _currentShop!.shopCode;
    await firestore.collection('shops').doc(shopCode).collection('customers').doc(cloudId).set({
      ...customer.toMap(),
      'cloud_id': cloudId,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedByDevice': _deviceId,
    }, SetOptions(merge: true));
    return cloudId;
  }

  Future<void> _pushCustomerTombstone(String cloudId) async {
    await FirebaseFirestore.instance
        .collection('shops')
        .doc(_currentShop!.shopCode)
        .collection('customers')
        .doc(cloudId)
        .set({
      'cloud_id': cloudId,
      'is_active': 0,
      'deleted_at': DateTime.now().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedByDevice': _deviceId,
    }, SetOptions(merge: true));
  }

  /// Push a single customer to cloud
  Future<void> syncCustomer(Customer customer) async {
    if (_currentShop == null || customer.id == null) return;
    final cloudId = await _ensureCustomerCloudId(customer);
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'customer',
        localId: customer.id,
        cloudId: cloudId,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushCustomerDoc(customer.copyWith(cloudId: cloudId));
      await _removeOutboxEntry('customer', cloudId);
      _lastSyncTime = DateTime.now();
      _notifySyncListeners();
    } catch (e) {
      debugPrint('Error syncing customer ${customer.id}: $e');
      await enqueueOutboxEntry(
        entityType: 'customer',
        localId: customer.id,
        cloudId: cloudId,
        error: e.toString(),
      );
    }
  }

  Future<void> deleteCustomerFromCloud(String cloudId) async {
    if (_currentShop == null || cloudId.isEmpty) return;
    if (!_isFirebaseAvailable) {
      await enqueueOutboxEntry(
        entityType: 'customer_delete',
        cloudId: cloudId,
        error: 'Offline',
      );
      return;
    }
    try {
      await _pushCustomerTombstone(cloudId);
      await _removeOutboxEntry('customer_delete', cloudId);
    } catch (e) {
      debugPrint('Error syncing customer tombstone $cloudId: $e');
      await enqueueOutboxEntry(
        entityType: 'customer_delete',
        cloudId: cloudId,
        error: e.toString(),
      );
    }
  }

}
