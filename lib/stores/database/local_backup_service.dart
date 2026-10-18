import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../constants/app_constants.dart';
import '../../utils/task_component.dart';
import 'add_database.dart';
import 'database_backup_service.dart';

/// 一条本地备份。
/// - v5：单个 .lifebook 包（zip：data.enc + task_attachments 附件）；
/// - v4：单个 .enc 加密文件；
/// - [folderPath] 仅用于兼容更旧的“文件夹包”备份。
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
    this.isBundle = false,
  });

  /// 单文件模式：加密文件（.enc）或备份包（.lifebook）绝对路径。
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

  /// v5 备份包（内含 data.enc 与附件目录）。
  final bool isBundle;

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
        } else if (entity is File && entity.path.endsWith('.lifebook')) {
          backups.add(_infoFromLifebookFile(entity));
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

  /// v5 备份包：文件名与 .enc 同规则，仅后缀不同。
  LocalBackupInfo _infoFromLifebookFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final baseName = fileName.toLowerCase().endsWith('.lifebook')
        ? fileName.substring(0, fileName.length - '.lifebook'.length)
        : fileName;
    final parsed = DatabaseBackupService.parseBackupFileName('$baseName.enc');
    return LocalBackupInfo(
      filePath: file.path,
      name: parsed?.name ?? baseName,
      exportTime: parsed?.time ?? file.lastModifiedSync(),
      autoBackup: baseName.contains('自动备份'),
      formatVersion: 5,
      isBundle: true,
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

  /// 创建 v5 加密备份包（.lifebook = data.enc + task_attachments 附件），
  /// 返回 .lifebook 文件路径。数据库内容仍走 v4 加密负载。
  Future<String> exportBackup({
    required String passphrase,
    String name = '',
    String? deviceName,
    DateTime? now,
  }) async {
    final root = await getBackupsRoot();
    final tempDir = await getTemporaryDirectory();
    final work = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      'backup_work_${DateTime.now().millisecondsSinceEpoch}',
    );
    await work.create(recursive: true);
    try {
      final encFile = await DatabaseBackupService.instance.saveBackup(
        work,
        passphrase: passphrase,
        name: name,
        now: now,
      );
      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          'data.enc',
          encFile.lengthSync(),
          await encFile.readAsBytes(),
        ),
      );
      for (final file in await _collectAttachmentFiles()) {
        final bytes = await file.readAsBytes();
        final fileName = file.path.split(Platform.pathSeparator).last;
        archive.addFile(ArchiveFile('attachments/$fileName', bytes.length, bytes));
      }
      final encName = encFile.path.split(Platform.pathSeparator).last;
      final bundleName =
          '${encName.substring(0, encName.length - '.enc'.length)}.lifebook';
      final bundleFile = File(
        '${root.path}${Platform.pathSeparator}$bundleName',
      );
      await bundleFile.writeAsBytes(ZipEncoder().encode(archive));
      return bundleFile.path;
    } finally {
      if (work.existsSync()) await work.delete(recursive: true);
    }
  }

  /// 收集需要随备份迁移的附件（任务图片/语音，位于 documents/task_attachments）。
  Future<List<File>> _collectAttachmentFiles() async {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${docs.path}${Platform.pathSeparator}task_attachments',
    );
    if (!folder.existsSync()) return const [];
    return folder.listSync().whereType<File>().toList();
  }

  /// 从系统文件选择器选取的备份文件（.lifebook / .enc）导入到备份目录，
  /// 已存在同名文件时直接复用（不重复拷贝）。
  Future<LocalBackupInfo> importBackupFile(String sourceFilePath) async {
    final source = File(sourceFilePath);
    if (!source.existsSync()) {
      throw const FormatException('所选备份文件不存在');
    }
    final fileName = sourceFilePath.split(Platform.pathSeparator).last;
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.lifebook') && !lower.endsWith('.enc')) {
      throw const FormatException('请选择 .lifebook 或 .enc 格式的备份文件');
    }
    final root = await getBackupsRoot();
    final dest = File('${root.path}${Platform.pathSeparator}$fileName');
    if (!await _sameFile(source, dest)) {
      await source.copy(dest.path);
    }
    return lower.endsWith('.lifebook')
        ? _infoFromLifebookFile(dest)
        : _infoFromEncFile(dest);
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
    final autoPassphrase = await getAutoBackupPassphrase();
    String backupPath;
    if (autoPassphrase != null && autoPassphrase.isNotEmpty) {
      // 已设置自动备份密码：v5 备份包（数据+附件），任意手机凭密码可恢复。
      backupPath = await exportBackup(
        passphrase: autoPassphrase,
        name: '自动备份',
        now: now,
      );
    } else {
      // 未设置：回退设备密钥（v3，仅本机可解）单文件备份。
      final backupFile = await DatabaseBackupService.instance.saveBackup(
        root,
        name: '自动备份',
        now: now,
      );
      backupPath = backupFile.path;
    }

    await db.insert(
      'app_settings',
      {'key': _lastAutoBackupKey, 'value': now.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return backupPath;
  }

  // ---------------- 自动备份密码（安全存储，不随备份导出） ----------------

  static const _autoBackupPassphraseKey = 'auto_backup_passphrase';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 已设置的自动备份密码；未设置返回 null。
  Future<String?> getAutoBackupPassphrase() =>
      _secureStorage.read(key: _autoBackupPassphraseKey);

  Future<void> setAutoBackupPassphrase(String? value) async {
    if (value == null || value.isEmpty) {
      await _secureStorage.delete(key: _autoBackupPassphraseKey);
      return;
    }
    await _secureStorage.write(key: _autoBackupPassphraseKey, value: value);
  }

  // ---------------- 恢复准备与附件还原 ----------------

  /// 恢复前准备：.enc 直接读取字节；.lifebook 解包到临时目录，
  /// 返回 data.enc 字节与附件目录（恢复数据库后调用 [restoreAttachments]）。
  /// [tempDir] 为 .lifebook 的解包目录，由调用方在恢复流程结束后
  /// 通过 [cleanupRestoreTemp] 清理（附件目录位于其内，不可提前删除）。
  Future<
    ({
      Uint8List dataBytes,
      String? attachmentsDir,
      String? tempDir,
    })
  >
  prepareRestore(LocalBackupInfo backup) async {
    if (!backup.isBundle) {
      final path = backup.dataFileName;
      if (path.isEmpty) {
        throw const FormatException('备份数据文件缺失');
      }
      return (
        dataBytes: await File(path).readAsBytes(),
        attachmentsDir: null,
        tempDir: null,
      );
    }
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(
      '${tempDir.path}${Platform.pathSeparator}'
      'restore_${DateTime.now().millisecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(
        await File(backup.filePath).readAsBytes(),
      );
      for (final file in archive.files) {
        final out = File(
          '${dir.path}${Platform.pathSeparator}'
          '${file.name.replaceAll('/', Platform.pathSeparator)}',
        );
        await out.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      }
      final dataFile = File('${dir.path}${Platform.pathSeparator}data.enc');
      if (!dataFile.existsSync()) {
        throw const FormatException('备份包缺少 data.enc 数据文件');
      }
      final attachmentsDir =
          '${dir.path}${Platform.pathSeparator}attachments';
      return (
        dataBytes: await dataFile.readAsBytes(),
        attachmentsDir:
            Directory(attachmentsDir).existsSync() ? attachmentsDir : null,
        tempDir: dir.path,
      );
    } catch (_) {
      // 解包失败时自清理，避免在 cache 留下残缺目录。
      if (dir.existsSync()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 清理 [prepareRestore] 解包产生的临时目录；幂等，路径为空时忽略。
  Future<void> cleanupRestoreTemp(String? tempDirPath) async {
    if (tempDirPath == null || tempDirPath.isEmpty) return;
    final dir = Directory(tempDirPath);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// 数据库恢复完成后调用：把备份包内的附件复制到本机
  /// documents/task_attachments，并按文件名重写任务组件里的旧设备
  /// 绝对路径（换手机后原路径无效）。返回恢复的附件数量。
  Future<int> restoreAttachments(String attachmentsDir) async {
    final docs = await getApplicationDocumentsDirectory();
    final destDir = Directory(
      '${docs.path}${Platform.pathSeparator}task_attachments',
    );
    await destDir.create(recursive: true);
    var count = 0;
    for (final entity
        in Directory(attachmentsDir).listSync().whereType<File>()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      await entity.copy('${destDir.path}${Platform.pathSeparator}$name');
      count++;
    }
    if (count > 0) await _rewriteAttachmentPaths(destDir.path);
    return count;
  }

  /// 重写三类任务 component_json 中图片/语音组件的绝对路径：
  /// 以文件名为准映射到本机 task_attachments 目录。
  Future<void> _rewriteAttachmentPaths(String taskAttachmentsPath) async {
    final db = await AppDatabase.instance.database;
    const tables = ['daily_tasks', 'special_tasks', 'tasks'];
    for (final table in tables) {
      final idColumn = table == 'tasks' ? 'task_id' : 'id';
      final rows = await db.query(
        table,
        columns: [idColumn, 'component_json'],
        where: 'component_json LIKE ?',
        whereArgs: ['%"${ComponentDataKeys.files}"%'],
      );
      for (final row in rows) {
        final raw = row['component_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final doc = TaskComponentDocument.decode(raw);
        // 图片与语音组件共用 files 数据结构，都可能有旧路径。
        var changed = false;
        for (final type in [ComponentType.images, ComponentType.voice]) {
          final index = doc.indexOf(type);
          if (index < 0) continue;
          final items = TaskComponentDocument.fileItems(
            doc.components[index].data,
          );
          for (final item in items) {
            final oldPath = '${item['path'] ?? ''}';
            if (oldPath.isEmpty) continue;
            final name = oldPath.split(Platform.pathSeparator).last;
            final newPath =
                '$taskAttachmentsPath${Platform.pathSeparator}$name';
            if (newPath != oldPath && File(newPath).existsSync()) {
              item['path'] = newPath;
              changed = true;
            }
          }
          if (changed) {
            doc.components[index] = TaskComponent(
              type: type,
              data: {ComponentDataKeys.files: items},
            );
          }
        }
        if (!changed) continue;
        await db.update(
          table,
          {'component_json': doc.encode()},
          where: '$idColumn = ?',
          whereArgs: [row[idColumn]],
        );
      }
    }
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
