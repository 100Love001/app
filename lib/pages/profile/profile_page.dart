import 'dart:async';

import 'package:app/pages/profile/appearance_settings_page.dart';
import 'package:app/pages/profile/backup_management_page.dart';
import 'package:app/pages/profile/billing_system_page.dart';
import 'package:app/pages/profile/data_analysis_page.dart';
import 'package:app/pages/profile/preference_settings_page.dart';
import 'package:app/pages/profile/quote_management_page.dart';
import 'package:app/pages/profile/quote_reply_history_page.dart';
import 'package:app/pages/profile/tag_management_page.dart';
import 'package:app/pages/profile/time_capsule_page.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:app/utils/dialog.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onPersonalDataChanged});

  final VoidCallback? onPersonalDataChanged;

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final AppSettingsController _settings = AppSettingsController.instance;

  /// 页头统计（积分余额 / 完成任务 / 记账笔数）；加载失败保持 null 隐藏。
  ({int points, int completedTasks, int bills})? _stats;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
    unawaited(_loadStats());
  }

  void refresh() {
    unawaited(_settings.load());
    unawaited(_loadStats());
  }

  Future<void> _loadStats() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await Future.wait([
        db.rawQuery('SELECT COALESCE(SUM(point_value), 0) AS v FROM points'),
        db.rawQuery('SELECT COUNT(*) AS c FROM daily_task_reward_logs'),
        db.rawQuery(
          "SELECT COUNT(*) AS c FROM special_tasks WHERE status_tag = '已完成'",
        ),
        db.rawQuery(
          "SELECT COUNT(*) AS c FROM tasks WHERE status = '已完成'",
        ),
        db.rawQuery('SELECT COUNT(*) AS c FROM income_expenses'),
      ]);
      int count(Object? value) => int.tryParse('$value') ?? 0;
      final stats = (
        points: count(rows[0].first['v']),
        completedTasks:
            count(rows[1].first['c']) +
            count(rows[2].first['c']) +
            count(rows[3].first['c']),
        bills: count(rows[4].first['c']),
      );
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {
      // 统计加载失败不打断页面，保持隐藏。
    }
  }

  Future<void> _runSetting(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存设置失败：$error')));
    }
  }

  /// 提醒总开关：开启时先申请系统通知权限，再持久化并立即重排提醒；
  /// 关闭时取消所有已排程通知。
  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      try {
        await LocalNotificationService.instance.requestPermission();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
        return;
      }
    }
    await _runSetting(() => _settings.setNotificationsEnabled(value));
    try {
      await LocalNotificationService.instance.syncSchedule();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提醒同步失败：$error')));
      }
    }
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _settings.displayName);
    final signatureController = TextEditingController(
      text: _settings.signature,
    );
    final formKey = GlobalKey<FormState>();
    final values = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑个人资料'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                maxLength: 20,
                decoration: const InputDecoration(labelText: '昵称'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请输入昵称' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: signatureController,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '个性签名'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, (
                nameController.text,
                signatureController.text,
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    nameController.dispose();
    signatureController.dispose();
    if (values == null || !mounted) return;
    await _runSetting(
      () =>
          _settings.updateProfile(displayName: values.$1, signature: values.$2),
    );
  }

  Future<void> _clearPersonalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空个人记录？'),
        content: const Text(
          '此操作不可撤销。将删除任务、愿望与希望清单、日记、心情、收支、积分、纪念日、特殊语录和语录回复，并恢复默认语录；外观设置、预算、标签和文件夹结构会保留。',
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
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AppDatabase.instance.clearPersonalData();
      widget.onPersonalDataChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('个人记录已清空')));
      try {
        await LocalNotificationService.instance.syncSchedule();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('记录已清空，但提醒同步失败：$error')));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空个人记录失败：$error')));
      }
    }
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  /// 提醒时间磁贴的动态摘要，与提醒时间页的配置实时一致。
  String get _reminderSubtitle {
    String hourText(int hour) => hour.toString().padLeft(2, '0');
    final minutes = _settings.defaultRemindMinutes;
    final remind = minutes <= 0
        ? '准点提醒'
        : minutes % 1440 == 0
        ? '提前 ${minutes ~/ 1440} 天'
        : minutes % 60 == 0
        ? '提前 ${minutes ~/ 60} 小时'
        : '提前 $minutes 分钟';
    return '小结 ${hourText(_settings.dailySummaryHour)}:00 · '
        '纪念日 ${hourText(_settings.anniversaryReminderHour)}:00 · $remind';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, child) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildProfileCard(context),
            const SizedBox(height: 16),
            _buildSectionTitle('外观设置'),
            _buildGroupCard([
              _navTile(
                icon: Icons.palette_outlined,
                color: colorScheme.primary,
                title: '全局配置',
                subtitle: '主题颜色、深色模式、字体、卡片与按键样式',
                onTap: () => _open(const AppearanceSettingsPage()),
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle('通用设置'),
            _buildGroupCard([
              _navTile(
                icon: Icons.sell_outlined,
                color: colorScheme.primary,
                title: '标签设置',
                onTap: () => _open(const TagManagementPage()),
              ),
              _tileDivider(),
              _navTile(
                icon: Icons.schedule_outlined,
                color: colorScheme.tertiary,
                title: '提醒时间',
                subtitle: _reminderSubtitle,
                onTap: () => _open(const PreferenceSettingsPage()),
              ),
              _tileDivider(),
              _navTile(
                icon: Icons.receipt_long_outlined,
                color: colorScheme.secondary,
                title: '账单体系',
                subtitle: '记账分类、支出预算与积分兑换比例',
                onTap: () => _open(const BillingSystemPage()),
              ),
              _tileDivider(),
              SwitchListTile(
                secondary: _tileIcon(
                  Icons.notifications_outlined,
                  colorScheme.primary,
                ),
                title: const Text('消息与通知'),
                subtitle: const Text('任务提醒与每日记账提醒'),
                value: _settings.notificationsEnabled,
                onChanged: _toggleNotifications,
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle('语录设置'),
            _buildGroupCard([
              _navTile(
                icon: Icons.markunread_mailbox_outlined,
                color: colorScheme.secondary,
                title: '特殊语录',
                subtitle: '管理写给未来自己的语录',
                onTap: () => _open(const TimeCapsulePage()),
              ),
              _tileDivider(),
              _navTile(
                icon: Icons.forum_outlined,
                color: colorScheme.tertiary,
                title: '语录回复',
                subtitle: '查看用户交互场景的回复记录',
                onTap: () => _open(const QuoteReplyHistoryPage()),
              ),
              _tileDivider(),
              _navTile(
                icon: Icons.format_quote_rounded,
                color: colorScheme.primary,
                title: '今日语录',
                onTap: () => _open(const QuoteManagementPage()),
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionTitle('数据设置'),
            _buildGroupCard([
              _navTile(
                icon: Icons.insights_rounded,
                color: colorScheme.primary,
                title: '数据分析',
                subtitle: '积分、任务、收支与愿望统计',
                onTap: () => _open(const DataAnalysisPage()),
              ),
              _tileDivider(),
              _navTile(
                icon: Icons.backup_outlined,
                color: colorScheme.secondary,
                title: '数据备份',
                subtitle: '创建、恢复和管理备份包',
                onTap: () => _open(
                  BackupManagementPage(
                    onPersonalDataChanged: widget.onPersonalDataChanged,
                  ),
                ),
              ),
              _tileDivider(),
              ListTile(
                leading: _tileIcon(
                  Icons.delete_forever_outlined,
                  colorScheme.error,
                ),
                title: Text(
                  '清空个人记录',
                  style: TextStyle(color: colorScheme.error),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                onTap: _clearPersonalData,
              ),
              _tileDivider(),
              ListTile(
                leading: _tileIcon(Icons.info_outline, colorScheme.primary),
                title: const Text('版本信息'),
                trailing: Text(
                  '1.0.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tileIcon(IconData icon, Color color) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: color, size: 20),
  );

  Widget _tileDivider() => const Divider(height: 1, indent: 68);

  Widget _navTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: _tileIcon(icon, color),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 22,
      ),
      onTap: onTap,
    );
  }

  Widget _buildGroupCard(List<Widget> children) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = _settings.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _editProfile,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 31,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (_settings.signature.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            _settings.signature,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    _statItem(context, '积分余额', _stats?.points),
                    _statDivider(colorScheme),
                    _statItem(context, '完成任务', _stats?.completedTasks),
                    _statDivider(colorScheme),
                    _statItem(context, '记账笔数', _stats?.bills),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statDivider(ColorScheme colorScheme) => Container(
    width: 1,
    height: 26,
    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
  );

  Widget _statItem(BuildContext context, String label, int? value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value == null ? '--' : '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
