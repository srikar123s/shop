import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:sqflite/sqflite.dart';

class StorageArchiveRecord {
  const StorageArchiveRecord({
    required this.archiveId,
    required this.ruleApplied,
    required this.dateRangeStart,
    required this.dateRangeEnd,
    required this.recordCount,
    required this.archivedDocIds,
    this.checksum,
    required this.compressedGzipBase64,
    required this.verified,
    this.restoredAt,
    required this.createdAt,
  });

  final String archiveId;
  final String ruleApplied;
  final DateTime dateRangeStart;
  final DateTime dateRangeEnd;
  final int recordCount;
  final List<String> archivedDocIds;
  final String? checksum;
  final String compressedGzipBase64;
  final bool verified;
  final DateTime? restoredAt;
  final DateTime createdAt;

  Map<String, Object?> toDbMap() => {
        'archive_id': archiveId,
        'rule_applied': ruleApplied,
        'date_range_start': dateRangeStart.toIso8601String(),
        'date_range_end': dateRangeEnd.toIso8601String(),
        'record_count': recordCount,
        'archived_doc_ids_json': jsonEncode(archivedDocIds),
        'checksum': checksum,
        'compressed_gzip_base64': compressedGzipBase64,
        'verified': verified ? 1 : 0,
        'restored_at': restoredAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory StorageArchiveRecord.fromMap(Map<String, dynamic> map) {
    List<String> docIds = const [];
    final rawIds = map['archived_doc_ids_json'] ?? map['archivedDocIds'];
    if (rawIds is String && rawIds.isNotEmpty) {
      try {
        docIds = (jsonDecode(rawIds) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    } else if (rawIds is List) {
      docIds = rawIds.map((e) => e.toString()).toList();
    }

    return StorageArchiveRecord(
      archiveId: (map['archive_id'] ?? map['archiveId'] ?? '').toString(),
      ruleApplied: (map['rule_applied'] ?? map['ruleApplied'] ?? 'rule_a_1_month')
          .toString(),
      dateRangeStart: DateTime.tryParse(
              (map['date_range_start'] ?? map['dateRangeStart'] ?? '')
                  .toString()) ??
          DateTime.now(),
      dateRangeEnd: DateTime.tryParse(
              (map['date_range_end'] ?? map['dateRangeEnd'] ?? '').toString()) ??
          DateTime.now(),
      recordCount:
          ((map['record_count'] ?? map['recordCount']) as num?)?.toInt() ?? 0,
      archivedDocIds: docIds,
      checksum: map['checksum'] as String?,
      compressedGzipBase64:
          (map['compressed_gzip_base64'] ?? map['compressedGzipBase64'] ?? '')
              .toString(),
      verified: map['verified'] == true ||
          ((map['verified'] as num?)?.toInt() ?? 0) == 1,
      restoredAt: (map['restored_at'] ?? map['restoredAt']) != null
          ? DateTime.tryParse(
              (map['restored_at'] ?? map['restoredAt']).toString())
          : null,
      createdAt: DateTime.tryParse(
              (map['created_at'] ?? map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class StorageAuditLog {
  const StorageAuditLog({
    this.id,
    required this.action,
    this.jobId,
    this.archiveId,
    this.ruleApplied,
    required this.status,
    this.recordsArchived = 0,
    this.recordsDeleted = 0,
    this.bytesBefore = 0,
    this.bytesAfter = 0,
    this.reclaimedBytes = 0,
    this.message,
    required this.createdAt,
  });

  final int? id;
  final String action;
  final String? jobId;
  final String? archiveId;
  final String? ruleApplied;
  final String status;
  final int recordsArchived;
  final int recordsDeleted;
  final int bytesBefore;
  final int bytesAfter;
  final int reclaimedBytes;
  final String? message;
  final DateTime createdAt;

  Map<String, Object?> toDbMap() => {
        'action': action,
        'job_id': jobId,
        'archive_id': archiveId,
        'rule_applied': ruleApplied,
        'status': status,
        'records_archived': recordsArchived,
        'records_deleted': recordsDeleted,
        'bytes_before': bytesBefore,
        'bytes_after': bytesAfter,
        'reclaimed_bytes': reclaimedBytes,
        'message': message,
        'created_at': createdAt.toIso8601String(),
      };

  factory StorageAuditLog.fromMap(Map<String, dynamic> map) {
    return StorageAuditLog(
      id: (map['id'] as num?)?.toInt(),
      action: (map['action'] ?? '').toString(),
      jobId: (map['job_id'] ?? map['jobId']) as String?,
      archiveId: (map['archive_id'] ?? map['archiveId']) as String?,
      ruleApplied: (map['rule_applied'] ?? map['ruleApplied']) as String?,
      status: (map['status'] ?? 'info').toString(),
      recordsArchived:
          ((map['records_archived'] ?? map['recordsArchived']) as num?)
                  ?.toInt() ??
              0,
      recordsDeleted:
          ((map['records_deleted'] ?? map['recordsDeleted']) as num?)
                  ?.toInt() ??
              0,
      bytesBefore:
          ((map['bytes_before'] ?? map['bytesBefore']) as num?)?.toInt() ?? 0,
      bytesAfter:
          ((map['bytes_after'] ?? map['bytesAfter']) as num?)?.toInt() ?? 0,
      reclaimedBytes:
          ((map['reclaimed_bytes'] ?? map['reclaimedBytes']) as num?)
                  ?.toInt() ??
              0,
      message: (map['message'] ?? map['error']) as String?,
      createdAt: DateTime.tryParse(
              (map['created_at'] ?? map['timestamp'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Manages dated gzip-compressed archives, verification before deletion,
/// audit logs, and full restoration of archived orders & transactions.
class ArchiveService {
  ArchiveService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Compresses records using GZip, verifies round-trip readability & record count,
  /// and saves the verified archive record to SQLite.
  Future<StorageArchiveRecord> createAndVerifyArchive({
    required String archiveId,
    required String ruleApplied,
    required DateTime dateRangeStart,
    required DateTime dateRangeEnd,
    required List<Map<String, dynamic>> records,
  }) async {
    if (records.isEmpty) {
      throw ArgumentError('Cannot create an empty archive');
    }

    final payload = <String, dynamic>{
      'archiveId': archiveId,
      'createdAt': DateTime.now().toIso8601String(),
      'dateRangeStart': dateRangeStart.toIso8601String(),
      'dateRangeEnd': dateRangeEnd.toIso8601String(),
      'records': records,
    };

    final rawBytes = utf8.encode(jsonEncode(payload));
    final gzBytes = GZipEncoder().encode(rawBytes);
    if (gzBytes == null || gzBytes.isEmpty) {
      throw StateError('Failed to GZip-compress archive payload');
    }
    final b64 = base64Encode(gzBytes);
    final crcHex = getCrc32(rawBytes).toRadixString(16);

    // Verify before saving/returning
    final verifiedRecords = decodeAndVerifyPayload(
      compressedGzipBase64: b64,
      expectedCount: records.length,
    );
    if (verifiedRecords.length != records.length) {
      throw StateError('Archive verification mismatch');
    }

    final docIds = records
        .map((r) => '${r['collection'] ?? 'orders'}/${r['docId'] ?? ''}')
        .toList();

    final record = StorageArchiveRecord(
      archiveId: archiveId,
      ruleApplied: ruleApplied,
      dateRangeStart: dateRangeStart,
      dateRangeEnd: dateRangeEnd,
      recordCount: records.length,
      archivedDocIds: docIds,
      checksum: crcHex,
      compressedGzipBase64: b64,
      verified: true,
      createdAt: DateTime.now(),
    );

    final db = await _dbHelper.database;
    await db.insert(
      'storage_archives',
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return record;
  }

  List<Map<String, dynamic>> decodeAndVerifyPayload({
    required String compressedGzipBase64,
    int? expectedCount,
  }) {
    if (compressedGzipBase64.trim().isEmpty) {
      throw StateError('Empty archive payload');
    }
    final compressed = base64Decode(compressedGzipBase64);
    final raw = GZipDecoder().decodeBytes(compressed);
    final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final list = (decoded['records'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (expectedCount != null && list.length != expectedCount) {
      throw StateError(
        'Archive verification failed: expected $expectedCount records, got ${list.length}',
      );
    }
    return list;
  }

  Future<void> syncArchivesAndLogsFromCloud(String shopCode) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final db = await _dbHelper.database;

      final archSnaps = await firestore
          .collection('shops')
          .doc(shopCode)
          .collection('storage_archives')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      for (final doc in archSnaps.docs) {
        final rec = StorageArchiveRecord.fromMap({
          ...doc.data(),
          'archiveId': doc.id,
        });
        await db.insert(
          'storage_archives',
          rec.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final logSnaps = await firestore
          .collection('shops')
          .doc(shopCode)
          .collection('storage_audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      if (logSnaps.docs.isNotEmpty) {
        await db.delete('storage_audit_logs');
        for (final doc in logSnaps.docs) {
          final log = StorageAuditLog.fromMap(doc.data());
          await db.insert('storage_audit_logs', log.toDbMap());
        }
      }
    } catch (e) {
      debugPrint('[ArchiveService] Cloud sync skipped: $e');
    }
  }

  Future<List<StorageArchiveRecord>> listArchives() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'storage_archives',
      orderBy: 'created_at DESC',
    );
    return rows.map(StorageArchiveRecord.fromMap).toList();
  }

  Future<List<StorageAuditLog>> listAuditLogs() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'storage_audit_logs',
      orderBy: 'created_at DESC, id DESC',
      limit: 100,
    );
    return rows.map(StorageAuditLog.fromMap).toList();
  }

  Future<void> recordAuditLog(StorageAuditLog log) async {
    final db = await _dbHelper.database;
    await db.insert('storage_audit_logs', log.toDbMap());
  }

  /// Restores an archive's orders, items, options, payments, and delivery
  /// transactions into local SQLite and pushes them back to Firestore if connected.
  Future<int> restoreArchive(
    String archiveId, {
    bool syncToCloud = true,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'storage_archives',
      where: 'archive_id = ?',
      whereArgs: [archiveId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Archive "$archiveId" not found');
    }

    final archive = StorageArchiveRecord.fromMap(rows.first);
    final records = decodeAndVerifyPayload(
      compressedGzipBase64: archive.compressedGzipBase64,
      expectedCount: archive.recordCount,
    );

    final restoredOrderIds = <int>[];

    await db.transaction((txn) async {
      for (final rec in records) {
        final col = (rec['collection'] ?? 'orders').toString();
        final docId = (rec['docId'] ?? '').toString();
        final data = Map<String, dynamic>.from(rec['data'] as Map);

        if (col == 'orders') {
          final orderId = await _restoreOrder(txn, docId, data);
          if (orderId != null) restoredOrderIds.add(orderId);
        } else if (col == 'payments') {
          await _restorePayment(txn, docId, data);
        } else if (col == 'delivery_transactions') {
          await _restoreDeliveryTx(txn, docId, data);
        }
      }

      await txn.update(
        'storage_archives',
        {'restored_at': DateTime.now().toIso8601String()},
        where: 'archive_id = ?',
        whereArgs: [archiveId],
      );

      await txn.insert(
        'storage_audit_logs',
        StorageAuditLog(
          action: 'archive_restored',
          archiveId: archiveId,
          status: 'success',
          recordsArchived: records.length,
          message: 'Restored ${records.length} records from $archiveId',
          createdAt: DateTime.now(),
        ).toDbMap(),
      );
    });

    if (syncToCloud && ShopSyncService.instance.isConnected) {
      for (final oid in restoredOrderIds) {
        await ShopSyncService.instance.syncOrder(oid);
      }
    }

    return records.length;
  }

  Future<int?> _restoreOrder(
    DatabaseExecutor txn,
    String cloudOrderId,
    Map<String, dynamic> data,
  ) async {
    final existing = await txn.query(
      'orders',
      columns: ['id'],
      where: 'cloud_order_id = ?',
      whereArgs: [cloudOrderId],
      limit: 1,
    );

    int custId = (data['customer_id'] as num?)?.toInt() ?? 1;
    final phone = (data['customer_phone'] as String?)?.trim() ?? '';
    if (phone.isNotEmpty) {
      final matched = await _dbHelper.findCustomerIdByNormalizedPhone(txn, phone);
      if (matched != null) custId = matched;
    }

    int targetOrderId;
    if (existing.isNotEmpty) {
      targetOrderId = (existing.first['id'] as num).toInt();
    } else {
      targetOrderId = await txn.insert('orders', {
        'cloud_order_id': cloudOrderId,
        'order_number': (data['order_number'] as num?)?.toInt(),
        'customer_id': custId,
        'customer_name_snapshot':
            data['customer_name_snapshot'] ?? 'Restored Customer',
        'customer_phone': data['customer_phone'],
        'taken_by': data['taken_by'] ?? 'Store',
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
        'status': data['status'] ?? 'COMPLETED',
        'notes': data['notes'],
        'estimate_total': (data['estimate_total'] as num?)?.toDouble() ?? 0.0,
        'paid_amount': (data['paid_amount'] as num?)?.toDouble() ?? 0.0,
        'payment_mode': data['payment_mode'] ?? 'cash',
        'payment_status': data['payment_status'] ?? 'paid',
        'delivery_partner_name': data['delivery_partner_name'],
        'box_count': (data['box_count'] as num?)?.toInt() ?? 0,
      });

      final items = (data['items'] as List<dynamic>? ?? []);
      for (final rawItem in items) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final snap = item['product_snapshot'] as String? ??
            jsonEncode({
              'itemName': item['item_name'],
              'unitPrice': unitPrice,
              'options': item['options'] ?? {},
            });
        final itemId = await txn.insert('order_items', {
          'order_id': targetOrderId,
          'product_id': item['product_id'],
          'item_name': item['item_name'] ?? 'Item',
          'quantity_ordered':
              (item['quantity_ordered'] as num?)?.toDouble() ?? 0.0,
          'quantity_given': (item['quantity_given'] as num?)?.toDouble() ?? 0.0,
          'unit': item['unit'] ?? 'pcs',
          'unit_price': unitPrice,
          'status': item['status'] ?? 'GIVEN',
          'is_other_item': (item['is_other_item'] as num?)?.toInt() ?? 0,
          'procurement_status': item['procurement_status'] ?? 'NOT_REQUIRED',
          'details': item['details'],
          'notes': item['notes'],
          'product_snapshot': snap,
        });

        final opts = item['options'] as Map?;
        if (opts != null) {
          for (final entry in opts.entries) {
            await txn.insert('order_item_options', {
              'order_item_id': itemId,
              'option_name': entry.key.toString(),
              'option_value': entry.value.toString(),
            });
          }
        }
      }
    }
    return targetOrderId;
  }

  Future<void> _restorePayment(
    DatabaseExecutor txn,
    String cloudPaymentId,
    Map<String, dynamic> data,
  ) async {
    final existing = await txn.query(
      'customer_payments',
      columns: ['id'],
      where: 'cloud_payment_id = ?',
      whereArgs: [cloudPaymentId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    int custId = (data['customer_id'] as num?)?.toInt() ?? 1;
    final phone = (data['customer_phone'] as String?)?.trim() ?? '';
    if (phone.isNotEmpty) {
      final matched = await _dbHelper.findCustomerIdByNormalizedPhone(txn, phone);
      if (matched != null) custId = matched;
    }

    await txn.insert('customer_payments', {
      'cloud_payment_id': cloudPaymentId,
      'customer_id': custId,
      'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
      'payment_mode': data['payment_mode'] ?? 'cash',
      'notes': data['notes'],
      'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
    });
  }

  Future<void> _restoreDeliveryTx(
    DatabaseExecutor txn,
    String cloudTxId,
    Map<String, dynamic> data,
  ) async {
    final existing = await txn.query(
      'delivery_transactions',
      columns: ['id'],
      where: 'cloud_tx_id = ?',
      whereArgs: [cloudTxId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final pCloudId =
        ((data['pc'] ?? data['partner_cloud_id']) as String? ?? '').trim();
    final pName =
        ((data['pn'] ?? data['partner_name']) as String? ?? 'Partner').trim();
    int? partnerId;
    if (pCloudId.isNotEmpty) {
      final pRows = await txn.query(
        'delivery_partners',
        columns: ['id'],
        where: 'cloud_partner_id = ?',
        whereArgs: [pCloudId],
        limit: 1,
      );
      if (pRows.isNotEmpty) partnerId = (pRows.first['id'] as num).toInt();
    }
    partnerId ??= await txn.insert('delivery_partners', {
      'cloud_partner_id': pCloudId.isNotEmpty ? pCloudId : null,
      'name': pName.isNotEmpty ? pName : 'Partner',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    final createdRaw = data['c'] ?? data['created_at'];
    final createdIso = createdRaw is num
        ? DateTime.fromMillisecondsSinceEpoch(createdRaw.toInt())
            .toIso8601String()
        : (createdRaw?.toString() ?? DateTime.now().toIso8601String());

    await txn.insert('delivery_transactions', {
      'cloud_tx_id': cloudTxId,
      'partner_id': partnerId,
      'tx_type': _expandTxType(data['t'] ?? data['tx_type']),
      'location': data['l'] ?? data['location'],
      'total_boxes': ((data['bx'] ?? data['total_boxes']) as num?)?.toInt() ?? 0,
      'rate_breakdown_json': data['rt'] ?? data['rate_breakdown_json'],
      'earned_amount':
          ((data['e'] ?? data['earned_amount']) as num?)?.toDouble() ?? 0.0,
      'paid_amount':
          ((data['pa'] ?? data['paid_amount']) as num?)?.toDouble() ?? 0.0,
      'cut_amount':
          ((data['ca'] ?? data['cut_amount']) as num?)?.toDouble() ?? 0.0,
      'payment_mode': _expandPayMode(data['pm'] ?? data['payment_mode']),
      'description': data['ds'] ?? data['description'],
      'created_at': createdIso,
    });
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

  String _expandPayMode(dynamic raw) {
    final s = raw?.toString() ?? '';
    if (s == 'c' || s == 'cash') return 'cash';
    if (s == 'u' || s == 'upi') return 'upi';
    return 'none';
  }

  /// Exports a verified archive as a compressed `.json.gz` file and shares it.
  Future<String> exportArchiveFile(StorageArchiveRecord archive) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, '${archive.archiveId}.json.gz');
    final bytes = base64Decode(archive.compressedGzipBase64);
    await File(path).writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Shop Cloud Archive ${archive.archiveId} (${archive.recordCount} records)',
    );
    return path;
  }
}
