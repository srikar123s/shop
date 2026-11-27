import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop/services/app_notification_service.dart';
import 'package:shop/services/top_notification_service.dart';

enum StorageStatusLevel { normal, warning, critical, full }

class CloudStorageStatus {
  const CloudStorageStatus({
    required this.quotaBytes,
    required this.usedBytes,
    required this.remainingBytes,
    required this.utilizationPercent,
    required this.statusLevel,
    this.metricSource = 'gcp_cloud_monitoring',
    this.lastCheckAt,
    this.nextCheckAt,
    this.lastArchiveAt,
    this.lastCleanupAt,
    this.archivedRecordCount = 0,
    this.lastReclaimedBytes = 0,
    this.insufficientEligibleData = false,
    this.lastNotifiedPercent = 0.0,
  });

  final int quotaBytes;
  final int usedBytes;
  final int remainingBytes;
  final double utilizationPercent;
  final StorageStatusLevel statusLevel;
  final String metricSource;
  final DateTime? lastCheckAt;
  final DateTime? nextCheckAt;
  final DateTime? lastArchiveAt;
  final DateTime? lastCleanupAt;
  final int archivedRecordCount;
  final int lastReclaimedBytes;
  final bool insufficientEligibleData;
  final double lastNotifiedPercent;

  double get usedMb => usedBytes / (1024 * 1024);
  double get remainingMb => remainingBytes / (1024 * 1024);
  double get quotaMb => quotaBytes / (1024 * 1024);

  bool get shouldShowDashboardWarning => utilizationPercent >= 75.0;
  bool get isCritical => utilizationPercent >= 90.0;

  static StorageStatusLevel classifyPercent(double pct) {
    if (pct >= 100.0) return StorageStatusLevel.full;
    if (pct >= 90.0) return StorageStatusLevel.critical;
    if (pct >= 75.0) return StorageStatusLevel.warning;
    return StorageStatusLevel.normal;
  }

  factory CloudStorageStatus.fromMap(Map<String, dynamic> map) {
    final quota = (map['quotaBytes'] as num?)?.toInt() ?? (1024 * 1024 * 1024);
    final used = (map['usedBytes'] as num?)?.toInt() ?? 0;
    final remaining =
        (map['remainingBytes'] as num?)?.toInt() ?? max(0, quota - used);
    final pct = (map['utilizationPercent'] as num?)?.toDouble() ??
        (quota > 0 ? (used / quota) * 100.0 : 0.0);

    return CloudStorageStatus(
      quotaBytes: quota,
      usedBytes: used,
      remainingBytes: remaining,
      utilizationPercent: pct,
      statusLevel: classifyPercent(pct),
      metricSource: (map['metricSource'] as String?) ?? 'gcp_cloud_monitoring',
      lastCheckAt: _parseDt(map['lastCheckAt']),
      nextCheckAt: _parseDt(map['nextCheckAt']),
      lastArchiveAt: _parseDt(map['lastArchiveAt']),
      lastCleanupAt: _parseDt(map['lastCleanupAt']),
      archivedRecordCount: (map['archivedRecordCount'] as num?)?.toInt() ?? 0,
      lastReclaimedBytes: (map['lastReclaimedBytes'] as num?)?.toInt() ?? 0,
      insufficientEligibleData: map['insufficientEligibleData'] == true,
      lastNotifiedPercent:
          (map['lastNotifiedPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'quotaBytes': quotaBytes,
        'usedBytes': usedBytes,
        'remainingBytes': remainingBytes,
        'utilizationPercent': utilizationPercent,
        'statusLevel': statusLevel.name,
        'metricSource': metricSource,
        'lastCheckAt': lastCheckAt?.toIso8601String(),
        'nextCheckAt': nextCheckAt?.toIso8601String(),
        'lastArchiveAt': lastArchiveAt?.toIso8601String(),
        'lastCleanupAt': lastCleanupAt?.toIso8601String(),
        'archivedRecordCount': archivedRecordCount,
        'lastReclaimedBytes': lastReclaimedBytes,
        'insufficientEligibleData': insufficientEligibleData,
        'lastNotifiedPercent': lastNotifiedPercent,
      };

  static DateTime? _parseDt(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    if (raw is Timestamp) return raw.toDate();
    return null;
  }
}

/// Monitors cloud Firestore storage status reported by the trusted backend
/// Cloud Function (Cloud Monitoring / Billing metrics). Never uses SQLite size
/// as cloud storage and never stores service account credentials on device.
class StorageMonitorService extends ChangeNotifier {
  StorageMonitorService._();

  static final StorageMonitorService instance = StorageMonitorService._();

  static const String _cacheKey = 'cloud_storage_status_cache_v1';
  static const String _notifiedPctKey = 'cloud_storage_notified_pct_v1';
  static const double warningThresholdPct = 75.0;
  static const double criticalThresholdPct = 90.0;
  static const double significantGrowthPct = 5.0;

  static const String storageAlmostFullMessage =
      'Storage Almost Full! Your cloud database has reached 90% capacity. Automatic storage management will now identify eligible old records for archiving and cleanup. Please review your backup status.';

  CloudStorageStatus? _status;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  bool _isChecking = false;
  double _lastLocallyNotifiedPct = 0.0;
  String? _activeShopCode;

  CloudStorageStatus? get status => _status;
  bool get isChecking => _isChecking;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastLocallyNotifiedPct = prefs.getDouble(_notifiedPctKey) ?? 0.0;
      final cachedRaw = prefs.getString(_cacheKey);
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final map = jsonDecode(cachedRaw) as Map<String, dynamic>;
        _status = CloudStorageStatus.fromMap(map);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[StorageMonitorService] Error loading cache: $e');
    }
  }

  void startListening(String shopCode) {
    if (_activeShopCode == shopCode && _statusSub != null) return;
    stopListening();
    _activeShopCode = shopCode;

    try {
      _statusSub = FirebaseFirestore.instance
          .collection('shops')
          .doc(shopCode)
          .collection('system')
          .doc('storage_status')
          .snapshots()
          .listen((snap) async {
        if (!snap.exists || snap.data() == null) return;
        final next = CloudStorageStatus.fromMap(snap.data()!);
        await applyStatusSnapshot(next, notifyUi: true);
      }, onError: (Object err) {
        debugPrint('[StorageMonitorService] Listener error: $err');
      });
    } catch (e) {
      debugPrint('[StorageMonitorService] Could not start listener: $e');
    }
  }

  void stopListening() {
    _statusSub?.cancel();
    _statusSub = null;
    _activeShopCode = null;
  }

  /// Evaluates threshold crossing and updates cached status.
  /// Returns true if a new warning notification was triggered.
  Future<bool> applyStatusSnapshot(
    CloudStorageStatus next, {
    bool notifyUi = false,
  }) async {
    final prevPct = _status?.utilizationPercent ?? 0.0;
    _status = next;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(next.toMap()));
    } catch (_) {}

