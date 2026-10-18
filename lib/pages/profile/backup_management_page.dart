import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../stores/database/database_backup_service.dart';
import '../../stores/database/local_backup_service.dart';
import '../../stores/notifications/local_notification_service.dart';
import '../../stores/settings/app_settings_controller.dart';

class BackupManagementPage extends StatefulWidget {
  const BackupManagementPage({super.key, this.onPersonalDataChanged});

  final VoidCallback? onPersonalDataChanged;

  @override
  State<BackupManagementPage> createState() => _BackupManagementPageState();
}

class _BackupManagementPageState extends State<BackupManagementPage> {
  final LocalBackupService _backupService = LocalBackupService.instance;
  final AppSettingsController _settings = AppSettingsController.instance;
  List<LocalBackupInfo> _backups = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backups = await _backupService.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 返回用户输入的备份名称与密码；取消返回 null。
  Future<({String name, String passphrase})?> _askExportOptions() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final defaultName =
        DateFormat("yyyy年M月d日 HH时mm分").format(DateTime.now());
    final result =
        await showDialog<({String name, String passphrase})>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void submit() {
          final password = passwordController.text;
          if (password.length < 6) {
            ScaffoldMessenger.of(dialogContext)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text('密码至少需要 6 位')));
            return;
          }
          if (password != confirmController.text) {
            ScaffoldMessenger.of(dialogContext)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text('两次输入的密码不一致')));
            return;
          }
          final rawName = nameController.text.trim();
          Navigator.pop(
            dialogContext,
            (
              name: rawName.isEmpty ? defaultName : rawName,
              passphrase: password,
            ),
          );
        }

        return AlertDialog(
        title: const Text('创建备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '备份打包为单个加密文件（含图片/语音附件），可保存到手机或直接分享，'
              '在任意手机上凭密码恢复。'
              '密码无法找回，请妥善记忆；更换手机或重装应用后，'
              '需要凭此密码恢复备份。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: '备份名称（可留空）',
                hintText: '默认：$defaultName',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '备份密码（至少 6 位）'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码'),
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: submit,
            child: const Text('生成备份'),
          ),
        ],
        );
      },
    );
    // 对话框关闭动画期间 TextField 仍可能挂在树上，延迟一帧再释放
    // controller，避免触发 _dependents.isEmpty 断言导致红屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    });
    return result;
  }

  Future<String?> _askImportPassphrase() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入备份密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: '备份密码'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // 同上：延迟一帧释放，避免关闭动画期间的断言红屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return result;
  }

  Future<void> _exportBackup() async {
    final options = await _askExportOptions();
    if (options == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final filePath = await _backupService.exportBackup(
        passphrase: options.passphrase,
        name: options.name,
      );
      if (!mounted) return;
      // 单文件可直接分享，用户可保存到手机存储或发送到其他设备。
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          subject: '生活手账数据备份',
          fileNameOverrides: [filePath.split(Platform.pathSeparator).last],
          text: '生活手账加密数据备份（请妥善保管备份密码）',
        ),
      );
      await _loadBackups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份已生成为单个加密文件')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出备份失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromFile() async {
    PlatformFile? picked;
    try {
      // 用 FileType.any 而非按扩展名过滤：部分手机的文件管理器会把没有
      // 标准 MIME 类型的 .enc 文件灰显，导致从其他手机传来的备份选不中。
      // 后缀校验在 importBackupFile 内完成，选错时会给出明确提示。
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: '选择备份文件（.lifebook / .enc）',
      );
      final files = result?.files;
      picked = (files == null || files.isEmpty) ? null : files.first;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择文件失败：$error')));
      }
      return;
    }
    final sourcePath = picked?.path;
    if (sourcePath == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // 一步完成跨机迁移：文件拷入备份列表后直接进入恢复流程
      // （询问密码 → 校验 → 覆盖确认 → 恢复并刷新所有页面）。
      final imported = await _backupService.importBackupFile(sourcePath);
      await _loadBackups();
      if (!mounted) return;
      await _restoreBackup(imported);
      await _loadBackups();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入备份文件失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup(LocalBackupInfo backup) async {
    setState(() => _busy = true);
    String? restoreTempDir;
    try {
      // v5 包在此时解包（data.enc + 附件）；.enc 直接读取字节。
      final prepared = await _backupService.prepareRestore(backup);
      restoreTempDir = prepared.tempDir;
      final bytes = prepared.dataBytes;
      String? passphrase;
      final dbBackupService = DatabaseBackupService.instance;

      if (dbBackupService.requiresPassphrase(bytes)) {
        while (true) {
          if (!mounted) return;
          passphrase = await _askImportPassphrase();
          if (passphrase == null || passphrase.isEmpty) return;
          try {
            await dbBackupService.validateBackup(bytes, passphrase: passphrase);
            break;
          } catch (_) {
            if (!mounted) return;
            final retry = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: const Text('备份密码错误'),
                content: const Text('密码不正确，或备份文件已损坏。是否重新输入？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消恢复'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('重新输入'),
                  ),
                ],
              ),
            );
            if (retry != true) return;
          }
        }
      } else {
        await dbBackupService.validateBackup(bytes);
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复数据备份？'),
          content: Text(
            backup.isBundle
                ? '恢复会完整替换此设备上的记录、标签、预算和设置，'
                    '并同步备份包内的图片/语音附件。'
                    '开始前会自动将当前数据库另存为回滚备份。'
                : '恢复会完整替换此设备上的记录、标签、预算和设置。'
                    '开始前会自动将当前数据库另存为回滚备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('备份当前数据并恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await dbBackupService.restoreBackup(
        bytes,
        passphrase: passphrase,
      );
      // 数据库恢复成功后，同步备份包内的附件到本机并重写路径。
      var attachmentCount = 0;
      if (prepared.attachmentsDir != null) {
        attachmentCount = await _backupService.restoreAttachments(
          prepared.attachmentsDir!,
        );
      }
      _backupService.clearCachedInstallationId();
      await _settings.reload();
      widget.onPersonalDataChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              attachmentCount > 0
                  ? '恢复完成，共导入 ${result.restoredRowCount} 条记录、'
                      '$attachmentCount 个附件'
                  : '恢复完成，共导入 ${result.restoredRowCount} 条记录',
            ),
          ),
        );
      }
      try {
        await LocalNotificationService.instance.syncSchedule();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('数据已恢复，但提醒同步失败：$error')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复备份失败：$error')));
      }
    } finally {
      // 无论取消、密码错误、失败还是成功，都清理 .lifebook 解包临时目录
      //（附件已在此前复制进本机目录，此处删除不影响恢复结果）。
      try {
        await _backupService.cleanupRestoreTemp(restoreTempDir);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareBackup(LocalBackupInfo backup) async {
    final encPath = backup.dataFileName;
    if (encPath.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(encPath)],
          subject: '生活手账数据备份',
          text: '生活手账加密数据备份（请妥善保管备份密码）',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享备份失败：$error')));
      }
    }
  }

  Future<void> _deleteBackup(LocalBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除备份？'),
        content: const Text('删除后无法恢复，请确认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _backupService.deleteBackup(backup.deleteTarget);
      await _loadBackups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份已删除')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除备份失败：$error')));
      }
    }
  }

  Future<void> _showBackupActions(LocalBackupInfo backup) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_outlined),
              title: const Text('恢复此备份'),
              onTap: () => Navigator.pop(sheetContext, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('分享备份文件'),
              onTap: () => Navigator.pop(sheetContext, 'share'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'restore') await _restoreBackup(backup);
    if (action == 'share') await _shareBackup(backup);
    if (action == 'delete') await _deleteBackup(backup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地备份与恢复')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: _buildActionCards(context),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text('加载失败：$_error'),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _loadBackups,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        children: [
                          if (_backups.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.backup_outlined,
                                      size: 48,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '暂无备份',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '点击上方按钮创建或导入备份',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ..._backups.map(
                              (backup) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildBackupCard(context, backup),
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.add_a_photo_outlined,
                title: '创建备份',
                subtitle: '数据+附件 加密打包',
                color: Theme.of(context).colorScheme.primary,
                enabled: !_busy,
                onTap: _exportBackup,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.file_open_outlined,
                title: '导入备份文件',
                subtitle: '.lifebook / .enc 恢复',
                color: Theme.of(context).colorScheme.tertiary,
                enabled: !_busy,
                onTap: _importFromFile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AutoPassphraseCard(busy: _busy),
      ],
    );
  }

  Widget _buildBackupCard(BuildContext context, LocalBackupInfo backup) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('yyyy年M月d日 HH:mm');
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: _busy ? null : () => _showBackupActions(backup),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.secondaryContainer.withValues(alpha: 0.3),
                colorScheme.surfaceContainerLow,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.backup_outlined,
                  color: colorScheme.secondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            backup.name.isEmpty ? '未命名备份' : backup.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (backup.autoBackup)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '自动',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colorScheme.tertiary,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            backup.fileSizeDisplay,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.secondary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(backup.exportTime),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // 旧版文件夹包才有独立 sidecar 元数据，展示设备信息；
                    // 单文件备份的设备信息已在加密 payload 内，无需在列表展示。
                    if (backup.legacyFolder)
                      Text(
                        '设备 ${backup.deviceCode} · ${backup.deviceName} · 旧版备份包',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoPassphraseCard extends StatefulWidget {
  const _AutoPassphraseCard({required this.busy});

  final bool busy;

  @override
  State<_AutoPassphraseCard> createState() => _AutoPassphraseCardState();
}

class _AutoPassphraseCardState extends State<_AutoPassphraseCard> {
  final LocalBackupService _service = LocalBackupService.instance;
  bool _loading = true;
  bool _hasPassphrase = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final passphrase = await _service.getAutoBackupPassphrase();
    if (!mounted) return;
    setState(() {
      _hasPassphrase = passphrase != null && passphrase.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _editPassphrase() async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // 校验失败时保持弹窗不关闭，避免误触清除密码。
        void submit() {
          final password = controller.text;
          if (password.length < 6) {
            ScaffoldMessenger.of(dialogContext)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text('密码至少需要 6 位')));
            return;
          }
          if (password != confirmController.text) {
            ScaffoldMessenger.of(dialogContext)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(content: Text('两次输入的密码不一致')));
            return;
          }
          Navigator.pop(dialogContext, true);
        }

        return AlertDialog(
          title: Text(_hasPassphrase ? '修改自动备份密码' : '设置自动备份密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '设置后，每年的自动备份将以此密码加密打包（含附件），'
                '可在任意手机上恢复。密码不会随备份导出，请自行牢记。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: '自动备份密码（至少 6 位）'),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认密码'),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            if (_hasPassphrase)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('清除密码'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: submit,
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    // 对话框退场动画期间输入框仍挂在树上，延迟一帧再释放。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      confirmController.dispose();
    });
    if (saved == null) return;
    if (!saved) {
      // 清除密码
      await _service.setAutoBackupPassphrase(null);
    } else {
      await _service.setAutoBackupPassphrase(controller.text);
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? '已保存自动备份密码' : '已清除自动备份密码，自动备份仅本机可恢复')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        onTap: widget.busy ? null : _editPassphrase,
        leading: Icon(
          Icons.password_outlined,
          color: colorScheme.secondary,
        ),
        title: const Text('自动备份密码'),
        subtitle: Text(
          _loading
              ? '加载中…'
              : _hasPassphrase
              ? '已设置：自动备份为加密包，任意手机凭密码可恢复'
              : '未设置：自动备份仅本机可恢复，点击设置',
        ),
        trailing: Icon(
          _hasPassphrase ? Icons.lock_outline : Icons.lock_open_outlined,
          color: _hasPassphrase ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                colorScheme.surfaceContainerLow,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
