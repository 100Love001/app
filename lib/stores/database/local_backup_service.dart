import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'add_database.dart';
import 'database_backup_service.dart';

/// 一条本地备份。F1 起备份为单个 .enc 加密文件；
/// [folderPath] 仅用于兼容旧版“文件夹包”备份。
class LocalBackupInfo {
  LocalBackupInfo({
    required this.exportTime,
    required this.formatVersion,
    this.filePath = '',
    this.folderPath = '',
    this.name = '',
    this.deviceCode = '????',
    this.deviceName = '未知设备',
    this.legacyFolder = false,
    this.autoBackup = false,
  });

  /// 单文件模式：加密文件绝对路径。
  final String filePath;

  /// 旧版文件夹包模式：文件夹绝对路径。
  final String folderPath;

  /// 用户命名（来自文件名/旧 sidecar）。
  final String name;
  final String deviceCode;
  final DateTime exportTime;
  final String deviceName;
  final int formatVersion;
  final bool legacyFolder;
  final bool autoBackup;

  /// 恢复/分享时实际使用的 .enc 文件路径。
  String get dataFileName {
    if (filePath.isNotEmpty) return filePath;
    if (folderPath.isEmpty) return '';
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return '';
    for (final file in dir.listSync().whereType<File>()) {
      if (file.path.endsWith('.enc')) return file.path;
    }
    return '';
  }

  /// 删除入口：旧包删文件夹，新备份删单文件。
  String get deleteTarget => legacyFolder ? folderPath : filePath;

  String get fileSizeDisplay {
    final path = dataFileName;
    if (path.isEmpty) return '未知';
    final file = File(path);
    if (!file.existsSync()) return '未知';
    final size = file.lengthSync();
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class LocalBackupService {
  LocalBackupService._();
  static final instance = LocalBackupService._();

  static const _installationIdKey = 'installation_id';
  static const _installationTimeKey = 'installation_time';
  static const _lastAutoBackupKey = 'last_auto_backup_time';
  static const _backupsSubdir = '生活手账_backups';
  // 旧版“文件夹包”可能使用的根目录名，存在则一并扫描。
  static const _legacyBackupsSubdirs = ['life_organizer_backups'];
  static const _backupInfoFile = 'backup_info.json';

  String? _cachedInstallationId;

  Future<String> getOrCreateInstallationId() async {
    if (_cachedInstallationId != null) return _cachedInstallationId!;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_installationIdKey],
    );
    if (rows.isNotEmpty) {
      _cachedInstallationId = rows.first['value'] as String;
      return _cachedInstallationId!;
    }
    final random = Random.secure();
    final id = sha256
        .convert(
          List<int>.generate(32, (_) => random.nextInt(256)),
        )
        .toString();
    await db.insert(
      'app_settings',
      {'key': _installationIdKey, 'value': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {'key': _installationTimeKey, 'value': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cachedInstallationId = id;
    return id;
  }

  Future<String> getDeviceCode() async {
    final id = await getOrCreateInstallationId();
    return sha256.convert(utf8.encode(id)).toString().substring(0, 4).toUpperCase();
  }

  Future<Directory> getBackupsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_backupsSubdir');
    await dir.create(recursive: true);
    return dir;
  }

  /// 列出备份：新的单个 .enc 文件 + 旧版文件夹包，统一按时间倒序。
  Future<List<LocalBackupInfo>> listBackups() async {
    final docs = await getApplicationDocumentsDirectory();
    final roots = <Directory>[await getBackupsRoot()];
    for (final legacySubdir in _legacyBackupsSubdirs) {
      final dir = Directory(
        '${docs.path}${Platform.pathSeparator}$legacySubdir',
      );
      if (dir.existsSync()) roots.add(dir);
    }
    final backups = <LocalBackupInfo>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync()) {
        if (entity is File && entity.path.endsWith('.enc')) {
          backups.add(_infoFromEncFile(entity));
        } else if (entity is Directory) {
          final legacy = _infoFromLegacyFolder(entity);
          if (legacy != null) backups.add(legacy);
        }
      }
    }
    backups.sort((a, b) => b.exportTime.compareTo(a.exportTime));
    return backups;
  }

