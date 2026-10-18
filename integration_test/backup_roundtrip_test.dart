import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/database_backup_service.dart';
import 'package:app/stores/database/local_backup_service.dart';
import 'package:app/utils/task_component.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// v5 备份包（.lifebook = data.enc + 附件）全链路验证：
/// 导出 -> 列表 -> 准备恢复 -> 校验密码 -> 恢复数据库 -> 附件还原与路径重写。
/// 直接调用 service 层，绕开 UI 事件（模拟器 adb 触摸注入不稳定）。
///
/// ⚠️ 危险：`flutter test integration_test` 会先卸载设备上的应用再安装，
/// 应用私有目录（数据库、备份包、附件）会全部清空！
/// 运行本测试前必须先执行：
///   adb exec-out run-as com.example.text tar -cf - . > 数据备份.tar
/// 将应用数据保全到电脑后再运行。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v5 backup roundtrip restores rows and attachments', (
    tester,
  ) async {
    final db = await AppDatabase.instance.database;
    final docs = await getApplicationDocumentsDirectory();
    final attachDir = Directory('${docs.path}${Platform.pathSeparator}task_attachments');
    await attachDir.create(recursive: true);

    // 1. 造一个测试附件 + 引用它的日常任务（图片组件共用 files 结构）。
    final attachFile = File('${attachDir.path}${Platform.pathSeparator}it_test_note.txt');
    await attachFile.writeAsString('integration-test-attachment');
    final doc = TaskComponentDocument([
      TaskComponent(
        type: ComponentType.images,
        data: {
          ComponentDataKeys.files: [
            {'name': 'it_test_note.txt', 'path': attachFile.path},
          ],
        },
      ),
    ]);
    final taskId = await db.insert('daily_tasks', {
      'name': 'IT-回环测试任务',
      'start_time': DateTime(2026, 10, 18, 8).toIso8601String(),
      'component_json': doc.encode(),
    });

    // 2. 导出 v5 包并确认入列表。
    final bundlePath = await LocalBackupService.instance.exportBackup(
      passphrase: 'test12345',
      name: 'IT回环测试备份',
    );
    expect(bundlePath, endsWith('.lifebook'));
    expect(File(bundlePath).existsSync(), isTrue);
    final backups = await LocalBackupService.instance.listBackups();
    final info = backups.firstWhere((item) => item.filePath == bundlePath);
    expect(info.isBundle, isTrue);
    expect(info.formatVersion, 5);

    // 3. 模拟换机：删掉本机附件与任务行，恢复后两者都应回来。
    await attachFile.delete();
    await db.delete('daily_tasks', where: 'id = ?', whereArgs: [taskId]);

    // 4. 准备恢复：解包拿到 data.enc 与附件目录。
    final prepared = await LocalBackupService.instance.prepareRestore(info);
    expect(prepared.dataBytes.length, greaterThan(0));
    expect(prepared.attachmentsDir, isNotNull);

    // 5. 密码校验 + 数据库恢复 + 附件还原。
    await DatabaseBackupService.instance.validateBackup(
      prepared.dataBytes,
      passphrase: 'test12345',
    );
    final result = await DatabaseBackupService.instance.restoreBackup(
      prepared.dataBytes,
      passphrase: 'test12345',
    );
    expect(result.restoredRowCount, greaterThan(0));
    final restoredAttachments = await LocalBackupService.instance
        .restoreAttachments(prepared.attachmentsDir!);
    expect(restoredAttachments, 1);
    expect(File(attachFile.path).existsSync(), isTrue);

    // 6. 数据落库且附件绝对路径已重写为本机目录。
    final rows = await db.query(
      'daily_tasks',
      where: 'id = ?',
      whereArgs: [taskId],
    );
    expect(rows, isNotEmpty);
    final rawJson = rows.first['component_json'] as String?;
    expect(rawJson, isNotNull);
    final restoredDoc = TaskComponentDocument.decode(rawJson);
    final items = TaskComponentDocument.fileItems(
      restoredDoc.dataOf(ComponentType.images),
    );
    expect(items, isNotEmpty);
    expect(items.first['path'], attachFile.path);

    // 7. 解包临时目录可被清理（真实流程由页面 finally 调用）。
    final tempDirPath = prepared.tempDir!;
    await LocalBackupService.instance.cleanupRestoreTemp(tempDirPath);
    expect(Directory(tempDirPath).existsSync(), isFalse);

    // 8. teardown：清掉测试任务行与测试备份包，应用数据回到测试前状态。
    await db.delete('daily_tasks', where: 'id = ?', whereArgs: [taskId]);
    await File(bundlePath).delete();
  });
}
