import 'dart:async';

import 'package:shop/database/database_helper.dart';
import 'package:shop/models/delivery_partner.dart';
import 'package:shop/services/shop_sync_service.dart';

class DeliveryRepository {
  DeliveryRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<DeliveryPartner>> getPartnersWithSummary() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        dp.*,
        COALESCE(SUM(dt.earned_amount), 0.0) AS total_earned,
        COALESCE(SUM(dt.paid_amount), 0.0) AS total_paid,
        COUNT(dt.id) AS tx_count,
        MAX(dt.created_at) AS last_tx_at
      FROM delivery_partners dp
      LEFT JOIN delivery_transactions dt ON dt.partner_id = dp.id
      WHERE dp.is_active = 1
      GROUP BY dp.id
      ORDER BY COALESCE(MAX(dt.created_at), dp.created_at) DESC, dp.name COLLATE NOCASE ASC
    ''');
    return rows.map(DeliveryPartner.fromMap).toList();
  }

  Future<DeliveryPartner?> getPartnerById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        dp.*,
        COALESCE(SUM(dt.earned_amount), 0.0) AS total_earned,
        COALESCE(SUM(dt.paid_amount), 0.0) AS total_paid,
        COUNT(dt.id) AS tx_count,
        MAX(dt.created_at) AS last_tx_at
      FROM delivery_partners dp
      LEFT JOIN delivery_transactions dt ON dt.partner_id = dp.id
      WHERE dp.id = ?
      GROUP BY dp.id
    ''', [id]);
    if (rows.isEmpty) return null;
    return DeliveryPartner.fromMap(rows.first);
  }

  Future<int> addPartner({
    required String name,
    String? phone,
    String? vehicleInfo,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final cloudId = ShopSyncService.instance.generateCloudId('dp');
    final now = DateTime.now();
    final partner = DeliveryPartner(
      cloudPartnerId: cloudId,
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      vehicleInfo:
          vehicleInfo?.trim().isEmpty == true ? null : vehicleInfo?.trim(),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      createdAt: now,
    );
    final id = await db.insert('delivery_partners', partner.toMap());
    unawaited(ShopSyncService.instance
        .syncDeliveryPartner(partner.copyWith(id: id))
        .catchError((_) {}));
    return id;
  }

  Future<void> updatePartner(DeliveryPartner partner) async {
    if (partner.id == null) return;
    final db = await _dbHelper.database;
    final cloudId = partner.cloudPartnerId ??
        ShopSyncService.instance.generateCloudId('dp');
    await db.update(
      'delivery_partners',
      {
        'cloud_partner_id': cloudId,
        'name': partner.name.trim(),
        'phone':
            partner.phone?.trim().isEmpty == true ? null : partner.phone?.trim(),
        'vehicle_info': partner.vehicleInfo?.trim().isEmpty == true
            ? null
            : partner.vehicleInfo?.trim(),
        'notes':
            partner.notes?.trim().isEmpty == true ? null : partner.notes?.trim(),
      },
      where: 'id = ?',
      whereArgs: [partner.id],
    );
    unawaited(ShopSyncService.instance
        .syncDeliveryPartner(partner.copyWith(cloudPartnerId: cloudId))
        .catchError((_) {}));
  }

  Future<void> deletePartner(int id) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'delivery_partners',
      columns: ['cloud_partner_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final cloudId = existing.isNotEmpty
        ? existing.first['cloud_partner_id'] as String?
        : null;
    await db.delete('delivery_partners', where: 'id = ?', whereArgs: [id]);
    if (cloudId != null && cloudId.isNotEmpty) {
      unawaited(ShopSyncService.instance
          .deleteDeliveryPartnerFromCloud(cloudId)
          .catchError((_) {}));
    }
  }

  /// Returns all unique locations from existing customers AND saved delivery locations.
  Future<List<String>> getLocations() async {
    final db = await _dbHelper.database;
    final customerLocs = await db.rawQuery('''
      SELECT DISTINCT TRIM(address) AS loc
      FROM customers
      WHERE address IS NOT NULL AND TRIM(address) != ''
    ''');
    final savedLocs = await db.rawQuery('''
      SELECT DISTINCT TRIM(name) AS loc
      FROM delivery_locations
      WHERE name IS NOT NULL AND TRIM(name) != ''
    ''');

    final seenLower = <String, String>{};
    for (final row in [...savedLocs, ...customerLocs]) {
      final loc = (row['loc'] as String?)?.trim() ?? '';
      if (loc.isEmpty) continue;
      final key = loc.toLowerCase();
      seenLower.putIfAbsent(key, () => loc);
    }

    final result = seenLower.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<void> addLocation(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await _dbHelper.database;
    await db.rawInsert('''
      INSERT OR IGNORE INTO delivery_locations (name, created_at)
      VALUES (?, ?)
    ''', [trimmed, DateTime.now().toIso8601String()]);
    unawaited(
        ShopSyncService.instance.syncDeliveryLocation(trimmed).catchError((_) {}));
  }

  Future<List<DeliveryTransaction>> getTransactionsForPartner(
      int partnerId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'delivery_transactions',
      where: 'partner_id = ?',
      whereArgs: [partnerId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(DeliveryTransaction.fromMap).toList();
  }

  Future<int> addTransaction(DeliveryTransaction tx) async {
    final db = await _dbHelper.database;
    if (tx.location != null && tx.location!.trim().isNotEmpty) {
      await addLocation(tx.location!);
    }
    final cloudTxId = tx.cloudTxId ?? ShopSyncService.instance.generateCloudId('dtx');
    final map = tx.toMap();
    map['cloud_tx_id'] = cloudTxId;
    final id = await db.insert('delivery_transactions', map);

    final partnerRows = await db.query(
      'delivery_partners',
      columns: ['cloud_partner_id', 'name'],
      where: 'id = ?',
      whereArgs: [tx.partnerId],
      limit: 1,
    );
    if (partnerRows.isNotEmpty) {
      var partnerCloudId =
          partnerRows.first['cloud_partner_id'] as String? ?? '';
      final partnerName = (partnerRows.first['name'] as String?) ?? 'Partner';
      if (partnerCloudId.isEmpty) {
        partnerCloudId = ShopSyncService.instance.generateCloudId('dp');
        await db.update(
          'delivery_partners',
          {'cloud_partner_id': partnerCloudId},
          where: 'id = ?',
          whereArgs: [tx.partnerId],
        );
      }
      final syncedTx = DeliveryTransaction(
        id: id,
        cloudTxId: cloudTxId,
        partnerId: tx.partnerId,
        txType: tx.txType,
        location: tx.location,
        totalBoxes: tx.totalBoxes,
        rateTiers: tx.rateTiers,
        earnedAmount: tx.earnedAmount,
        paidAmount: tx.paidAmount,
        cutAmount: tx.cutAmount,
        paymentMode: tx.paymentMode,
        description: tx.description,
        createdAt: tx.createdAt,
      );
      unawaited(ShopSyncService.instance
          .syncDeliveryTransaction(
            syncedTx,
            partnerCloudId: partnerCloudId,
            partnerName: partnerName,
          )
          .catchError((_) {}));
    }
    return id;
  }

  Future<void> deleteTransaction(int id) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'delivery_transactions',
      columns: ['cloud_tx_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final cloudTxId = existing.isNotEmpty
        ? existing.first['cloud_tx_id'] as String?
        : null;
    await db.delete('delivery_transactions', where: 'id = ?', whereArgs: [id]);
    if (cloudTxId != null && cloudTxId.isNotEmpty) {
      unawaited(ShopSyncService.instance
          .deleteDeliveryTransactionFromCloud(cloudTxId)
          .catchError((_) {}));
    }
  }
}
