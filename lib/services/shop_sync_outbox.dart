part of 'shop_sync_service.dart';

/// Durable SQLite outbox queue and exponential backoff flush routines.
extension ShopSyncOutbox on ShopSyncService {
  /// Records a failed/offline sync operation in the durable SQLite `sync_outbox`
  /// table with exponential backoff so mutations are never lost.
  Future<void> enqueueOutboxEntry({
    required String entityType,
    int? localId,
    required String cloudId,
    Map<String, dynamic>? payload,
    String? error,
  }) async {
    if (cloudId.isEmpty) return;
    try {
      final db = await _dbHelper.database;
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final existing = await db.query(
        'sync_outbox',
        columns: ['id', 'retry_count'],
        where: 'entity_type = ? AND cloud_id = ?',
        whereArgs: [entityType, cloudId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final prevRetry = (existing.first['retry_count'] as num?)?.toInt() ?? 0;
        final nextRetry = prevRetry + 1;
        final backoffSec = min(300, 1 << min(nextRetry, 8));
        await db.update(
          'sync_outbox',
          {
            if (localId != null) 'local_id': localId,
            if (payload != null) 'payload_json': jsonEncode(payload),
            'retry_count': nextRetry,
            'next_retry_at': now.add(Duration(seconds: backoffSec)).toIso8601String(),
            if (error != null) 'last_error': error,
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert('sync_outbox', {
          'entity_type': entityType,
          'local_id': localId,
          'cloud_id': cloudId,
          'payload_json': payload != null ? jsonEncode(payload) : null,
          'retry_count': 0,
          'next_retry_at': nowIso,
          'last_error': error,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }
    } catch (e) {
      debugPrint('Failed to enqueue sync_outbox ($entityType/$cloudId): $e');
    }
  }

  Future<void> _removeOutboxEntry(String entityType, String cloudId) async {
    if (cloudId.isEmpty) return;
    try {
      final db = await _dbHelper.database;
      await db.delete(
        'sync_outbox',
        where: 'entity_type = ? AND cloud_id = ?',
        whereArgs: [entityType, cloudId],
      );
    } catch (_) {}
  }

  /// Flushes due entries from the durable `sync_outbox` table to Firestore.
  Future<int> flushSyncOutbox() async {
    if (_isFlushingOutbox || _currentShop == null || !_isFirebaseAvailable) {
      return 0;
    }
    _isFlushingOutbox = true;
    int syncedCount = 0;
    try {
      final db = await _dbHelper.database;
      final nowIso = DateTime.now().toIso8601String();
      final dueRows = await db.query(
        'sync_outbox',
        where: 'next_retry_at <= ?',
        whereArgs: [nowIso],
        orderBy: 'id ASC',
        limit: 100,
      );
      for (final row in dueRows) {
        final entityType = row['entity_type'] as String? ?? '';
        final localId = (row['local_id'] as num?)?.toInt();
        final cloudId = row['cloud_id'] as String? ?? '';
        final rawPayload = row['payload_json'] as String?;
        Map<String, dynamic>? payload;
        if (rawPayload != null && rawPayload.isNotEmpty) {
          try {
            payload = (jsonDecode(rawPayload) as Map).cast<String, dynamic>();
          } catch (_) {}
        }

        try {
          switch (entityType) {
            case 'product':
              if (localId != null) {
                final pRows = await db.query('products', where: 'id = ?', whereArgs: [localId], limit: 1);
                if (pRows.isNotEmpty) {
                  await _pushProductDoc(Product.fromMap(pRows.first));
                }
              }
              break;
            case 'product_delete':
              await _pushProductTombstone(cloudId);
              break;
            case 'customer':
              if (localId != null) {
                final cRows = await db.query('customers', where: 'id = ?', whereArgs: [localId], limit: 1);
                if (cRows.isNotEmpty) {
                  await _pushCustomerDoc(Customer.fromMap(cRows.first));
                }
              }
              break;
            case 'customer_delete':
              await _pushCustomerTombstone(cloudId);
              break;
            case 'order':
              if (localId != null) {
                await _pushOrderDoc(localId);
              }
              break;
            case 'payment':
              if (localId != null) {
                await _pushPaymentDoc(localId);
              }
              break;
            case 'delivery_partner':
              if (localId != null) {
                final dpRows = await db.query('delivery_partners', where: 'id = ?', whereArgs: [localId], limit: 1);
                if (dpRows.isNotEmpty) {
                  await _pushDeliveryPartnerDoc(DeliveryPartner.fromMap(dpRows.first));
                }
              }
              break;
            case 'delivery_partner_delete':
              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(_currentShop!.shopCode)
                  .collection('delivery_partners')
                  .doc(cloudId)
                  .delete();
              break;
            case 'delivery_location':
              final locName = (payload?['name'] as String?) ?? cloudId;
              await _pushDeliveryLocationDoc(locName);
              break;
            case 'delivery_tx':
              if (localId != null) {
                final txRows = await db.query('delivery_transactions', where: 'id = ?', whereArgs: [localId], limit: 1);
                if (txRows.isNotEmpty) {
                  final tx = DeliveryTransaction.fromMap(txRows.first);
                  await _pushDeliveryTxDoc(
                    tx,
                    partnerCloudId: (payload?['partnerCloudId'] as String?) ?? '',
                    partnerName: (payload?['partnerName'] as String?) ?? 'Partner',
                  );
                }
              }
              break;
            case 'delivery_tx_delete':
              await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(_currentShop!.shopCode)
                  .collection('delivery_transactions')
                  .doc(cloudId)
                  .delete();
              break;
          }
          await db.delete('sync_outbox', where: 'id = ?', whereArgs: [row['id']]);
          syncedCount++;
        } catch (e) {
          await enqueueOutboxEntry(
            entityType: entityType,
            localId: localId,
            cloudId: cloudId,
            payload: payload,
            error: e.toString(),
          );
        }
      }
    } finally {
      _isFlushingOutbox = false;
    }
    return syncedCount;
  }
}
