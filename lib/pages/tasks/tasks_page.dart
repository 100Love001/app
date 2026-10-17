import 'dart:async';

import 'package:app/constants/app_constants.dart';
import 'package:app/pages/records/records_page.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/date_range.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _TaskSection { special, daily, wishes, hopes }

/// B2：特殊任务提醒的预设提前量（分钟）。0 表示准时提醒。
const List<int> _specialReminderPresets = [0, 15, 30, 60, 1440, 4320, 10080];

/// 提前提醒分钟数 → 选项标签。
String _reminderLeadLabel(int minutes) {
  if (minutes == 0) return '准时';
  if (minutes % 1440 == 0) {
    final days = minutes ~/ 1440;
    return '提前 $days 天';
  }
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '提前 $mins 分钟';
  if (mins == 0) return '提前 $hours 小时';
  return '提前 $hours 小时$mins 分';
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  TasksPageState createState() => TasksPageState();
}

class TasksPageState extends State<TasksPage> {
  _TaskSection _section = _TaskSection.special;
  final PageController _todayCarouselController = PageController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _specialTasks = [];
  List<Map<String, dynamic>> _dailyTasks = [];
  List<Map<String, dynamic>> _dailyTags = [];
  int _carouselIndex = 0;
  String _specialFolder = '进行中';
  String _endedTaskFilter = '未完成';
  String _dailyStatus = '进行中';
  int? _dailyTagFilter;
  Timer? _carouselTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  /// 仅在今日任务超过 1 页时运行轮播定时器，避免空耗与
  /// 测试中 pumpAndSettle 永不静默。
  void _configureCarouselTimer() {
    final shouldRun = _todayTasks.length > 1;
    if (shouldRun && _carouselTimer != null) return;
    if (!shouldRun) {
      _carouselTimer?.cancel();
      _carouselTimer = null;
      return;
    }
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final count = _todayTasks.length;
      if (count > 1) {
        final nextPage = (_carouselIndex + 1) % count;
        setState(() => _carouselIndex = nextPage);
        if (_todayCarouselController.hasClients) {
          _todayCarouselController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _todayCarouselController.dispose();
    super.dispose();
  }

  void refresh() => unawaited(_loadTasks());

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PointsService.settleDailyTaskPenalties();
      final repo = TaskRepository.instance;
      final results = await Future.wait([
        repo.loadSpecialTasks(),
        repo.loadDailyTasks(),
        repo.loadDailyTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _specialTasks = results[0];
        _dailyTasks = results[1];
        _dailyTags = results[2];
        _carouselIndex = 0;
        _loading = false;
      });
      _configureCarouselTimer();
      if (_todayCarouselController.hasClients) {
        _todayCarouselController.jumpToPage(0);
      }
      if (AppSettingsController.instance.notificationsEnabled) {
        try {
          await LocalNotificationService.instance.syncSchedule();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('任务已加载，但提醒同步失败：$error')));
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '任务加载失败：$error';
      });
    }
  }

  List<Map<String, dynamic>> get _todayTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool isToday(String? value) {
      if (value == null) return false;
      final date = DateTime.tryParse(value);
      return date != null &&
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }

    final special = _specialTasks
        .where((task) {
          if (_specialStatus(task) != '进行中') return false;
          final start = DateTime.tryParse('${task['start_time']}');
          final end = DateTime.tryParse('${task['end_time']}');
          return start != null &&
              end != null &&
              !today.isBefore(DateTime(start.year, start.month, start.day)) &&
              !today.isAfter(DateTime(end.year, end.month, end.day));
        })
        .map((task) => {...task, 'kind': '特殊任务'});
    final daily = _dailyTasks
        .where((task) {
          if (task['status_tag'] != '进行中') return false;
          // B1：习惯型按重复规则判定今天是否打卡日。
          if (_isHabitTask(task)) return _habitDueToday(task);
          return isToday(task['next_review_time'] as String?) ||
              isToday(task['start_time'] as String?);
        })
        .map((task) => {...task, 'kind': '日常任务'});
    return [...special, ...daily];
  }

  Future<void> _completeTask(Map<String, dynamic> task) async {
    final isSpecial = task['kind'] == '特殊任务';
    final status = isSpecial
        ? _specialStatus(task)
        : task['status_tag'] as String;
    if (status != '进行中' ||
        (!isSpecial &&
            (_dailyRewardClaimedToday(task) || !_dailyClaimableToday(task)))) {
      return;
    }
    final id = task['id'] as int;
    try {
      final reward = isSpecial
          ? await PointsService.completeSpecialTask(id)
          : _isHabitTask(task)
          ? await PointsService.claimHabitTaskReward(
              taskId: id,
              date: DateTime.now(),
            )
          : await PointsService.claimDailyTaskReward(
              taskId: id,
              date: DateTime.now(),
            );
      if (reward == null) {
        await _loadTasks();
        if (mounted && !isSpecial) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('今日奖励已经领取，或任务当前不可领取')));
        }
        return;
      }
      await _loadTasks();
      if (mounted) {
        final message = isSpecial
            ? (reward > 0 ? '任务完成，获得 $reward 积分' : '任务已完成')
            : '已领取今日任务奖励：$reward 积分';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新任务失败：$error')));
    }
  }

  /// 逾期特殊任务补完成：确认后归档为“已完成”，不发放积分。
  Future<void> _closeExpiredSpecialTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('补标记完成'),
        content: const Text('该任务已超过截止时间，补标记完成不会发放积分。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final ok = await PointsService.closeExpiredSpecialTask(task['id'] as int);
      await _loadTasks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已补标记完成（不计积分）' : '任务当前不可补完成，请刷新后重试')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新任务失败：$error')));
    }
  }

  bool _dailyRewardClaimedToday(Map<String, dynamic> task) =>
      toInt(task['reward_claimed_today']) == 1;

  /// 日常任务今天是否已到领奖窗口：今天 >= 开始日期且今天 >= 下次复习日期。
  /// 错过的复习日也视为到期（允许补领一次），由服务层做最终校验。
  bool _dailyClaimDue(Map<String, dynamic> task) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? dayOf(Object? value) {
      final parsed = DateTime.tryParse('$value');
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final startDay = dayOf(task['start_time']);
    final reviewDay = dayOf(task['next_review_time']);
    if (startDay == null || reviewDay == null) return false;
    return !today.isBefore(startDay) && !today.isBefore(reviewDay);
  }

  /// B1：习惯型日常任务判定。
  bool _isHabitTask(Map<String, dynamic> task) => task['task_mode'] == 'habit';

  RepeatRule _repeatRuleOf(Map<String, dynamic> task) => RepeatRule.fromColumns(
    task['repeat_type'] as String?,
    task['repeat_value'] as String?,
  );

  /// B1：习惯任务今天是否为打卡日。
  bool _habitDueToday(Map<String, dynamic> task) {
    final start = DateTime.tryParse('${task['start_time']}');
    if (start == null) return false;
    return _repeatRuleOf(task).isDueOn(DateTime.now(), start);
  }

  /// 日常任务今天能否领奖：习惯型看重复规则，复习型看复习日期。
  bool _dailyClaimableToday(Map<String, dynamic> task) =>
      _isHabitTask(task) ? _habitDueToday(task) : _dailyClaimDue(task);

  Future<void> _addTask({
    required bool special,
    Map<String, dynamic>? task,
  }) async {
    late final List<Map<String, dynamic>> tags;
    try {
      tags = special
          ? await _queryTags('special_task_tags')
          : await _queryTags('daily_task_tags');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('读取任务标签失败：$error')));
      }
      return;
    }
    if (!mounted) return;

    final nameController = TextEditingController(
      text: task?['name'] as String? ?? '',
    );
    final contentController = TextEditingController(
      text: task?['content'] as String? ?? '',
    );
    final remarkController = TextEditingController(
      text: task?['remark'] as String? ?? '',
    );
    final requirementController = TextEditingController(
      text: task?['requirement'] as String? ?? '',
    );
    final pointsController = TextEditingController(
      text: task == null
          ? special
                ? '10'
                : '1'
          : '${task[special ? 'reward_points' : 'daily_points']}',
    );
    final penaltyController = TextEditingController(
      text: task == null ? '0' : '${task['penalty_points'] ?? 0}',
    );
    final currentTag = task?['task_tag_id'] as int?;
    int? selectedTag = tags.any((tag) => tag['id'] == currentTag)
        ? currentTag
        : tags.isEmpty
        ? null
        : tags.first['id'] as int;
    DateTime start =
        DateTime.tryParse('${task?['start_time']}') ?? DateTime.now();
    DateTime end =
        DateTime.tryParse('${task?['end_time']}') ??
        start.add(const Duration(hours: 1));
    // B2：编辑特殊任务时读回已配置的多档提醒；新建默认用个性化参数中的提前量。
    var selectedReminders = <int>{
      AppSettingsController.instance.defaultRemindMinutes,
    };
    if (special && task != null) {
      try {
        final stored = await TaskRepository.instance.loadSpecialTaskReminders(
          task['id'] as int,
        );
        if (stored.isNotEmpty) selectedReminders = stored.toSet();
      } catch (_) {
        // 读取失败保留默认值，不阻塞编辑。
      }
    }
    // B1：日常任务模式（记忆复习型/自定义习惯型）与习惯配置。
    var habitMode = false;
    var repeatType = RepeatType.daily;
    var selectedWeekdays = <int>{};
    var selectedMonthDays = <int>{};
    final intervalController = TextEditingController(text: '2');
    var reminderTimes = <TimeOfDay>[
      const TimeOfDay(hour: AppConstants.reminderMorningHour, minute: 0),
    ];
    if (!special && task != null && task['task_mode'] == 'habit') {
      habitMode = true;
      final rule = RepeatRule.fromColumns(
        task['repeat_type'] as String?,
        task['repeat_value'] as String?,
      );
      repeatType = rule.type;
      if (repeatType == RepeatType.weekly) {
        selectedWeekdays = RepeatRule.intList(rule.value).toSet();
      } else if (repeatType == RepeatType.monthly) {
        selectedMonthDays = RepeatRule.intList(rule.value).toSet();
      } else if (repeatType == RepeatType.interval) {
        intervalController.text = (rule.value ?? '').trim().isEmpty
            ? '2'
            : rule.value!.trim();
      }
      try {
        final stored = await TaskRepository.instance.loadDailyTaskReminders(
          task['id'] as int,
        );
        if (stored.isNotEmpty) {
          reminderTimes = stored
              .map((time) => TimeOfDay(hour: time.hour, minute: time.minute))
              .toList();
        }
      } catch (_) {
        // 读取失败保留默认提醒时刻。
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${task == null ? '添加' : '编辑'}${special ? '特殊任务' : '日常任务'}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '名称 *'),
                ),
                TextField(
                  controller: contentController,
                  // 随内容自动向下增高（最小 2 行，不设上限）。
                  minLines: 2,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: '内容'),
                ),
                TextField(
                  controller: requirementController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '要求',
                    helperText: '选填：完成该任务需满足的条件/验收标准',
                  ),
                ),
                TextField(
                  controller: remarkController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                TextField(
                  controller: pointsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: special ? '完成奖励积分' : '每日完成积分',
                    suffixText: '分',
                  ),
                ),
                TextField(
                  controller: penaltyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '未完成扣除积分',
                    suffixText: '分',
                    helperText: '任务未完成时扣除的积分',
                  ),
                ),
                if (tags.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('暂无任务标签，将保存为未分类'),
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: selectedTag,
                    decoration: const InputDecoration(labelText: '任务标签'),
                    items: tags
                        .map(
                          (tag) => DropdownMenuItem<int>(
                            value: tag['id'] as int,
                            child: Text(tag['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedTag = value),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('开始：${_formatDate(start.toIso8601String())}'),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (value != null) {
                      if (!context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(start),
                      );
                      if (!context.mounted) return;
                      final selectedTime =
                          time ?? TimeOfDay.fromDateTime(start);
                      setDialogState(() {
                        start = DateTime(
                          value.year,
                          value.month,
                          value.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );
                        if (!special) {
                          end = start;
                        } else if (end.isBefore(start)) {
                          end = DateTime(
                            start.year,
                            start.month,
                            start.day,
                            23,
                            59,
                          );
                        }
                      });
                    }
                  },
                ),
                // B1：日常任务支持两种模式。
                if (!special) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Text('任务模式'),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('记忆复习型'),
                        selected: !habitMode,
                        onSelected: (_) =>
                            setDialogState(() => habitMode = false),
                      ),
                      ChoiceChip(
                        label: const Text('自定义习惯型'),
                        selected: habitMode,
                        onSelected: (_) =>
                            setDialogState(() => habitMode = true),
                      ),
                    ],
                  ),
                  if (!habitMode)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '按艾宾浩斯曲线安排复习，到期可领取每日积分',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  if (habitMode) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 4),
                        child: Text('重复规则'),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in const [
                          (RepeatType.daily, '每天'),
                          (RepeatType.weekly, '每周'),
                          (RepeatType.monthly, '每月'),
                          (RepeatType.interval, '间隔天数'),
                        ])
                          ChoiceChip(
                            label: Text(entry.$2),
                            selected: repeatType == entry.$1,
                            onSelected: (_) =>
                                setDialogState(() => repeatType = entry.$1),
                          ),
                      ],
                    ),
                    if (repeatType == RepeatType.weekly)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          children: [
                            for (var weekday = 1; weekday <= 7; weekday++)
                              FilterChip(
                                label: Text(
                                  const [
                                    '一',
                                    '二',
                                    '三',
                                    '四',
                                    '五',
                                    '六',
                                    '日',
                                  ][weekday - 1],
                                ),
                                selected: selectedWeekdays.contains(weekday),
                                onSelected: (checked) => setDialogState(() {
                                  if (checked) {
                                    selectedWeekdays.add(weekday);
                                  } else {
                                    selectedWeekdays.remove(weekday);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    if (repeatType == RepeatType.monthly)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: [
                            for (var day = 1; day <= 31; day++)
                              FilterChip(
                                label: Text('$day'),
                                selected: selectedMonthDays.contains(day),
                                onSelected: (checked) => setDialogState(() {
                                  if (checked) {
                                    selectedMonthDays.add(day);
                                  } else {
                                    selectedMonthDays.remove(day);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    if (repeatType == RepeatType.interval)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: intervalController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '每隔多少天打卡一次',
                            suffixText: '天',
                          ),
                        ),
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 4),
                        child: Text('提醒时间点（可添加多个）'),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (
                          var index = 0;
                          index < reminderTimes.length;
                          index++
                        )
                          Chip(
                            label: Text(reminderTimes[index].format(context)),
                            onDeleted: reminderTimes.length <= 1
                                ? null
                                : () => setDialogState(
                                    () => reminderTimes.removeAt(index),
                                  ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add_alarm, size: 18),
                          label: const Text('添加时间'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: const TimeOfDay(hour: 9, minute: 0),
                            );
                            if (picked != null) {
                              final exists = reminderTimes.any(
                                (time) =>
                                    time.hour == picked.hour &&
                                    time.minute == picked.minute,
                              );
                              if (!exists) {
                                setDialogState(() => reminderTimes.add(picked));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
                if (special)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('结束：${_formatDate(end.toIso8601String())}'),
                    onTap: () async {
                      final firstDate = DateTime(
                        start.year,
                        start.month,
                        start.day,
                      );
                      final lastDate = DateTime(2100);
                      final initialEnd = clampDateToRange(
                        end,
                        firstDate,
                        lastDate,
                      );
                      final value = await showDatePicker(
                        context: context,
                        initialDate: initialEnd,
                        firstDate: firstDate,
                        lastDate: lastDate,
                      );
                      if (value != null) {
                        if (!context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(end),
                        );
                        if (!context.mounted) return;
                        final selectedTime =
                            time ?? TimeOfDay.fromDateTime(end);
                        setDialogState(
                          () => end = DateTime(
                            value.year,
                            value.month,
                            value.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          ),
                        );
                      }
                    },
                  ),
                // B2：特殊任务支持多档提前提醒（含准时/自定义）。
                if (special) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Text('提醒时间（可多选）'),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final minutes in _specialReminderPresets)
                        FilterChip(
                          label: Text(_reminderLeadLabel(minutes)),
                          selected: selectedReminders.contains(minutes),
                          onSelected: (checked) {
                            setDialogState(() {
                              if (checked) {
                                selectedReminders.add(minutes);
                              } else {
                                selectedReminders.remove(minutes);
                              }
                            });
                          },
                        ),
                      // 非预设的自定义提前量，可单独取消。
                      for (final minutes
                          in selectedReminders
                              .where(
                                (value) =>
                                    !_specialReminderPresets.contains(value),
                              )
                              .toList()
                            ..sort())
                        Chip(
                          label: Text(_reminderLeadLabel(minutes)),
                          onDeleted: () => setDialogState(
                            () => selectedReminders.remove(minutes),
                          ),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('自定义'),
                        onPressed: () async {
                          final custom = await _askCustomReminder(context);
                          if (custom != null) {
                            setDialogState(() => selectedReminders.add(custom));
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(const SnackBar(content: Text('请输入任务名称')));
                  return;
                }
                final points = int.tryParse(pointsController.text.trim());
                if (points == null || points < 0) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('请输入有效的非负积分')));
                  return;
                }
                final penalty =
                    int.tryParse(penaltyController.text.trim()) ?? 0;
                if (penalty < 0) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(const SnackBar(content: Text('扣除积分不能为负数')));
                  return;
                }
                if (special && end.isBefore(start)) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
                  return;
                }
                // B1：习惯型配置校验。
                String? repeatValue;
                if (!special && habitMode) {
                  if (repeatType == RepeatType.weekly &&
                      selectedWeekdays.isEmpty) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(const SnackBar(content: Text('请至少选择一个星期')));
                    return;
                  }
                  if (repeatType == RepeatType.monthly &&
                      selectedMonthDays.isEmpty) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(const SnackBar(content: Text('请至少选择一个日期')));
                    return;
                  }
                  if (repeatType == RepeatType.interval) {
                    final days = int.tryParse(intervalController.text.trim());
                    if (days == null || days < 1) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('请输入有效的间隔天数（至少 1 天）')),
                      );
                      return;
                    }
                    repeatValue = '$days';
                  } else if (repeatType == RepeatType.weekly) {
                    repeatValue = RepeatRule.encode(selectedWeekdays.toList());
                  } else if (repeatType == RepeatType.monthly) {
                    repeatValue = RepeatRule.encode(selectedMonthDays.toList());
                  }
                  if (reminderTimes.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('请至少添加一个提醒时间点')),
                    );
                    return;
                  }
                }
                try {
                  final repo = TaskRepository.instance;
                  if (special) {
                    final values = {
                      'name': nameController.text.trim(),
                      'content': contentController.text.trim(),
                      'requirement': requirementController.text.trim(),
                      'remark': remarkController.text.trim(),
                      'start_time': start.toIso8601String(),
                      'end_time': end.toIso8601String(),
                      'task_tag_id': selectedTag,
                      'reward_points': points,
                      'penalty_points': penalty,
                    };
                    await repo.saveSpecialTask(
                      values,
                      id: task?['id'] as int?,
                      remindMinutesBefore: selectedReminders,
                    );
                  } else {
                    final values = {
                      'name': nameController.text.trim(),
                      'content': contentController.text.trim(),
                      'requirement': requirementController.text.trim(),
                      'remark': remarkController.text.trim(),
                      'start_time': start.toIso8601String(),
                      'task_tag_id': selectedTag,
                      'daily_points': points,
                      'penalty_points': penalty,
                      // B1：模式与重复规则。
                      'task_mode': habitMode ? 'habit' : 'review',
                      'repeat_type': habitMode ? repeatType.name : 'daily',
                      'repeat_value': habitMode ? repeatValue : null,
                      if (task != null && toInt(task['review_stage']) == 0)
                        'next_review_time': start.toIso8601String(),
                    };
                    await repo.saveDailyTask(
                      values,
                      id: task?['id'] as int?,
                      // 习惯型写入多个提醒点；切回复习型则清空旧提醒。
                      reminders: habitMode
                          ? reminderTimes
                                .map(
                                  (time) =>
                                      (hour: time.hour, minute: time.minute),
                                )
                                .toList()
                          : const [],
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text('保存任务失败：$error')));
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    // Wait for the dialog's reverse animation before disposing its field
    // controllers or rebuilding the page that owns the dialog route.
    await waitForDialogDismissal();
    nameController.dispose();
    contentController.dispose();
    remarkController.dispose();
    requirementController.dispose();
    pointsController.dispose();
    penaltyController.dispose();
    intervalController.dispose();
    if (saved == true && mounted) await _loadTasks();
  }

  /// B2：自定义提前提醒（天/小时/分钟组合），返回总分钟数。
  Future<int?> _askCustomReminder(BuildContext context) {
    final dayController = TextEditingController(text: '0');
    final hourController = TextEditingController(text: '0');
    final minuteController = TextEditingController(text: '30');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义提前提醒'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: dayController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '天'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: hourController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '小时'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: minuteController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '分钟'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final days = int.tryParse(dayController.text.trim()) ?? 0;
              final hours = int.tryParse(hourController.text.trim()) ?? 0;
              final minutes = int.tryParse(minuteController.text.trim()) ?? 0;
              if (days < 0 ||
                  hours < 0 ||
                  minutes < 0 ||
                  hours > 23 ||
                  minutes > 59 ||
                  days > 365) {
                ScaffoldMessenger.of(dialogContext)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('请输入有效时间（天 0-365、小时 0-23、分钟 0-59）'),
                    ),
                  );
                return;
              }
              final total = days * 1440 + hours * 60 + minutes;
              if (total <= 0) {
                ScaffoldMessenger.of(dialogContext)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('提前时间需大于 0')));
                return;
              }
              Navigator.pop(dialogContext, total);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _queryTags(String table) async {
    if (table == 'special_task_tags') {
      return TaskRepository.instance.loadSpecialTags();
    }
    return TaskRepository.instance.loadDailyTags();
  }

  Future<void> _startSpecialTask(Map<String, dynamic> task) async {
    try {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().toIso8601String();
      await db.update(
        'special_tasks',
        {'start_time': now},
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [task['id'] as int],
      );
      await _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('任务已开始，截止时间不变')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('开始任务失败：$error')));
      }
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final isSpecial = task['kind'] == '特殊任务';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('删除${isSpecial ? '特殊' : '日常'}任务'),
        content: Text('确定删除“${task['name']}”吗？已有积分和打卡历史会保留，此任务将从列表中隐藏。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final changed = await TaskRepository.instance.softDeleteTask(
        table: isSpecial ? 'special_tasks' : 'daily_tasks',
        id: task['id'] as int,
      );
      if (changed == 0) throw StateError('任务不存在或已删除');
      if (mounted) await _loadTasks();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除任务失败：$error')));
      }
    }
  }

  Future<void> _showTaskDetails(Map<String, dynamic> task) async {
    final isSpecial = task['kind'] == '特殊任务';
    final status = isSpecial
        ? _specialStatus(task)
        : task['status_tag'] as String;
    final rewardClaimedToday = !isSpecial && _dailyRewardClaimedToday(task);
    // B2：详情中展示该特殊任务的提醒安排。
    var reminderText = '';
    if (isSpecial) {
      try {
        final reminders = await TaskRepository.instance
            .loadSpecialTaskReminders(task['id'] as int);
        if (reminders.isNotEmpty) {
          reminderText = reminders.map(_reminderLeadLabel).join('、');
        }
      } catch (_) {
        reminderText = '';
      }
    } else if (_isHabitTask(task)) {
      // B1：习惯任务展示重复规则与多个提醒时刻。
      try {
        final reminders = await TaskRepository.instance.loadDailyTaskReminders(
          task['id'] as int,
        );
        if (reminders.isNotEmpty && mounted) {
          reminderText = reminders
              .map(
                (time) => TimeOfDay(
                  hour: time.hour,
                  minute: time.minute,
                ).format(context),
              )
              .join('、');
        }
      } catch (_) {
        reminderText = '';
      }
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task['name'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _DetailLine(label: '任务类型', value: task['kind'] as String? ?? ''),
              _DetailLine(
                label: '任务标签',
                value: task['tag_name'] as String? ?? '未分类',
              ),
              if (isSpecial)
                _DetailLine(
                  label: '时间',
                  value:
                      '${_formatDate(task['start_time'])} - ${_formatDate(task['end_time'])}',
                ),
              if (isSpecial && reminderText.isNotEmpty)
                _DetailLine(label: '提醒', value: reminderText),
              if (!isSpecial && _isHabitTask(task)) ...[
                _DetailLine(
                  label: '重复规则',
                  value: _repeatRuleOf(task).displayText,
                ),
                if (reminderText.isNotEmpty)
                  _DetailLine(label: '提醒时间', value: reminderText),
              ],
              if (!isSpecial && !_isHabitTask(task))
                _DetailLine(
                  label: '复习阶段',
                  value:
                      '第 ${(task['review_stage'] as int?) ?? 0} 次（按艾宾浩斯曲线安排）',
                ),
              _DetailLine(
                label: '完成奖励',
                value:
                    '${toInt(task[isSpecial ? 'reward_points' : 'daily_points'])} 积分',
              ),
              if (toInt(task['penalty_points']) > 0)
                _DetailLine(
                  label: '未完成扣除',
                  value: '${toInt(task['penalty_points'])} 积分',
                ),
              const SizedBox(height: 8),
              Text(task['content'] as String? ?? '暂无详细内容'),
              if ((task['requirement'] as String? ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('要求：${(task['requirement'] as String).trim()}'),
                ),
              ],
              if ((task['remark'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '备注：${task['remark']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              if (isSpecial && status == '未开始')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 'start'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始任务'),
                  ),
                )
              else if (isSpecial)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: status != '进行中'
                        ? null
                        : () => Navigator.pop(context, 'complete'),
                    icon: const Icon(Icons.check),
                    label: Text(
                      status == '已完成'
                          ? '已完成'
                          : status == '已结束'
                          ? '任务已结束'
                          : '完成任务',
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final due = _dailyClaimableToday(task);
                    final isHabit = _isHabitTask(task);
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: status != '进行中' || rewardClaimedToday || !due
                            ? null
                            : () => Navigator.pop(context, 'complete'),
                        icon: const Icon(Icons.check),
                        label: Text(
                          rewardClaimedToday
                              ? '今日奖励已领取'
                              : status == '已完成'
                              ? '已完成'
                              : due
                              ? '领取今日奖励'
                              : isHabit
                              ? '今天非打卡日'
                              : '未到复习日期',
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                  if (!isSpecial)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'history'),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('打卡历史'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'complete':
        if (status == '进行中' && (isSpecial || !rewardClaimedToday)) {
          await _completeTask(task);
        }
        break;
      case 'start':
        if (isSpecial && status == '未开始') {
          await _startSpecialTask(task);
        }
        break;
      case 'edit':
        await _addTask(special: isSpecial, task: task);
        break;
      case 'history':
        if (!isSpecial) await _showDailyTaskHistory(task);
        break;
      case 'delete':
        await _deleteTask(task);
        break;
      case null:
        break;
    }
  }

  Future<void> _showDailyTaskHistory(Map<String, dynamic> task) async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
    final firstDate = TimeUtil.toDateKey(firstDay);
    final nextDate = TimeUtil.toDateKey(nextMonth);
    try {
      final logs = await TaskRepository.instance.loadDailyTaskRewardLogs(
        taskId: task['id'] as int,
        startDate: firstDate,
        endDate: nextDate,
      );
      if (!mounted) return;
      final checkedDays = logs
          .map((log) => DateTime.tryParse('${log['reward_date']}')?.day)
          .whereType<int>()
          .toSet();
      final leadingDays = firstDay.weekday - 1;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${task['name']} · ${now.year}年${now.month}月',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '本月打卡 ${checkedDays.length} 天',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 7 + leadingDays + lastDay,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 0.9,
                        ),
                    itemBuilder: (context, index) {
                      if (index < 7) {
                        return Center(
                          child: Text(
                            ['一', '二', '三', '四', '五', '六', '日'][index],
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        );
                      }
                      final day = index - 7 - leadingDays + 1;
                      if (day < 1 || day > lastDay) {
                        return const SizedBox.shrink();
                      }
                      final checked = checkedDays.contains(day);
                      return Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: checked
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: checked
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$day'),
                              if (checked)
                                Icon(
                                  Icons.check_circle,
                                  size: 15,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('读取打卡历史失败：$error')));
      }
    }
  }

  String _formatDate(Object? value) {
    final date = DateTime.tryParse('$value');
    return date == null ? '未设置' : DateFormat('MM月dd日 HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions:
            _section == _TaskSection.special || _section == _TaskSection.daily
            ? [
                PopupMenuButton<String>(
                  tooltip: '添加任务',
                  onSelected: (value) => _addTask(special: value == 'special'),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'special', child: Text('添加特殊任务')),
                    PopupMenuItem(value: 'daily', child: Text('添加日常任务')),
                  ],
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: '刷新任务',
                  onPressed: _loading ? null : _loadTasks,
                  icon: const Icon(Icons.refresh),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildSectionTabs(),
          ),
          Expanded(
            child:
                _section == _TaskSection.wishes ||
                    _section == _TaskSection.hopes
                ? RecordsPage(
                    key: ValueKey(_section),
                    taskListsOnly: true,
                    openHopes: _section == _TaskSection.hopes,
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadTasks)
                : RefreshIndicator(
                    onRefresh: _loadTasks,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _buildToday(),
                        const SizedBox(height: 12),
                        if (_section == _TaskSection.special) _buildSpecial(),
                        if (_section == _TaskSection.daily) _buildDaily(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in const [
            (_TaskSection.special, '特殊任务'),
            (_TaskSection.daily, '日常任务'),
            (_TaskSection.wishes, '愿望清单'),
            (_TaskSection.hopes, '希望清单'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.$2),
                selected: _section == entry.$1,
                onSelected: (_) => setState(() => _section = entry.$1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToday() {
    final tasks = _todayTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今日进行中', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _buildCarousel(tasks),
      ],
    );
  }

  Widget _buildCarousel(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      return const _EmptyState(
        icon: Icons.wb_sunny_outlined,
        message: '今天没有需要完成的任务',
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _todayCarouselController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tasks.length,
            onPageChanged: (index) => setState(() => _carouselIndex = index),
            itemBuilder: (context, index) => _TodayTaskCard(
              task: tasks[index],
              onTap: () => _showTaskDetails(tasks[index]),
              onComplete: () => _completeTask(tasks[index]),
              canComplete: tasks[index]['kind'] == '特殊任务'
                  ? _specialStatus(tasks[index]) == '进行中'
                  : tasks[index]['status_tag'] == '进行中' &&
                        _dailyClaimableToday(tasks[index]) &&
                        !_dailyRewardClaimedToday(tasks[index]),
              dailyRewardClaimedToday:
                  tasks[index]['kind'] == '日常任务' &&
                  _dailyRewardClaimedToday(tasks[index]),
            ),
          ),
        ),
        if (tasks.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              tasks.length,
              (index) => Container(
                width: index == _carouselIndex ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
                decoration: BoxDecoration(
                  color: index == _carouselIndex
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpecial() {
    final filtered = _specialTasks.where((task) {
      if (_specialFolder == '已结束') {
        if (_endedTaskFilter == '已完成') return task['status_tag'] == '已完成';
        return task['status_tag'] != '已完成' && _specialStatus(task) == '已结束';
      }
      return _specialStatus(task) == _specialFolder;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFolderTabs(
          const ['进行中', '未开始', '已结束'],
          _specialFolder,
          (folder) => setState(() => _specialFolder = folder),
        ),
        if (_specialFolder == '已结束')
          _buildFolderTabs(
            const ['未完成', '已完成'],
            _endedTaskFilter,
            (filter) => setState(() => _endedTaskFilter = filter),
          ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const _EmptyState(icon: Icons.event_busy_outlined, message: '此分类暂无任务')
        else
          ...filtered.map(_buildTaskTile),
      ],
    );
  }

  Widget _buildDaily() {
    final filtered = _dailyTasks
        .where((task) => task['status_tag'] == _dailyStatus)
        .where(
          (task) =>
              _dailyTagFilter == null || task['task_tag_id'] == _dailyTagFilter,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDailyStatusTabs(),
        const SizedBox(height: 8),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('全部 (${_dailyTasks.length})'),
                  selected: _dailyTagFilter == null,
                  onSelected: (_) => setState(() => _dailyTagFilter = null),
                ),
              ),
              for (final tag in _dailyTags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${tag['name']} (${_dailyTasks.where((task) => task['task_tag_id'] == tag['id']).length})',
                    ),
                    selected: _dailyTagFilter == tag['id'],
                    onSelected: (_) =>
                        setState(() => _dailyTagFilter = tag['id'] as int),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          _EmptyState(icon: Icons.repeat, message: '此标签暂无$_dailyStatus日常任务')
        else
          ...filtered.map(_buildTaskTile),
      ],
    );
  }

  Future<void> _setDailyStatus(Map<String, dynamic> task, String status) async {
    try {
      await TaskRepository.instance.setDailyStatus(task['id'] as int, status);
      await _loadTasks();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新日常任务状态失败：$error')));
      }
    }
  }

  Widget _buildDailyStatusTabs() => SizedBox(
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final status in const ['未开始', '进行中', '已完成'])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                '$status (${_dailyTasks.where((task) => task['status_tag'] == status).length})',
              ),
              selected: _dailyStatus == status,
              onSelected: (_) => setState(() => _dailyStatus = status),
            ),
          ),
      ],
    ),
  );

  String _specialStatus(Map<String, dynamic> task) {
    final storedStatus = task['status_tag'] as String? ?? '未开始';
    if (storedStatus == '已完成') return storedStatus;
    if (storedStatus == '未完成') return '已结束';
    final start = DateTime.tryParse('${task['start_time']}');
    final end = DateTime.tryParse('${task['end_time']}');
    if (start == null || end == null) return storedStatus;
    final now = DateTime.now();
    if (now.isBefore(start)) return '未开始';
    if (now.isAfter(end)) return '已结束';
    return '进行中';
  }

  Widget _buildFolderTabs(
    List<String> folders,
    String selected,
    ValueChanged<String> onSelected,
  ) => SizedBox(
    height: 46,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final folder in folders)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                '$folder (${_specialTasks.where((task) {
                  if (folder == '已完成') return task['status_tag'] == '已完成';
                  if (folder == '未完成') {
                    return task['status_tag'] != '已完成' && _specialStatus(task) == '已结束';
                  }
                  if (folder == '已结束') return _specialStatus(task) == '已结束';
                  return _specialStatus(task) == folder;
                }).length})',
              ),
              selected: folder == selected,
              onSelected: (_) => onSelected(folder),
            ),
          ),
      ],
    ),
  );

  Widget _buildTaskTile(Map<String, dynamic> task) {
    final isSpecial = task['kind'] == '特殊任务';
    final status = isSpecial
        ? _specialStatus(task)
        : task['status_tag'] as String;
    final isHabit = !isSpecial && _isHabitTask(task);
    final rewardClaimedToday = !isSpecial && _dailyRewardClaimedToday(task);
    final claimDue = !isSpecial && _dailyClaimableToday(task);
    final completed = isSpecial && status == '已完成';
    final canComplete =
        status == '进行中' && (isSpecial || (!rewardClaimedToday && claimDue));
    return ListTile(
      onTap: () => _showTaskDetails(task),
      leading: IconButton(
        tooltip: completed
            ? '已完成'
            : rewardClaimedToday
            ? '今日奖励已领取'
            : isSpecial
            ? '完成任务'
            : claimDue
            ? '领取今日奖励'
            : (isHabit ? '今天非打卡日' : '未到复习日期'),
        onPressed: canComplete ? () => _completeTask(task) : null,
        icon: Icon(
          completed || rewardClaimedToday
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
        ),
      ),
      title: Text(
        task['name'] as String,
        style: TextStyle(
          decoration: completed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${isHabit ? '${_repeatRuleOf(task).displayText} · ' : ''}${task['tag_name'] ?? '未分类'} · ${task['content'] ?? '暂无内容'} · ${rewardClaimedToday ? '今日已领取' : '每日 +${toInt(task[isSpecial ? 'reward_points' : 'daily_points'])} 分'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSpecial && status == '未开始')
            FilledButton.tonalIcon(
              onPressed: () => _startSpecialTask(task),
              icon: const Icon(Icons.play_arrow, size: 14),
              label: const Text('开始', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 28),
              ),
            ),
          if (!isSpecial)
            PopupMenuButton<String>(
              tooltip: '更改任务状态',
              onSelected: (value) => _setDailyStatus(task, value),
              itemBuilder: (context) => [
                for (final nextStatus in const ['未开始', '进行中', '已完成'])
                  if (nextStatus != status)
                    PopupMenuItem(
                      value: nextStatus,
                      child: Text(switch (nextStatus) {
                        '未开始' => '设为未开始',
                        '进行中' => '开始任务',
                        _ => '标记已完成',
                      }),
                    ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          if (isSpecial && status == '已结束')
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'close_expired') {
                  _closeExpiredSpecialTask(task);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'close_expired',
                  child: Text('补标记完成（不计积分）'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          IconButton(
            tooltip: '删除任务',
            onPressed: () => _deleteTask(task),
            icon: const Icon(Icons.delete_outline),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _TodayTaskCard extends StatelessWidget {
  const _TodayTaskCard({
    required this.task,
    required this.onTap,
    required this.onComplete,
    required this.canComplete,
    required this.dailyRewardClaimedToday,
  });

  final Map<String, dynamic> task;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final bool canComplete;
  final bool dailyRewardClaimedToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSpecial = task['kind'] == '特殊任务';
    final accentColor = isSpecial ? colorScheme.tertiary : colorScheme.primary;
    final rewardPoints = toInt(
      task[isSpecial ? 'reward_points' : 'daily_points'],
    );
    final penaltyPoints = toInt(task['penalty_points']);
    final tagName = task['tag_name'] as String? ?? '未分类';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: accentColor.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accentColor, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        task['kind'] as String,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tagName,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const Spacer(),
                    if (dailyRewardClaimedToday)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '已领取',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      )
                    else if (canComplete)
                      SizedBox(
                        height: 30,
                        child: FilledButton.tonalIcon(
                          onPressed: onComplete,
                          icon: const Icon(Icons.check, size: 16),
                          label: Text(
                            isSpecial ? '完成' : '领取',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 30),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  task['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  task['content'] as String? ?? '点击查看详细内容',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (rewardPoints > 0) ...[
                      Icon(Icons.stars, size: 14, color: Colors.amber[700]),
                      const SizedBox(width: 3),
                      Text(
                        '+$rewardPoints',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.amber[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (penaltyPoints > 0) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.remove_circle_outline,
                        size: 14,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '-$penaltyPoints',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (isSpecial)
                      _buildTimeInfo(context, colorScheme)
                    else
                      _buildReviewStageInfo(context, colorScheme),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo(BuildContext context, ColorScheme colorScheme) {
    final start = DateTime.tryParse('${task['start_time']}');
    final end = DateTime.tryParse('${task['end_time']}');
    if (start == null || end == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final totalDuration = end.difference(start).inDays;
    final elapsed = now.difference(start).inDays;
    final remaining = (totalDuration - elapsed).clamp(0, totalDuration);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.hourglass_bottom,
          size: 13,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          '剩余 $remaining 天',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildReviewStageInfo(BuildContext context, ColorScheme colorScheme) {
    final stage = toInt(task['review_stage']);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.repeat, size: 13, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '第 ${stage + 1} 次复习',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