  LocalBackupInfo _infoFromEncFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final parsed = DatabaseBackupService.parseBackupFileName(fileName);
    final modified = file.lastModifiedSync();
    final name = parsed?.name ??
        (fileName.endsWith('.enc')
            ? fileName.substring(0, fileName.length - 4)
            : fileName);
    return LocalBackupInfo(
      filePath: file.path,
      name: name,
      // 单文件备份无需解密即可从文件名获知命名与时间。
      exportTime: parsed?.time ?? modified,
      autoBackup: name.contains('自动备份'),
      formatVersion: 4,
    );
  }

  LocalBackupInfo? _infoFromLegacyFolder(Directory folder) {
    final infoFile = File(
      '${folder.path}${Platform.pathSeparator}$_backupInfoFile',
    );
    if (!infoFile.existsSync()) return null;
    try {
      final json =
          jsonDecode(infoFile.readAsStringSync()) as Map<String, dynamic>;
      return LocalBackupInfo(
        folderPath: folder.path,
        legacyFolder: true,
        deviceCode: json['device_code'] as String? ?? '????',
        exportTime: DateTime.parse(json['export_time'] as String),
        deviceName: json['device_name'] as String? ?? '未知设备',
        formatVersion: json['format_version'] as int? ?? 4,
        autoBackup: json['auto_backup'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// 创建单个加密备份文件，返回 .enc 文件路径。
  Future<String> exportBackup({
    required String passphrase,
    String name = '',
    String? deviceName,
  }) async {
    final root = await getBackupsRoot();
    final backupFile = await DatabaseBackupService.instance.saveBackup(
      root,
      passphrase: passphrase,
      name: name,
    );
    return backupFile.path;
  }

  /// 从系统文件选择器选取的 .enc 文件导入到备份目录，
  /// 已存在同名文件时直接复用（不重复拷贝）。
  Future<LocalBackupInfo> importBackupFile(String sourceFilePath) async {
    final source = File(sourceFilePath);
    if (!source.existsSync()) {
      throw const FormatException('所选备份文件不存在');
    }
    final fileName = sourceFilePath.split(Platform.pathSeparator).last;
    if (!fileName.toLowerCase().endsWith('.enc')) {
      throw const FormatException('请选择 .enc 格式的备份文件');
    }
    final root = await getBackupsRoot();
    final dest = File('${root.path}${Platform.pathSeparator}$fileName');
    if (!await _sameFile(source, dest)) {
      await source.copy(dest.path);
    }
    return _infoFromEncFile(dest);
  }

  Future<bool> _sameFile(File a, File b) async {
    if (!b.existsSync()) return false;
    if (a.path == b.path) return true;
    return a.lengthSync() == b.lengthSync();
  }

  Future<String?> checkYearlyAutoBackup() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_lastAutoBackupKey],
    );
    if (rows.isNotEmpty) {
      final lastTime = DateTime.tryParse(rows.first['value'] as String);
      if (lastTime != null && DateTime.now().difference(lastTime).inDays < 365) {
        return null;
      }
    }

    final now = DateTime.now();
    final root = await getBackupsRoot();
    // 自动备份使用设备密钥（v3，仅本机可解），单文件保存。
    final backupFile = await DatabaseBackupService.instance.saveBackup(
      root,
      name: '自动备份',
      now: now,
    );

    await db.insert(
      'app_settings',
      {'key': _lastAutoBackupKey, 'value': now.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return backupFile.path;
  }

  Future<void> deleteBackup(String targetPath) async {
    if (targetPath.isEmpty) return;
    if (File(targetPath).existsSync()) {
      await File(targetPath).delete();
    } else {
      final dir = Directory(targetPath);
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }

  void clearCachedInstallationId() {
    _cachedInstallationId = null;
  }
}
