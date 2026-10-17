import 'dart:async';

import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:flutter/material.dart';

/// 提醒时间：把原来的固定值（每日小结、纪念日提醒、任务提前量）
/// 开放为可配置，修改后全局生效；保存后立即重排通知排程。
class PreferenceSettingsPage extends StatefulWidget {
  const PreferenceSettingsPage({super.key});

  @override
  State<PreferenceSettingsPage> createState() =>
      _PreferenceSettingsPageState();
}

class _PreferenceSettingsPageState extends State<PreferenceSettingsPage> {
  final AppSettingsController _settings = AppSettingsController.instance;

  static const _remindMinuteOptions = <int>[0, 5, 10, 15, 30, 60, 120, 1440];

  Future<void> _save(
    Future<void> Function() action, {
    bool affectsSchedule = false,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return;
    }
    if (!affectsSchedule) return;
    try {
      await LocalNotificationService.instance.syncSchedule();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存，但提醒重排失败：$error')));
    }
  }

  static String _remindMinutesText(int minutes) {
    if (minutes <= 0) return '不提前，准点提醒';
    if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
    if (minutes % 60 == 0) return '提前 ${minutes ~/ 60} 小时';
    return '提前 $minutes 分钟';
  }

  Future<void> _pickHour({
    required String title,
    required int current,
    required Future<void> Function(int hour) onSave,
  }) async {
    var selected = current;
    final value = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${selected.toString().padLeft(2, '0')}:00',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Slider(
                  value: selected.toDouble(),
                  min: 0,
                  max: 23,
                  divisions: 23,
                  label: '${selected.toString().padLeft(2, '0')}:00',
                  onChanged: (v) => setDialogState(() => selected = v.round()),
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
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await _save(() => onSave(value), affectsSchedule: true);
  }

  Future<void> _pickDefaultRemindMinutes() async {
    final value = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('任务默认提前提醒'),
        children: [
          RadioGroup<int>(
            groupValue: _settings.defaultRemindMinutes,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final minutes in _remindMinuteOptions)
                  RadioListTile<int>(
                    value: minutes,
                    title: Text(_remindMinutesText(minutes)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _save(
      () => _settings.setDefaultRemindMinutes(value),
      affectsSchedule: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒时间')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!_settings.notificationsEnabled) ...[
              Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.info_outline,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('通知开关当前关闭'),
                  subtitle: const Text('开启「我的-消息与通知」后，提醒时间设置才会生效'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: _tileIcon(
                      Icons.summarize_outlined,
                      colorScheme.secondary,
                    ),
                    title: const Text('每日小结推送时间'),
                    subtitle: Text(
                      '${_settings.dailySummaryHour.toString().padLeft(2, '0')}:00 推送当日完成与入账',
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onTap: () => _pickHour(
                      title: '每日小结推送时间',
                      current: _settings.dailySummaryHour,
                      onSave: _settings.setDailySummaryHour,
                    ),
                  ),
                  const Divider(height: 1, indent: 68),
                  ListTile(
                    leading: _tileIcon(
                      Icons.cake_outlined,
                      colorScheme.tertiary,
                    ),
                    title: const Text('纪念日提醒时间'),
                    subtitle: Text(
                      '纪念日当天 '
                      '${_settings.anniversaryReminderHour.toString().padLeft(2, '0')}:00 提醒',
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onTap: () => _pickHour(
                      title: '纪念日提醒时间',
                      current: _settings.anniversaryReminderHour,
                      onSave: _settings.setAnniversaryReminderHour,
                    ),
                  ),
                  const Divider(height: 1, indent: 68),
                  ListTile(
                    leading: _tileIcon(
                      Icons.alarm_rounded,
                      colorScheme.primary,
                    ),
                    title: const Text('任务默认提前提醒'),
                    subtitle: Text(
                      '${_remindMinutesText(_settings.defaultRemindMinutes)}，'
                      '新建特殊任务时默认采用',
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onTap: _pickDefaultRemindMinutes,
                  ),
                ],
              ),
            ),
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
}
