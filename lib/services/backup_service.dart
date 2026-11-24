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

      final targetPath = await _databaseHelper.getDatabaseFullPath();
      await _databaseHelper.close();

      // Clean up any existing WAL journal and shared-memory files from old database to avoid corruption
      try {
        final walFile = File('$targetPath-wal');
        if (await walFile.exists()) await walFile.delete();
        final shmFile = File('$targetPath-shm');
        if (await shmFile.exists()) await shmFile.delete();
      } catch (_) {}

      await backupFile.copy(targetPath);
      await _databaseHelper.reopen();
      return true;
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }
}
