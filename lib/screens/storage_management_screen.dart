import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shop/database/database_helper.dart';
import 'package:shop/l10n/app_localizations.dart';
import 'package:shop/services/archive_service.dart';
import 'package:shop/services/backup_service.dart';
import 'package:shop/services/shop_sync_service.dart';
import 'package:shop/services/storage_monitor_service.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  @override
  State<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen> {
  final StorageMonitorService _monitor = StorageMonitorService.instance;
  final ArchiveService _archiveService = ArchiveService();
  final DateFormat _dtFmt = DateFormat('dd MMM yyyy, hh:mm a');

  List<StorageArchiveRecord> _archives = [];
  List<StorageAuditLog> _auditLogs = [];
  bool _loadingLocal = true;
  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _monitor.addListener(_onMonitorChanged);
    _refreshAll();
  }

  @override
  void dispose() {
    _monitor.removeListener(_onMonitorChanged);
    super.dispose();
  }

  void _onMonitorChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshAll() async {
    setState(() => _loadingLocal = true);
    final shop = ShopSyncService.instance.currentShop;
    if (shop != null && ShopSyncService.instance.isConnected) {
      await _archiveService.syncArchivesAndLogsFromCloud(shop.shopCode);
    }
    final results = await Future.wait([
      _archiveService.listArchives(),
      _archiveService.listAuditLogs(),
    ]);
    if (!mounted) return;
    setState(() {
      _archives = results[0] as List<StorageArchiveRecord>;
      _auditLogs = results[1] as List<StorageAuditLog>;
      _loadingLocal = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    if (mb >= 10) return '${mb.toStringAsFixed(1)} MB';
    if (mb >= 0.1) return '${mb.toStringAsFixed(2)} MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB';
  }

  Future<void> _runStorageCheck() async {
    final shop = ShopSyncService.instance.currentShop;
    if (shop == null || !ShopSyncService.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cloud Sync is not connected. Connect Shop Sync to run a cloud storage check.',
          ),
        ),
      );
      return;
    }

    setState(() => _busyAction = true);
    try {
      final result = await _monitor.requestBackendStorageCheck(
        shopCode: shop.shopCode,
        deviceId: ShopSyncService.instance.currentUserOrDeviceName,
      );
      await _refreshAll();
      if (!mounted) return;
      final msg = result == 'already_running'
          ? 'A storage check/cleanup job is already running on the backend.'
          : result == 'error'
              ? 'Backend storage check reported an error. Check Cleanup History.'
              : 'Cloud storage check completed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not request storage check: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _downloadBackup() async {
    setState(() => _busyAction = true);
    try {
      final path = await BackupService(DatabaseHelper.instance)
          .createBackup(shareImmediately: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _showArchivedDataSheet({bool restoreMode = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    restoreMode
                        ? 'Restore Archived Data'
                        : 'Archived Data (${_archives.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _archives.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No archived batches yet. Automatic archiving runs when cloud storage reaches 90%.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _archives.length,
                      itemBuilder: (ctx, i) {
                        final arch = _archives[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      arch.verified
                                          ? Icons.verified_outlined
                                          : Icons.archive_outlined,
                                      size: 18,
                                      color: arch.verified
                                          ? Colors.teal
                                          : Colors.orange,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        arch.archiveId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${arch.recordCount} records',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.indigo.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Range: ${DateFormat('dd MMM yyyy').format(arch.dateRangeStart)} – ${DateFormat('dd MMM yyyy').format(arch.dateRangeEnd)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                Text(
                                  'Rule: ${arch.ruleApplied} • Created: ${_dtFmt.format(arch.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (arch.restoredAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Restored on ${_dtFmt.format(arch.restoredAt!)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _previewArchiveRecords(arch),
                                      icon: const Icon(Icons.visibility_outlined,
                                          size: 16),
                                      label: const Text('Inspect'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _archiveService.exportArchiveFile(arch),
                                      icon: const Icon(Icons.download_outlined,
                                          size: 16),
                                      label: const Text('Export'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _confirmAndRestore(arch);
                                      },
                                      icon: const Icon(Icons.restore_rounded,
                                          size: 16),
                                      label: const Text('Restore'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewArchiveRecords(StorageArchiveRecord arch) async {
    try {
      final records = _archiveService.decodeAndVerifyPayload(
        compressedGzipBase64: arch.compressedGzipBase64,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Archive Preview (${records.length})'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final rec = records[idx];
                final col = rec['collection'] ?? 'orders';
                final docId = rec['docId'] ?? '';
                final data = Map<String, dynamic>.from(rec['data'] as Map);
                final title = data['customer_name_snapshot'] ??
                    data['customer_name'] ??
                    data['pn'] ??
                    docId;
                return ListTile(
                  dense: true,
                  title: Text('$col • $title'),
                  subtitle: Text(
                    'ID: $docId • ${data['created_at'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read archive: $e')),
      );
    }
  }

  Future<void> _confirmAndRestore(StorageArchiveRecord arch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Archived Data?'),
        content: Text(
          'This will restore ${arch.recordCount} verified records from ${arch.archiveId} back into your local database and sync them to Firestore if online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore Now'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyAction = true);
    try {
      final restoredCount = await _archiveService.restoreArchive(arch.archiveId);
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully restored $restoredCount records.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _showCleanupHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cleanup Audit History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _auditLogs.isEmpty
                  ? const Center(
                      child: Text('No cleanup activity recorded yet.'),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _auditLogs.length,
                      itemBuilder: (ctx, i) {
                        final log = _auditLogs[i];
                        final isSuccess = log.status == 'success';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              isSuccess
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              color: isSuccess ? Colors.teal : Colors.orange,
                            ),
                            title: Text(
                              log.action.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (log.ruleApplied != null)
                                  'Rule: ${log.ruleApplied}',
                                if (log.recordsArchived > 0)
                                  'Records: ${log.recordsArchived}',
                                if (log.reclaimedBytes > 0)
                                  'Reclaimed: ${_formatBytes(log.reclaimedBytes)}',
                                if (log.message != null) log.message!,
                                _dtFmt.format(log.createdAt),
                              ].join(' • '),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final st = _monitor.status;
    final pct = (st?.utilizationPercent ?? 0.0).clamp(0.0, 100.0);
    final level = st?.statusLevel ?? StorageStatusLevel.normal;

    final Color statusColor;
    final Color statusBg;
    final String statusText;
    switch (level) {
      case StorageStatusLevel.full:
        statusColor = const Color(0xFFB91C1C);
        statusBg = const Color(0xFFFEE2E2);
        statusText = s.t('storageStatusFull');
        break;
      case StorageStatusLevel.critical:
        statusColor = const Color(0xFFEA580C);
        statusBg = const Color(0xFFFFEDD5);
        statusText = s.t('storageStatusCritical');
        break;
      case StorageStatusLevel.warning:
        statusColor = const Color(0xFFB45309);
        statusBg = const Color(0xFFFEF3C7);
        statusText = s.t('storageStatusWarning');
        break;
      case StorageStatusLevel.normal:
        statusColor = const Color(0xFF047857);
        statusBg = const Color(0xFFD1FAE5);
        statusText = s.t('storageStatusNormal');
        break;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          s.t('storageManagement'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: _loadingLocal
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  // 1. Cloud Database Storage Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.t('cloudDatabaseStorage'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${pct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: pct / 100.0,
                              minHeight: 12,
                              backgroundColor: Colors.grey.shade200,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (st == null)
                            Text(
                              'No cloud storage metrics synced yet. Tap "Run Storage Check" below to fetch actual Firestore usage.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            )
                          else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _MetricPill(
                                  label: s.t('usedLabel'),
                                  value: _formatBytes(st.usedBytes),
                                ),
                                _MetricPill(
                                  label: s.t('availableLabel'),
                                  value: _formatBytes(st.remainingBytes),
                                ),
                                _MetricPill(
                                  label: s.t('quotaLabel'),
                                  value: _formatBytes(st.quotaBytes),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    level == StorageStatusLevel.normal
                                        ? Icons.check_circle_outline
                                        : Icons.warning_amber_rounded,
                                    size: 18,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (st.insufficientEligibleData)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'No more eligible historical records remain to archive. Consider upgrading your Firebase storage plan.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Storage History Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('storageHistory'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _HistoryRow(
                            label: 'Last storage check',
                            value: st?.lastCheckAt != null
                                ? _dtFmt.format(st!.lastCheckAt!.toLocal())
                                : 'Not run yet',
                          ),
                          _HistoryRow(
                            label: 'Last successful archive',
                            value: st?.lastArchiveAt != null
                                ? _dtFmt.format(st!.lastArchiveAt!.toLocal())
                                : 'None',
                          ),
                          _HistoryRow(
                            label: 'Last cleanup date',
                            value: st?.lastCleanupAt != null
                                ? _dtFmt.format(st!.lastCleanupAt!.toLocal())
                                : 'None',
                          ),
                          _HistoryRow(
                            label: 'Archived records',
                            value: '${st?.archivedRecordCount ?? 0}',
                          ),
                          _HistoryRow(
                            label: 'Storage reclaimed',
                            value: _formatBytes(st?.lastReclaimedBytes ?? 0),
                          ),
                          _HistoryRow(
                            label: 'Next scheduled check',
                            value: st?.nextCheckAt != null
                                ? _dtFmt.format(st!.nextCheckAt!.toLocal())
                                : 'Every 6 hours',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Management Controls Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: _monitor.isChecking || _busyAction
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.radar_rounded,
                                  color: Colors.indigo.shade700),
                          title: Text(
                            s.t('runStorageCheck'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Request backend Cloud Monitoring check & threshold evaluation',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: (_monitor.isChecking || _busyAction)
                              ? null
                              : _runStorageCheck,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.inventory_2_outlined,
                              color: Colors.teal.shade700),
                          title: Text(
                            s.t('viewArchivedData'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_archives.length} archive batches available',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showArchivedDataSheet(restoreMode: false),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.restore_rounded,
                              color: Colors.blue.shade700),
                          title: Text(
                            s.t('restoreArchivedData'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Recover archived orders and settled transactions',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showArchivedDataSheet(restoreMode: true),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.history_edu_outlined,
                              color: Colors.amber.shade800),
                          title: Text(
                            s.t('viewCleanupHistory'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_auditLogs.length} audit log entries',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showCleanupHistorySheet,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.download_for_offline_outlined,
                              color: Colors.green.shade700),
                          title: Text(
                            s.t('downloadBackup'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Export full local database backup (.db)',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busyAction ? null : _downloadBackup,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
