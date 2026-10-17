import 'dart:async';

import 'package:app/constants/app_constants.dart';
import 'package:app/pages/records/records_page.dart';
import 'package:app/pages/tasks/task_editor_page.dart';
import 'package:app/pages/tasks/task_trend_page.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_penalty_service.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/task_component.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _TaskSection { special, daily, longTerm, wishes, hopes }

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
  List<Map<String, dynamic>> _longTasks = [];
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
      // 统一逾期扣分扫描（4 类任务，幂等）：仅在实际产生新扣分时提示。
      final settled = await TaskPenaltyService.settleAll();
      final repo = TaskRepository.instance;
      final results = await Future.wait([
        repo.loadSpecialTasks(),
        repo.loadDailyTasks(),
        repo.loadDailyTags(),
        repo.loadLongTermTasks(),
      ]);
      if (!mounted) return;
      setState(() {
        _specialTasks = results[0];
        _dailyTasks = results[1];
        _dailyTags = results[2];
        _longTasks = results[3];
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
      // 逾期扣分通知必须在 syncSchedule 之后发送：同步内部会 cancelAll
      // 重建全部排程，提前发送的临时通知会被一并撤销而永远不可见。
      if (settled.isNotEmpty && mounted) {
        final total = settled.fold<int>(0, (sum, item) => sum + item.points);
        final message =
            '${settled.length} 个任务逾期未完成，已自动扣除 $total 积分（补完成将自动返还）';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        await LocalNotificationService.instance.showInfo(
          title: '任务逾期扣分',
          body: message,
        );
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
    final long = _longTasks
        .where((task) {
          if (task['status'] == '已完成') return false;
          return isToday(task['deadline'] as String?);
        })
        .map((task) => {
          ...task,
          'kind': '长期任务',
          'name': task['title'],
          'tag_name': (task['tag'] as String?)?.trim().isNotEmpty == true
              ? task['tag']
              : '未分类',
          'daily_points': task['reward_points'],
        });
    return [...special, ...daily, ...long];
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

  /// 打开动态组件任务编辑器；保存成功后刷新列表。
  Future<void> _openEditor(
    TaskType type, {
    Map<String, dynamic>? existing,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskEditorPage(
          args: TaskEditorArgs(type: type, existing: existing),
        ),
      ),
    );
    if (saved == true && mounted) await _loadTasks();
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
    final componentDoc = TaskComponentDocument.decode(
      task['component_json'] as String?,
    );
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
                  if (componentDoc.has(ComponentType.weight))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'weight'),
                      icon: const Icon(Icons.monitor_weight_outlined),
                      label: const Text('体重趋势'),
                    ),
                  if (componentDoc.has(ComponentType.mood))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'mood'),
                      icon: const Icon(Icons.mood_outlined),
                      label: const Text('心情趋势'),
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
        await _openEditor(
          isSpecial
              ? TaskType.shortTerm
              : _isHabitTask(task)
              ? TaskType.habit
              : TaskType.daily,
          existing: task,
        );
        break;
      case 'history':
        if (!isSpecial) await _showDailyTaskHistory(task);
        break;
      case 'weight':
      case 'mood':
        await _openTrend(
          taskKind: isSpecial ? 'special' : 'daily',
          taskId: toInt(task['id']),
          taskTitle: '${task['name']}',
          metric: action == 'weight' ? TrendMetric.weight : TrendMetric.mood,
        );
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
            _section == _TaskSection.special ||
                _section == _TaskSection.daily ||
                _section == _TaskSection.longTerm
            ? [
                PopupMenuButton<TaskType>(
                  tooltip: '添加任务',
                  onSelected: (type) => _openEditor(type),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: TaskType.shortTerm,
                      child: Text('添加特殊任务'),
                    ),
                    PopupMenuItem(
                      value: TaskType.daily,
                      child: Text('添加日常任务'),
                    ),
                    PopupMenuItem(
                      value: TaskType.habit,
                      child: Text('添加习惯任务'),
                    ),
                    PopupMenuItem(
                      value: TaskType.longTerm,
                      child: Text('添加长期任务'),
                    ),
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
                        if (_section == _TaskSection.longTerm) _buildLongTerm(),
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
            (_TaskSection.longTerm, '长期任务'),
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
              onTap: () => tasks[index]['kind'] == '长期任务'
                  ? _showLongTaskDetails(tasks[index])
                  : _showTaskDetails(tasks[index]),
              onComplete: () => tasks[index]['kind'] == '长期任务'
                  ? _completeLongTask(tasks[index])
                  : _completeTask(tasks[index]),
              canComplete: tasks[index]['kind'] == '特殊任务'
                  ? _specialStatus(tasks[index]) == '进行中'
                  : tasks[index]['kind'] == '长期任务'
                  ? tasks[index]['status'] != '已完成'
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
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ================= 长期任务（tasks 表 task_type='long'）=================

  /// 长期任务是否已逾期（开启扣分且过截止时间未完成）。
  bool _longOverdue(Map<String, dynamic> task) {
    if (task['status'] == '已完成') return false;
    if (toInt(task['enable_penalty'] ?? 1) != 1) return false;
    if (toInt(task['penalty_points']) <= 0) return false;
    final deadline = DateTime.tryParse('${task['deadline']}');
    return deadline != null && deadline.isBefore(DateTime.now());
  }

  /// 复习型日常任务是否处于逾期窗口（与扣分服务口径一致：逾期 > 1 天）。
  bool _dailyOverdue(Map<String, dynamic> task) {
    if (_isHabitTask(task)) return false;
    if (task['status_tag'] != '进行中') return false;
    if (toInt(task['enable_penalty'] ?? 1) != 1) return false;
    if (toInt(task['penalty_points']) <= 0) return false;
    final review = DateTime.tryParse('${task['next_review_time']}');
    if (review == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(
      DateTime(review.year, review.month, review.day),
    ).inDays > 1;
  }

  /// 特殊任务是否已逾期未完成。
  bool _specialOverdue(Map<String, dynamic> task) =>
      task['status_tag'] != '已完成' &&
      toInt(task['enable_penalty'] ?? 1) == 1 &&
      toInt(task['penalty_points']) > 0 &&
      _specialStatus(task) == '已结束';

  Widget _buildLongTerm() {
    if (_longTasks.isEmpty) {
      return const _EmptyState(
        icon: Icons.flag_outlined,
        message: '暂无长期任务，点击右上角 + 添加',
      );
    }
    final active = _longTasks
        .where((task) => task['status'] != '已完成')
        .toList();
    final finished = _longTasks
        .where((task) => task['status'] == '已完成')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final task in active) _buildLongTaskTile(task),
        if (finished.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('已完成', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final task in finished) _buildLongTaskTile(task),
        ],
      ],
    );
  }

  Widget _buildLongTaskTile(Map<String, dynamic> task) {
    final completed = task['status'] == '已完成';
    final overdue = !completed && _longOverdue(task);
    final deadline = DateTime.tryParse('${task['deadline']}');
    final titleColor = overdue
        ? Theme.of(context).colorScheme.error
        : null;
    return ListTile(
      onTap: () => _showLongTaskDetails(task),
      leading: IconButton(
        tooltip: completed ? '已完成' : '完成长期任务',
        onPressed: completed ? null : () => _completeLongTask(task),
        icon: Icon(
          completed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: overdue && !completed
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      ),
      title: Row(
        children: [
          if (overdue)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          Expanded(
            child: Text(
              '${task['title']}',
              style: TextStyle(
                color: titleColor,
                decoration: completed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '截止 ${deadline == null ? '未设置' : DateFormat('yyyy-MM-dd HH:mm').format(deadline)}'
        ' · ${(task['tag'] as String?)?.trim().isNotEmpty == true ? task['tag'] : '未分类'}'
        ' · 奖励 +${toInt(task['reward_points'])} 分'
        '${overdue ? ' · 逾期扣 ${toInt(task['penalty_points'])} 分' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: overdue
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '更多操作',
        onSelected: (value) async {
          switch (value) {
            case 'edit':
              await _openEditor(TaskType.longTerm, existing: task);
            case 'delete':
              await _deleteLongTask(task);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  Future<void> _completeLongTask(Map<String, dynamic> task) async {
    try {
      final reward = await PointsService.completeLongTermTask(
        toInt(task['task_id']),
      );
      await _loadTasks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reward == null
                ? '任务已完成'
                : reward > 0
                ? '长期任务完成，获得 $reward 积分（逾期扣分已返还）'
                : '长期任务已完成',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
    }
  }

  Future<void> _deleteLongTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('删除长期任务'),
        content: Text('确定删除“${task['title']}”吗？子任务与体重/心情记录会一并删除。'),
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
    if (confirmed != true) return;
    try {
      await TaskRepository.instance.deleteLongTermTask(toInt(task['task_id']));
      await _loadTasks();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除任务失败：$error')));
    }
  }

  Future<void> _showLongTaskDetails(Map<String, dynamic> task) async {
    final doc = TaskComponentDocument.decode(
      task['component_json'] as String?,
    );
    final deadline = DateTime.tryParse('${task['deadline']}');
    final completed = task['status'] == '已完成';
    final overdue = !completed && _longOverdue(task);
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
                '${task['title']}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 12),
              const _DetailLine(label: '任务类型', value: '长期任务'),
              _DetailLine(
                label: '任务标签',
                value: (task['tag'] as String?)?.trim().isNotEmpty == true
                    ? '${task['tag']}'
                    : '未分类',
              ),
              _DetailLine(
                label: '当前状态',
                value: completed
                    ? '已完成'
                    : overdue
                    ? '已逾期（已扣 ${toInt(task['penalty_points'])} 积分/待扣）'
                    : '${task['status'] ?? '进行中'}',
              ),
              _DetailLine(
                label: '截止时间',
                value: deadline == null
                    ? '未设置'
                    : DateFormat('yyyy-MM-dd HH:mm').format(deadline),
              ),
              _DetailLine(
                label: '完成奖励',
                value: '${toInt(task['reward_points'])} 积分',
              ),
              if (toInt(task['penalty_points']) > 0)
                _DetailLine(
                  label: '逾期扣分',
                  value:
                      '${toInt(task['penalty_points'])} 积分'
                      '（${toInt(task['enable_penalty'] ?? 1) == 1 ? '已开启' : '已关闭'}）',
                ),
              if ((task['note'] as String?)?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text('${task['note']}'),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: completed
                      ? null
                      : () => Navigator.pop(context, 'complete'),
                  icon: const Icon(Icons.check),
                  label: Text(completed ? '已完成' : '完成任务'),
                ),
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
                  if (doc.has(ComponentType.weight))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'weight'),
                      icon: const Icon(Icons.monitor_weight_outlined),
                      label: const Text('体重趋势'),
                    ),
                  if (doc.has(ComponentType.mood))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'mood'),
                      icon: const Icon(Icons.mood_outlined),
                      label: const Text('心情趋势'),
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
        await _completeLongTask(task);
      case 'edit':
        await _openEditor(TaskType.longTerm, existing: task);
      case 'delete':
        await _deleteLongTask(task);
      case 'weight':
      case 'mood':
        await _openTrend(
          taskKind: 'long',
          taskId: toInt(task['task_id']),
          taskTitle: '${task['title']}',
          metric: action == 'weight' ? TrendMetric.weight : TrendMetric.mood,
        );
      case null:
        break;
    }
  }

  Future<void> _openTrend({
    required String taskKind,
    required int taskId,
    required String taskTitle,
    required TrendMetric metric,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskTrendPage(
          taskKind: taskKind,
          taskId: taskId,
          taskTitle: taskTitle,
          metric: metric,
        ),
      ),
    );
    await _loadTasks();
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
    final overdue = isSpecial
        ? _specialOverdue(task)
        : _dailyOverdue(task);
    final overdueColor = Theme.of(context).colorScheme.error;
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
              : overdue
              ? Icons.error_outline
              : Icons.radio_button_unchecked,
          color: overdue ? overdueColor : null,
        ),
      ),
      title: Text(
        task['name'] as String,
        style: TextStyle(
          color: overdue ? overdueColor : null,
          decoration: completed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${isHabit ? '${_repeatRuleOf(task).displayText} · ' : ''}${task['tag_name'] ?? '未分类'} · ${task['content'] ?? '暂无内容'} · ${rewardClaimedToday ? '今日已领取' : '每日 +${toInt(task[isSpecial ? 'reward_points' : 'daily_points'])} 分'}${overdue ? ' · 已逾期' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: overdue ? TextStyle(color: overdueColor) : null,
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
                            isSpecial || task['kind'] == '长期任务'
                                ? '完成'
                                : '领取',
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
                    else if (task['kind'] == '长期任务')
                      _buildDeadlineInfo(context, colorScheme)
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
    // 小时粒度计算：同日起止（如 8:00-22:00）用天会恒显示“剩余 0 天”。
    final totalHours = end.difference(start).inHours;
    if (totalHours <= 0) return const SizedBox.shrink();
    final elapsed = now.difference(start).inHours;
    final remaining = (totalHours - elapsed).clamp(0, totalHours);
    final label = remaining >= 24
        ? '剩余 ${remaining ~/ 24} 天'
        : '剩余 $remaining 小时';
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
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 长期任务没有复习阶段概念，今日卡片展示截止信息。
  /// 今日卡片仅包含截止日为今天的长期任务。
  Widget _buildDeadlineInfo(BuildContext context, ColorScheme colorScheme) {
    final deadline = DateTime.tryParse('${task['deadline']}');
    if (deadline == null) return const SizedBox.shrink();
    final hasTime = deadline.hour != 0 || deadline.minute != 0;
    final label = hasTime
        ? '今天 ${deadline.hour.toString().padLeft(2, '0')}:'
            '${deadline.minute.toString().padLeft(2, '0')} 截止'
        : '今天截止';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event, size: 13, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
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
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color.withValues(alpha: 0.55)),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
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
