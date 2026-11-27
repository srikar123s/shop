import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/services/archive_service.dart';
import 'package:shop/services/storage_cleanup_service.dart';
import 'package:shop/services/storage_monitor_service.dart';

class _InMemoryArchiveService extends ArchiveService {
  final Map<String, StorageArchiveRecord> store = {};
  final List<StorageAuditLog> logs = [];
  bool failNextArchive = false;

  @override
  Future<StorageArchiveRecord> createAndVerifyArchive({
    required String archiveId,
    required String ruleApplied,
    required DateTime dateRangeStart,
    required DateTime dateRangeEnd,
    required List<Map<String, dynamic>> records,
  }) async {
    if (failNextArchive) {
      throw StateError('Simulated archive write/verification failure');
    }
    // Use real GZip encoding & verification from ArchiveService without needing sqflite platform channel
    final payload = {
      'archiveId': archiveId,
      'createdAt': DateTime.now().toIso8601String(),
      'dateRangeStart': dateRangeStart.toIso8601String(),
      'dateRangeEnd': dateRangeEnd.toIso8601String(),
      'records': records,
    };
    final raw = utf8.encode(jsonEncode(payload));
    // Re-use real decodeAndVerifyPayload via real encoder
    final rec = await _encodeOnly(
      archiveId: archiveId,
      ruleApplied: ruleApplied,
      dateRangeStart: dateRangeStart,
      dateRangeEnd: dateRangeEnd,
      records: records,
      rawBytes: raw,
    );
    store[archiveId] = rec;
    return rec;
  }

  Future<StorageArchiveRecord> _encodeOnly({
    required String archiveId,
    required String ruleApplied,
    required DateTime dateRangeStart,
    required DateTime dateRangeEnd,
    required List<Map<String, dynamic>> records,
    required List<int> rawBytes,
  }) async {
    final gz = gzip.encode(rawBytes);
    final b64 = base64Encode(gz);
    final verified = decodeAndVerifyPayload(
      compressedGzipBase64: b64,
      expectedCount: records.length,
    );
    expect(verified.length, records.length);

    return StorageArchiveRecord(
      archiveId: archiveId,
      ruleApplied: ruleApplied,
      dateRangeStart: dateRangeStart,
      dateRangeEnd: dateRangeEnd,
      recordCount: records.length,
      archivedDocIds:
          records.map((r) => '${r['collection']}/${r['docId']}').toList(),
      checksum: 'crc_ok',
      compressedGzipBase64: b64,
      verified: true,
      createdAt: DateTime.now(),
    );
  }
}

class _FakeCloudTarget implements StorageCleanupTarget {
  _FakeCloudTarget({
    required this.quotaBytes,
    required this.baseOverheadBytes,
    List<CleanupCandidateRecord>? orders,
    List<CleanupCandidateRecord>? payments,
    List<CleanupCandidateRecord>? deliveryTxs,
  })  : orders = orders ?? [],
        payments = payments ?? [],
        deliveryTxs = deliveryTxs ?? [];

  final int quotaBytes;
  final int baseOverheadBytes;
  final List<CleanupCandidateRecord> orders;
  final List<CleanupCandidateRecord> payments;
  final List<CleanupCandidateRecord> deliveryTxs;
  final List<StorageAuditLog> auditLogs = [];

  bool locked = false;
  String? lockOwner;
  DateTime? lockExpiresAt;
  bool simulateDropAfterOneDelete = false;
  int deleteCount = 0;

  @override
  Future<bool> tryAcquireLock(String jobId, DateTime now) async {
    if (locked && lockExpiresAt != null && lockExpiresAt!.isAfter(now)) {
      return false;
    }
    locked = true;
    lockOwner = jobId;
    lockExpiresAt = now.add(const Duration(minutes: 10));
    return true;
  }

  @override
  Future<void> releaseLock(String jobId) async {
    if (lockOwner == jobId) {
      locked = false;
      lockOwner = null;
      lockExpiresAt = null;
    }
  }

  @override
  Future<int> fetchCloudQuotaBytes() async => quotaBytes;

  @override
  Future<int> fetchActualCloudUsedBytes() async {
    int sum = baseOverheadBytes;
    for (final o in orders) {
      sum += o.estimatedCloudBytes;
    }
    for (final p in payments) {
      sum += p.estimatedCloudBytes;
    }
    for (final d in deliveryTxs) {
      sum += d.estimatedCloudBytes;
    }
    return sum;
  }

  @override
  Future<List<CleanupCandidateRecord>> fetchAllOrders() async => List.of(orders);

