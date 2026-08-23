import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shop/database/database_helper.dart';

class BackupService {
  const BackupService(this._databaseHelper);

  final DatabaseHelper _databaseHelper;

  Future<String> createBackup() async {
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
    return backupPath;
  }

  Future<bool> restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: <String>['db'],
    );
    if (picked == null || picked.files.single.path == null) {
      return false;
    }

    final backupPath = picked.files.single.path!;
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('Selected backup file does not exist.');
    }

    final targetPath = await _databaseHelper.getDatabaseFullPath();
    await _databaseHelper.close();
    await backupFile.copy(targetPath);
    await _databaseHelper.reopen();
    return true;
  }
}
