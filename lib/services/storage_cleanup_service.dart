import 'package:shop/services/archive_service.dart';

class CleanupCandidateRecord {
  const CleanupCandidateRecord({
    required this.collection,
    required this.docId,
    required this.createdAt,
    required this.data,
    required this.estimatedCloudBytes,
  });

  final String collection;
  final String docId;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  final int estimatedCloudBytes;
}

class CleanupWindowSelection {
  const CleanupWindowSelection({
    required this.ruleApplied,
    this.windowStart,
    this.windowEnd,
    required this.selected,
  });

  final String ruleApplied;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final List<CleanupCandidateRecord> selected;
}

class CleanupCycleResult {
  const CleanupCycleResult({
    required this.skippedBecauseLocked,
    required this.warningTriggered,
    required this.cleanupExecuted,
    required this.insufficientEligibleData,
    required this.iterations,
    required this.totalArchivedCount,
    required this.finalUsedBytes,
    required this.finalUtilizationPercent,
    required this.archiveIds,
  });

  final bool skippedBecauseLocked;
  final bool warningTriggered;
  final bool cleanupExecuted;
  final bool insufficientEligibleData;
  final int iterations;
  final int totalArchivedCount;
  final int finalUsedBytes;
  final double finalUtilizationPercent;
  final List<String> archiveIds;
}

/// Abstract lock & cloud-storage adapter so both real Firestore backend jobs
/// and deterministic unit tests share the exact same Rules A/B/C and safety checks.
abstract class StorageCleanupTarget {
  Future<bool> tryAcquireLock(String jobId, DateTime now);
  Future<void> releaseLock(String jobId);
  Future<int> fetchActualCloudUsedBytes();
  Future<int> fetchCloudQuotaBytes();
  Future<List<CleanupCandidateRecord>> fetchAllOrders();
  Future<List<CleanupCandidateRecord>> fetchAllPayments();
  Future<List<CleanupCandidateRecord>> fetchAllDeliveryTransactions();
  Future<void> deleteCloudRecord(String collection, String docId);
  Future<void> writeAuditLog(StorageAuditLog log);
}

/// Implements the automatic storage cleanup policy (Rules A, B, C),
/// data protection filters, archive verification, and lock coordination.
class StorageCleanupService {
  StorageCleanupService({required ArchiveService archiveService})
      : _archiveService = archiveService;

  final ArchiveService _archiveService;

  static const double warningThresholdPct = 75.0;
  static const double cleanupThresholdPct = 90.0;

  /// Strictly enforces which orders are safe to archive & remove from Firestore.
  static bool isOrderEligible({
    required Map<String, dynamic> order,
    required Map<String, double> customerBalances,
    required DateTime now,
  }) {
    if (order['disputed'] == true) return false;

    final status = (order['status'] ?? '').toString().toUpperCase();
    if (status != 'COMPLETED' && status != 'CLOSED') return false;

    final payStatus = (order['payment_status'] ?? 'unpaid').toString().toLowerCase();
    if (payStatus == 'unpaid' || payStatus == 'partial') return false;

    final total = (order['estimate_total'] as num?)?.toDouble() ?? 0.0;
    final paid = (order['paid_amount'] as num?)?.toDouble() ?? 0.0;
    if (total - paid > 0.01) return false;

    final notes = (order['notes'] ?? '').toString().toLowerCase();
    if (notes.contains('dispute') || notes.contains('unresolved')) return false;

    final key = customerKeyFromMap(order);
    if (key != null && (customerBalances[key] ?? 0.0).abs() > 0.01) {
      return false;
    }

    final createdAt = _parseDate(order['created_at']);
    if (createdAt == null) return false;
    final ageDays = now.difference(createdAt).inDays;
    return ageDays >= 30;
  }

