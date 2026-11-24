import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shop/database/database_helper.dart';

class BackupService {
  const BackupService(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<String> createBackup({bool shareImmediately = false}) async {
    // 1. Force WAL checkpoint to ensure all uncommitted journal transactions are written to main DB file
    try {
      final db = await _databaseHelper.database;
      await db.rawQuery('PRAGMA wal_checkpoint(FULL);');
    } catch (_) {}

    final sourcePath = await _databaseHelper.getDatabaseFullPath();
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Database not found for backup.');
    }
    final directory = await getApplicationDocumentsDirectory();
    final backupName =
        'hardware_shop_backup_${DateTime.now().millisecondsSinceEpoch}.db';
    final backupPath = p.join(directory.path, backupName);
    await source.copy(backupPath);

    if (shareImmediately) {
      await Share.shareXFiles(
        [XFile(backupPath)],
        text: 'Shop Database Backup ($backupName)',
      );
    }
    return backupPath;
  }

  Future<bool> restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: <String>['db'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return false;
    }

    final singleFile = picked.files.single;
    String? backupPath = singleFile.path;
    File? tempFile;

    if (backupPath == null && singleFile.bytes != null) {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(p.join(tempDir.path, 'restored_temp_${DateTime.now().millisecondsSinceEpoch}.db'));
      await tempFile.writeAsBytes(singleFile.bytes!);
      backupPath = tempFile.path;
    }

    if (backupPath == null) {
      return false;
    }

    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        throw Exception('Selected backup file does not exist.');
      }

      // 1. Validate SQLite header magic bytes (first 16 bytes must match "SQLite format 3\000")
      final backupLength = await backupFile.length();
      if (backupLength < 100) {
        throw Exception('Selected backup file is invalid or too small to be a database.');
      }
      final headerBytes = await backupFile.openRead(0, 16).first;
      const expectedHeader = [83, 113, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
      if (headerBytes.length < 16 || !headerBytes.take(16).toList().asMap().entries.every((e) => e.value == expectedHeader[e.key])) {
        throw Exception('Selected file is not a valid SQLite database.');
      }

      final targetPath = await _databaseHelper.getDatabaseFullPath();
      final targetFile = File(targetPath);
      final safetyBakPath = '$targetPath.safety_bak';
      final safetyWalPath = '$targetPath-wal.safety_bak';

      // 2. Create safety backup of active database before touching it
      if (await targetFile.exists()) {
        await targetFile.copy(safetyBakPath);
        final liveWal = File('$targetPath-wal');
        if (await liveWal.exists()) {
          await liveWal.copy(safetyWalPath);
        }
      }

      await _databaseHelper.close();

      try {
        // Clean up any existing WAL journal and shared-memory files from old database to avoid corruption
        try {
          final walFile = File('$targetPath-wal');
          if (await walFile.exists()) await walFile.delete();
          final shmFile = File('$targetPath-shm');
          if (await shmFile.exists()) await shmFile.delete();
        } catch (_) {}

        await backupFile.copy(targetPath);
        await _databaseHelper.reopen();

        // Remove safety backup on successful restore
        final safetyBak = File(safetyBakPath);
        if (await safetyBak.exists()) await safetyBak.delete();
        final safetyWal = File(safetyWalPath);
        if (await safetyWal.exists()) await safetyWal.delete();

        return true;
      } catch (restoreError) {
        // Rollback to safety backup if copy or reopen fails
        final safetyBak = File(safetyBakPath);
        if (await safetyBak.exists()) {
          await safetyBak.copy(targetPath);
          await safetyBak.delete();
        }
        final safetyWal = File(safetyWalPath);
        if (await safetyWal.exists()) {
          await safetyWal.copy('$targetPath-wal');
          await safetyWal.delete();
        }
        await _databaseHelper.reopen();
        rethrow;
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }
}
