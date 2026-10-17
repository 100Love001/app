import 'dart:async';

import 'package:app/stores/home/time_capsule_repository.dart';
import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:app/utils/dialog.dart';
import 'package:flutter/material.dart';

/// 特殊语录（时光信箱）管理页：写给未来自己的话。
/// 未到解锁日期的语录只展示数量、不展示内容；到时间后在首页开启，
/// 开启与已到期的语录在这里可回看、可删除。
class TimeCapsulePage extends StatefulWidget {
  const TimeCapsulePage({super.key});

  @override
  State<TimeCapsulePage> createState() => _TimeCapsulePageState();
}

class _TimeCapsulePageState extends State<TimeCapsulePage> {
  final TimeCapsuleRepository _repository = TimeCapsuleRepository.instance;
  List<Map<String, dynamic>> _unlocked = [];
  int _pendingCount = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _repository.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final unlocked = await _repository.unlocked();
      final pending = await _repository.pendingCount();
      if (!mounted) return;
      setState(() {
        _unlocked = unlocked;
        _pendingCount = pending;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createCapsule() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    var unlockDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('写给未来的自己'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: '想对未来的自己说的话',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) =>
                      value?.trim().isEmpty == true ? '内容不能为空' : null,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('解锁日期'),
                  subtitle: Text(
                    '${unlockDate.year}年${unlockDate.month}月${unlockDate.day}日'
                    '，当天会收到一份特殊礼物',
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: unlockDate,
                      firstDate: DateTime(
                        tomorrow.year,
                        tomorrow.month,
                        tomorrow.day,
                      ),
                      lastDate: DateTime.now().add(
                        const Duration(days: 3650),
                      ),
                    );
                    if (picked == null) return;
                    setDialogState(() => unlockDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('封存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    if (saved != true) {
      controller.dispose();
      return;
    }
    try {
      await _repository.create(
        content: controller.text,
        unlockDate: unlockDate,
      );
      _showMessage('已封存，到时间会自动出现在首页和通知栏');
    } catch (error) {
      _showMessage('保存失败：$error');
    }
    controller.dispose();
  }

  Future<void> _deleteCapsule(Map<String, dynamic> capsule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条特殊语录？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(capsule['id'] as int);
      // 解锁日为今天的语录可能已排程通知，删除后全量重排以撤销，
      // 避免通知栏弹出一封已被删除的“礼物”。
      try {
        await LocalNotificationService.instance.syncSchedule();
      } catch (_) {
        // 重排失败不影响删除结果，下次同步时自动修正。
      }
    } catch (error) {
      _showMessage('删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('特殊语录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (_pendingCount > 0)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(
                  Icons.markunread_mailbox_outlined,
                  color: colorScheme.primary,
                ),
                title: Text('有 $_pendingCount 份特殊礼物正在路上'),
                subtitle: const Text('到解锁日期后会在首页和通知栏出现'),
              ),
            ),
          if (_error != null)
            Card(
              color: colorScheme.errorContainer,
              child: ListTile(
                title: const Text('读取失败'),
                subtitle: Text('$_error'),
                trailing: TextButton(
                  onPressed: _reload,
                  child: const Text('重试'),
                ),
              ),
            ),
          if (_unlocked.isEmpty && _pendingCount == 0 && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '还没有特殊语录',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '写一句话封存起来，未来的某天会作为礼物送还给你',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else
            for (final capsule in _unlocked)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(
                    Icons.card_giftcard_rounded,
                    color: colorScheme.secondary,
                  ),
                  title: Text(capsule['content'] as String),
                  subtitle: Text('解锁于 ${capsule['unlock_date']}'),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_deleteCapsule(capsule)),
                  ),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCapsule,
        icon: const Icon(Icons.add),
        label: const Text('写语录'),
      ),
    );
  }
}
