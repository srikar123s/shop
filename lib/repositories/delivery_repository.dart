import 'package:shop/database/database_helper.dart';
import 'package:shop/models/delivery_partner.dart';

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
    return db.insert('delivery_partners', {
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'vehicle_info':
          vehicleInfo?.trim().isEmpty == true ? null : vehicleInfo?.trim(),
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updatePartner(DeliveryPartner partner) async {
    if (partner.id == null) return;
    final db = await _dbHelper.database;
    await db.update(
      'delivery_partners',
      {
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
  }

  Future<void> deletePartner(int id) async {
    final db = await _dbHelper.database;
    await db.delete('delivery_partners', where: 'id = ?', whereArgs: [id]);
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
    return db.insert('delivery_transactions', tx.toMap());
  }

  Future<void> deleteTransaction(int id) async {
    final db = await _dbHelper.database;
    await db.delete('delivery_transactions', where: 'id = ?', whereArgs: [id]);
  }
}