  static Map<String, double> computeCustomerBalances(
    List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> payments,
  ) {
    final map = <String, double>{};
    for (final o in orders) {
      final key = customerKeyFromMap(o);
      if (key == null) continue;
      final status = (o['status'] ?? '').toString().toUpperCase();
      final notes = (o['notes'] ?? '').toString();
      if (status == 'COMPLETED' ||
          status == 'CLOSED' ||
          status == 'PENDING' ||
          status == 'PARTIALLY COMPLETED' ||
          notes.contains('khata_debit')) {
        map[key] =
            (map[key] ?? 0.0) + ((o['estimate_total'] as num?)?.toDouble() ?? 0.0);
      }
    }
    for (final p in payments) {
      final key = customerKeyFromMap(p);
      if (key == null) continue;
      map[key] = (map[key] ?? 0.0) - ((p['amount'] as num?)?.toDouble() ?? 0.0);
    }
    return map;
  }

  static String? customerKeyFromMap(Map<String, dynamic> doc) {
    final rawPhone = (doc['customer_phone'] ?? '').toString();
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    if (digits.length >= 6) return 'p:$digits';

    if (doc['customer_id'] != null) return 'id:${doc['customer_id']}';
    final name =
        (doc['customer_name_snapshot'] ?? doc['customer_name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    return name.isEmpty ? null : 'n:$name';
  }

  /// Selects 1 month (Rule A: oldest < 365 days) or 3 months (Rule B: oldest >= 365 days).
  /// Never selects records within the most recent 30 days.
  static CleanupWindowSelection selectCleanupWindow(
    List<CleanupCandidateRecord> eligible,
    DateTime now,
  ) {
    if (eligible.isEmpty) {
      return const CleanupWindowSelection(
        ruleApplied: 'none',
        selected: [],
      );
    }

    final sorted = [...eligible]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final oldest = sorted.first.createdAt;
    final ageDays = now.difference(oldest).inDays;
    final recentCutoff = now.subtract(const Duration(days: 30));

    final months = ageDays >= 365 ? 3 : 1;
    final ruleApplied = ageDays >= 365 ? 'rule_b_3_months' : 'rule_a_1_month';

    final rawEnd = DateTime.utc(
      oldest.year,
      oldest.month + months,
      oldest.day,
      oldest.hour,
      oldest.minute,
      oldest.second,
    );
    final windowEnd = rawEnd.isBefore(recentCutoff) ? rawEnd : recentCutoff;
    final selected =
        sorted.where((r) => !r.createdAt.isAfter(windowEnd)).toList();

    return CleanupWindowSelection(
      ruleApplied: ruleApplied,
      windowStart: oldest,
      windowEnd: windowEnd,
      selected: selected,
    );
  }

  /// Runs a full locked, idempotent monitoring + cleanup cycle (Rule C loop).
  Future<CleanupCycleResult> executeCycle({
    required StorageCleanupTarget target,
    DateTime? nowOverride,
    String? jobIdOverride,
  }) async {
    final now = nowOverride ?? DateTime.now().toUtc();
    final jobId = jobIdOverride ?? 'job_${now.millisecondsSinceEpoch}';

    final acquired = await target.tryAcquireLock(jobId, now);
    if (!acquired) {
      return CleanupCycleResult(
        skippedBecauseLocked: true,
        warningTriggered: false,
        cleanupExecuted: false,
        insufficientEligibleData: false,
        iterations: 0,
        totalArchivedCount: 0,
        finalUsedBytes: 0,
        finalUtilizationPercent: 0,
        archiveIds: const [],
      );
    }

    try {
      final quota = await target.fetchCloudQuotaBytes();
      var used = await target.fetchActualCloudUsedBytes();
      var pct = quota > 0 ? (used / quota) * 100.0 : 0.0;

      final warningTriggered = pct >= warningThresholdPct;
      var iterations = 0;
      var totalArchived = 0;
      var insufficient = false;
      final archiveIds = <String>[];

      while (pct >= cleanupThresholdPct && iterations < 10) {
        iterations += 1;

        final orders = await target.fetchAllOrders();
        final payments = await target.fetchAllPayments();
        final deliveryTxs = await target.fetchAllDeliveryTransactions();

        final balances = computeCustomerBalances(
          orders.map((e) => e.data).toList(),
          payments.map((e) => e.data).toList(),
        );

        final eligible = <CleanupCandidateRecord>[];
        for (final o in orders) {
          if (isOrderEligible(
            order: o.data,
            customerBalances: balances,
            now: now,
          )) {
            eligible.add(o);
          }
        }
        for (final p in payments) {
          final key = customerKeyFromMap(p.data);
          final settled = key == null || (balances[key] ?? 0.0).abs() <= 0.01;
          if (settled && now.difference(p.createdAt).inDays >= 30) {
            eligible.add(p);
          }
        }
        // Only archive delivery transactions whose partner balance is settled
        final partnerBal = <String, double>{};
        for (final dtx in deliveryTxs) {
          final pid = (dtx.data['pc'] ??
                  dtx.data['partner_cloud_id'] ??
                  dtx.data['pn'] ??
                  '')
              .toString();
          if (pid.isEmpty) continue;
          final earned =
              ((dtx.data['e'] ?? dtx.data['earned_amount']) as num?)
                      ?.toDouble() ??
                  0.0;
          final paid =
              ((dtx.data['pa'] ?? dtx.data['paid_amount']) as num?)
                      ?.toDouble() ??
                  0.0;
          partnerBal[pid] = (partnerBal[pid] ?? 0.0) + (earned - paid);
        }
        for (final dtx in deliveryTxs) {
          final pid = (dtx.data['pc'] ??
                  dtx.data['partner_cloud_id'] ??
                  dtx.data['pn'] ??
                  '')
              .toString();
          final settled = pid.isEmpty || (partnerBal[pid] ?? 0.0).abs() <= 0.01;
          if (settled && now.difference(dtx.createdAt).inDays >= 30) {
            eligible.add(dtx);
          }
        }

        final selection = selectCleanupWindow(eligible, now);
        if (selection.selected.isEmpty) {
          insufficient = true;
          await target.writeAuditLog(
            StorageAuditLog(
              action: 'cleanup_stopped_insufficient_records',
              jobId: jobId,
              status: 'warning',
              bytesBefore: used,
              bytesAfter: used,
              message: 'No eligible historical records remain for archiving.',
              createdAt: now,
            ),
          );
          break;
        }

        final archiveId =
            'arch_${now.toIso8601String().substring(0, 10)}_${jobId}_$iterations';

        // 1. Create & verify archive BEFORE deleting any original records
        final archive = await _archiveService.createAndVerifyArchive(
          archiveId: archiveId,
          ruleApplied: selection.ruleApplied,
          dateRangeStart: selection.windowStart!,
          dateRangeEnd: selection.windowEnd!,
          records: selection.selected
              .map((r) => {
                    'collection': r.collection,
                    'docId': r.docId,
                    'data': r.data,
                  })
              .toList(),
        );
        archiveIds.add(archive.archiveId);

        // 2. Delete verified records from cloud
        for (final r in selection.selected) {
          await target.deleteCloudRecord(r.collection, r.docId);
        }

        totalArchived += selection.selected.length;
        final afterBytes = await target.fetchActualCloudUsedBytes();
        final reclaimed = used > afterBytes ? used - afterBytes : 0;

        await target.writeAuditLog(
          StorageAuditLog(
            action: 'archive_and_cleanup',
            jobId: jobId,
            archiveId: archive.archiveId,
            ruleApplied: selection.ruleApplied,
            status: 'success',
            recordsArchived: selection.selected.length,
            recordsDeleted: selection.selected.length,
            bytesBefore: used,
            bytesAfter: afterBytes,
            reclaimedBytes: reclaimed,
            createdAt: now,
          ),
        );

        used = afterBytes;
        pct = quota > 0 ? (used / quota) * 100.0 : 0.0;
        if (reclaimed == 0 && pct >= cleanupThresholdPct) break;
      }

      return CleanupCycleResult(
        skippedBecauseLocked: false,
        warningTriggered: warningTriggered,
        cleanupExecuted: totalArchived > 0,
        insufficientEligibleData: insufficient,
        iterations: iterations,
        totalArchivedCount: totalArchived,
        finalUsedBytes: used,
        finalUtilizationPercent: pct,
        archiveIds: archiveIds,
      );
    } finally {
      await target.releaseLock(jobId);
    }
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    if (raw is String && raw.trim().isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}