  @override
  Future<List<CleanupCandidateRecord>> fetchAllPayments() async =>
      List.of(payments);

  @override
  Future<List<CleanupCandidateRecord>> fetchAllDeliveryTransactions() async =>
      List.of(deliveryTxs);

  @override
  Future<void> deleteCloudRecord(String collection, String docId) async {
    if (simulateDropAfterOneDelete && deleteCount >= 1) {
      throw StateError('Simulated internet interruption mid-cleanup');
    }
    deleteCount += 1;
    if (collection == 'orders') {
      orders.removeWhere((e) => e.docId == docId);
    } else if (collection == 'payments') {
      payments.removeWhere((e) => e.docId == docId);
    } else if (collection == 'delivery_transactions') {
      deliveryTxs.removeWhere((e) => e.docId == docId);
    }
  }

  @override
  Future<void> writeAuditLog(StorageAuditLog log) async {
    auditLogs.add(log);
  }
}

CleanupCandidateRecord _makeSettledOrder({
  required String id,
  required DateTime createdAt,
  int bytes = 100,
  String custPhone = '9876543210',
  double total = 500.0,
  double paid = 500.0,
  String status = 'COMPLETED',
  String payStatus = 'paid',
  bool disputed = false,
}) {
  return CleanupCandidateRecord(
    collection: 'orders',
    docId: id,
    createdAt: createdAt,
    estimatedCloudBytes: bytes,
    data: {
      'id': id,
      'order_number': 101,
      'customer_id': 1,
      'customer_name_snapshot': 'Ravi Kirana',
      'customer_phone': custPhone,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'payment_status': payStatus,
      'estimate_total': total,
      'paid_amount': paid,
      'disputed': disputed,
      'items': [
        {
          'item_name': 'Nails 2in',
          'quantity_ordered': 5.0,
          'quantity_given': 5.0,
          'unit': 'kg',
          'unit_price': 100.0,
          'options': {'Size': '2 inch'},
        }
      ],
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Storage Management & Automatic Cleanup Policy (11 Scenarios)', () {
    final now = DateTime.utc(2026, 11, 28);
    const quota = 1000;

    test('1. Storage at 70% — no warning or cleanup', () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 600,
        orders: [
          _makeSettledOrder(
            id: 'ord_1',
            createdAt: now.subtract(const Duration(days: 200)),
            bytes: 100,
          ),
        ],
      );

      final monitor = StorageMonitorService.instance;
      final notified = await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({
          'quotaBytes': quota,
          'usedBytes': 700,
        }),
      );
      expect(notified, isFalse);
      expect(monitor.status!.statusLevel, StorageStatusLevel.normal);
      expect(monitor.status!.shouldShowDashboardWarning, isFalse);

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.warningTriggered, isFalse);
      expect(result.cleanupExecuted, isFalse);
      expect(target.orders.length, 1);
    });

    test('2. Storage at 85% — warning only, no cleanup', () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 750,
        orders: [
          _makeSettledOrder(
            id: 'ord_1',
            createdAt: now.subtract(const Duration(days: 200)),
            bytes: 100,
          ),
        ],
      );

      final monitor = StorageMonitorService.instance;
      await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({'quotaBytes': quota, 'usedBytes': 850}),
      );
      expect(monitor.status!.statusLevel, StorageStatusLevel.warning);
      expect(monitor.status!.shouldShowDashboardWarning, isTrue);
      expect(monitor.status!.isCritical, isFalse);

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.warningTriggered, isTrue);
      expect(result.cleanupExecuted, isFalse);
      expect(target.orders.length, 1);
    });

    test('3. Storage reaches 90% — notification once on crossing & cleanup starts',
        () async {
      final monitor = StorageMonitorService.instance;
      await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({'quotaBytes': quota, 'usedBytes': 700}),
      );
      final firstAlert = await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({'quotaBytes': quota, 'usedBytes': 910}),
      );
      expect(firstAlert, isTrue);
      expect(monitor.status!.isCritical, isTrue);

      // Repeat check at 92% (<5% growth) should not re-notify
      final repeatAlert = await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({'quotaBytes': quota, 'usedBytes': 920}),
      );
      expect(repeatAlert, isFalse);

      // Significant growth (>= 5%) after previous alert triggers another warning
      final growthAlert = await monitor.applyStatusSnapshot(
        CloudStorageStatus.fromMap({'quotaBytes': quota, 'usedBytes': 970}),
      );
      expect(growthAlert, isTrue);
    });

    test('4. Oldest eligible data < 1 year old — archives 1 month only', () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 600,
        orders: [
          // 180 days ago (< 1 year)
          _makeSettledOrder(
            id: 'ord_m1',
            createdAt: DateTime.utc(2026, 6, 1),
            bytes: 150,
          ),
          // 120 days ago (outside 1-month window from June 1)
          _makeSettledOrder(
            id: 'ord_m3',
            createdAt: DateTime.utc(2026, 8, 1),
            bytes: 150,
          ),
          // Recent (10 days ago) — must never be touched
          _makeSettledOrder(
            id: 'ord_recent',
            createdAt: now.subtract(const Duration(days: 10)),
            bytes: 50,
          ),
        ],
        payments: [
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_settled',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876543210',
              'amount': 1500.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
        ],
      );

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.cleanupExecuted, isTrue);
      expect(result.totalArchivedCount, 1);
      expect(archiveSvc.store.values.first.ruleApplied, 'rule_a_1_month');
      expect(target.orders.map((o) => o.docId), containsAll(['ord_m3', 'ord_recent']));
      expect(target.orders.map((o) => o.docId), isNot(contains('ord_m1')));
    });

    test('5. Oldest eligible data >= 1 year old — archives 3 months', () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 600,
        orders: [
          _makeSettledOrder(
            id: 'ord_old_1',
            createdAt: DateTime.utc(2025, 1, 10),
            bytes: 100,
          ),
          _makeSettledOrder(
            id: 'ord_old_2',
            createdAt: DateTime.utc(2025, 3, 20),
            bytes: 100,
          ),
          _makeSettledOrder(
            id: 'ord_newer',
            createdAt: DateTime.utc(2025, 6, 1),
            bytes: 150,
          ),
        ],
        payments: [
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_settled',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876543210',
              'amount': 1500.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
        ],
      );

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.cleanupExecuted, isTrue);
      expect(result.totalArchivedCount, 2);
      expect(archiveSvc.store.values.first.ruleApplied, 'rule_b_3_months');
      expect(target.orders.map((o) => o.docId), ['ord_newer']);
    });

    test('6. Storage remains >= 90% after 1st batch — Rule C repeats until < 90%',
        () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 850,
        orders: [
          _makeSettledOrder(
            id: 'ord_jan',
            createdAt: DateTime.utc(2026, 2, 1),
            custPhone: '9876543210',
            bytes: 100,
          ),
          _makeSettledOrder(
            id: 'ord_apr',
            createdAt: DateTime.utc(2026, 4, 15),
            custPhone: '9876500000',
            bytes: 100,
          ),
        ],
        payments: [
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_jan',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876543210',
              'amount': 500.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_apr',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876500000',
              'amount': 500.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
        ],
      );

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.iterations, 2);
      expect(result.totalArchivedCount, 2);
      expect(result.finalUtilizationPercent, lessThan(90.0));
    });

    test(
        '7. No eligible records (unpaid, Khata due, disputed, recent) — stops safely',
        () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 600,
        orders: [
          // Unpaid order
          _makeSettledOrder(
            id: 'ord_unpaid',
            createdAt: DateTime.utc(2025, 1, 1),
            bytes: 100,
            paid: 100,
            total: 500,
            payStatus: 'partial',
          ),
          // Disputed order
          _makeSettledOrder(
            id: 'ord_dispute',
            createdAt: DateTime.utc(2025, 2, 1),
            bytes: 100,
            disputed: true,
          ),
          // Recent order (< 30 days)
          _makeSettledOrder(
            id: 'ord_recent',
            createdAt: now.subtract(const Duration(days: 5)),
            bytes: 150,
          ),
        ],
      );

      final result = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now,
      );
      expect(result.cleanupExecuted, isFalse);
      expect(result.insufficientEligibleData, isTrue);
      expect(target.orders.length, 3);
    });

    test('8. Archive failure — never deletes original cloud records', () async {
      final archiveSvc = _InMemoryArchiveService()..failNextArchive = true;
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 800,
        orders: [
          _makeSettledOrder(
            id: 'ord_1',
            createdAt: DateTime.utc(2025, 1, 1),
            bytes: 150,
          ),
        ],
        payments: [
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_settled',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876543210',
              'amount': 500.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
        ],
      );

      await expectLater(
        () => cleanupSvc.executeCycle(target: target, nowOverride: now),
        throwsStateError,
      );
      expect(target.orders.length, 1);
      expect(target.locked, isFalse);
    });

    test('9. Internet interruption — lock recovers after lease & resumes safely',
        () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 850,
        orders: [
          _makeSettledOrder(
            id: 'ord_1',
            createdAt: DateTime.utc(2025, 1, 1),
            bytes: 100,
          ),
          _makeSettledOrder(
            id: 'ord_2',
            createdAt: DateTime.utc(2025, 2, 1),
            bytes: 100,
          ),
        ],
        payments: [
          CleanupCandidateRecord(
            collection: 'payments',
            docId: 'pay_settled',
            createdAt: now.subtract(const Duration(days: 5)),
            estimatedCloudBytes: 0,
            data: {
              'customer_phone': '9876543210',
              'amount': 1000.0,
              'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
            },
          ),
        ],
      )..simulateDropAfterOneDelete = true;

      await expectLater(
        () => cleanupSvc.executeCycle(target: target, nowOverride: now),
        throwsStateError,
      );
      // Archive was already saved and 1st doc deleted; 2nd doc still exists
      expect(target.orders.map((o) => o.docId), ['ord_2']);
      expect(target.locked, isFalse);

      // Network comes back — adjust remaining payment to match ord_2 (500) and resume
      target.payments[0] = CleanupCandidateRecord(
        collection: 'payments',
        docId: 'pay_settled',
        createdAt: now.subtract(const Duration(days: 5)),
        estimatedCloudBytes: 0,
        data: {
          'customer_phone': '9876543210',
          'amount': 500.0,
          'created_at': now.subtract(const Duration(days: 5)).toIso8601String(),
        },
      );
      target.simulateDropAfterOneDelete = false;
      final resumed = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now.add(const Duration(minutes: 1)),
      );
      expect(resumed.cleanupExecuted, isTrue);
      expect(target.orders, isEmpty);
      expect(resumed.finalUtilizationPercent, lessThan(90.0));
    });

    test('10. Multiple connected devices — only one cleanup job runs', () async {
      final archiveSvc = _InMemoryArchiveService();
      final cleanupSvc = StorageCleanupService(archiveService: archiveSvc);
      final target = _FakeCloudTarget(
        quotaBytes: quota,
        baseOverheadBytes: 800,
        orders: [
          _makeSettledOrder(
            id: 'ord_1',
            createdAt: DateTime.utc(2025, 1, 1),
            bytes: 150,
          ),
        ],
      );

      // Simulate Device A holding an active unexpired lock
      await target.tryAcquireLock('device_A', now);

      // Device B tries to start cleanup at the same time
      final deviceBResult = await cleanupSvc.executeCycle(
        target: target,
        nowOverride: now.add(const Duration(seconds: 5)),
        jobIdOverride: 'device_B',
      );
      expect(deviceBResult.skippedBecauseLocked, isTrue);
      expect(target.orders.length, 1);
    });

    test('11. Restore an archived order & related payment from gzip archive',
        () async {
      final archiveSvc = _InMemoryArchiveService();
      final orderRec = _makeSettledOrder(
        id: 'ord_restore_1',
        createdAt: DateTime.utc(2025, 1, 15),
        bytes: 120,
      );
      final paymentRec = CleanupCandidateRecord(
        collection: 'payments',
        docId: 'pay_restore_1',
        createdAt: DateTime.utc(2025, 1, 16),
        estimatedCloudBytes: 80,
        data: {
          'customer_id': 1,
          'customer_phone': '9876543210',
          'amount': 500.0,
          'payment_mode': 'cash',
          'created_at': DateTime.utc(2025, 1, 16).toIso8601String(),
        },
      );

      final arch = await archiveSvc.createAndVerifyArchive(
        archiveId: 'arch_restore_test',
        ruleApplied: 'rule_b_3_months',
        dateRangeStart: DateTime.utc(2025, 1, 1),
        dateRangeEnd: DateTime.utc(2025, 4, 1),
        records: [
          {
            'collection': orderRec.collection,
            'docId': orderRec.docId,
            'data': orderRec.data,
          },
          {
            'collection': paymentRec.collection,
            'docId': paymentRec.docId,
            'data': paymentRec.data,
          },
        ],
      );

      final restored = archiveSvc.decodeAndVerifyPayload(
        compressedGzipBase64: arch.compressedGzipBase64,
        expectedCount: 2,
      );
      expect(restored.length, 2);
      expect(restored[0]['docId'], 'ord_restore_1');
      expect(restored[0]['data']['items'][0]['item_name'], 'Nails 2in');
      expect(restored[1]['docId'], 'pay_restore_1');
      expect(restored[1]['data']['amount'], 500.0);
    });
  });
}