    final crossedCritical = next.utilizationPercent >= criticalThresholdPct &&
        prevPct < criticalThresholdPct &&
        _lastLocallyNotifiedPct < criticalThresholdPct;

    final significantGrowthAfterCleanup =
        next.utilizationPercent >= criticalThresholdPct &&
            _lastLocallyNotifiedPct >= criticalThresholdPct &&
            (next.utilizationPercent - _lastLocallyNotifiedPct) >=
                significantGrowthPct;

    bool triggeredNotification = false;

    if (crossedCritical || significantGrowthAfterCleanup) {
      triggeredNotification = true;
      _lastLocallyNotifiedPct = next.utilizationPercent;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_notifiedPctKey, _lastLocallyNotifiedPct);
      } catch (_) {}

      if (notifyUi) {
        TopNotificationService.showTopNotification(
          message: storageAlmostFullMessage,
          duration: const Duration(seconds: 6),
        );
        unawaited(
          AppNotificationService.instance
              .showLiveOrderNotification(
                title: '⚠️ Storage Almost Full (${next.utilizationPercent.toStringAsFixed(0)}%)',
                body: storageAlmostFullMessage,
              )
              .catchError((_) {}),
        );
      }
    } else if (next.utilizationPercent < criticalThresholdPct &&
        _lastLocallyNotifiedPct != 0.0) {
      _lastLocallyNotifiedPct = 0.0;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_notifiedPctKey, 0.0);
      } catch (_) {}
    }

    notifyListeners();
    return triggeredNotification;
  }

  /// Requests the trusted backend Cloud Function to run a storage check now.
  Future<String> requestBackendStorageCheck({
    required String shopCode,
    required String deviceId,
  }) async {
    if (_isChecking) return 'already_checking';
    _isChecking = true;
    notifyListeners();

    try {
      final reqRef = FirebaseFirestore.instance
          .collection('shops')
          .doc(shopCode)
          .collection('system')
          .doc('storage_check_request');

      final requestId = DateTime.now().millisecondsSinceEpoch.toString();
      await reqRef.set({
        'status': 'requested',
        'requestId': requestId,
        'requestedByDevice': deviceId,
        'requestedAt': DateTime.now().toIso8601String(),
      });

      // Wait briefly for Cloud Function completion (up to 12 seconds)
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final snap = await reqRef.get();
        final data = snap.data();
        final st = data?['status'] as String?;
        if (st == 'completed' || st == 'already_running' || st == 'error') {
          return st ?? 'completed';
        }
      }
      return 'queued';
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
}
