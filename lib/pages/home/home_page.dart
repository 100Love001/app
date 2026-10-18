import 'dart:async';

import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/home/home_repository.dart';
import 'package:app/stores/home/quote_repository.dart';
import 'package:app/stores/home/time_capsule_repository.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_component_repository.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/task_component.dart';
import 'package:app/utils/time.dart';
import 'package:app/viewmodels/home/home_view_model.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onOpenTasks,
    this.onOpenHopes,
    this.onOpenPoints,
    this.onOpenAnniversaries,
  });

  final VoidCallback? onOpenTasks;

  /// 跳转到任务页并定位到希望清单分区。
  final VoidCallback? onOpenHopes;

  /// 跳转到财务页并定位到积分体系 tab。
  final VoidCallback? onOpenPoints;

  /// 跳转到记录页纪念日分区；参数表示是否进入后自动打开添加对话框。
  final ValueChanged<bool>? onOpenAnniversaries;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late final HomeViewModel vm;
  final AppSettingsController _settings = AppSettingsController.instance;
  Map<String, dynamic>? _quote;
  Object? _quoteError;
  List<Map<String, dynamic>> _unopenedCapsules = [];
  int? _pointsBalance;
  Object? _overviewError;
  bool _overviewLoading = true;
  List<Map<String, dynamic>> _todayTasks = [];
  WeightRecord? _latestWeight;
  MoodRecord? _latestMood;
  List<MoodCategory>? _moodCategories;

  @override
  void initState() {
    super.initState();
    vm = HomeViewModel();
    _settings.addListener(_onSettingsChanged);
    QuoteRepository.instance.addListener(_onQuotesChanged);
    TimeCapsuleRepository.instance.addListener(_onCapsulesChanged);
    unawaited(vm.refreshData());
    unawaited(_loadHomeOverview());
    unawaited(_loadQuote());
    unawaited(_loadCapsules());
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    QuoteRepository.instance.removeListener(_onQuotesChanged);
    TimeCapsuleRepository.instance.removeListener(_onCapsulesChanged);
    vm.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onQuotesChanged() => unawaited(_loadQuote());

  void _onCapsulesChanged() => unawaited(_loadCapsules());

  Future<void> _loadCapsules() async {
    try {
      final capsules = await TimeCapsuleRepository.instance.unopened();
      if (!mounted) return;
      setState(() => _unopenedCapsules = capsules);
    } catch (_) {
      // 礼物卡读取失败不阻塞首页其余内容。
    }
  }

  /// 开启最早一份已到期的特殊语录：展示全文并标记已开启，
  /// 若还有未开启的，礼物卡会继续留在首页等待下一次开启。
  Future<void> _openCapsule() async {
    if (_unopenedCapsules.isEmpty) return;
    final capsule = _unopenedCapsules.first;
    final opened = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.card_giftcard_rounded, size: 22),
            SizedBox(width: 8),
            Text('今天收到了一份特殊礼物'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                capsule['content'] as String,
                style: const TextStyle(height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                '写于 ${(capsule['create_time'] as String? ?? '').split(' ').first}'
                ' · 解锁于 ${capsule['unlock_date']}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('收下了'),
          ),
        ],
      ),
    );
    if (opened != true) return;
    try {
      await TimeCapsuleRepository.instance.markOpened(capsule['id'] as int);
    } catch (error) {
      _showMessage('开启失败：$error');
    }
  }

  Future<void> refresh() async {
    await Future.wait([vm.refreshData(), _loadHomeOverview()]);
  }

  Future<void> _loadQuote() async {
    try {
      final quote = await QuoteRepository.instance.randomQuote();
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoteError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _quoteError = error);
    }
  }

  Future<void> _showQuoteDialog() async {
    final quote = _quote;
    if (quote == null) {
      if (_quoteError != null) _showMessage('读取今日语录失败：$_quoteError');
      return;
    }
    final quoteId = quote['quote_id'] as int;
    late final List<Map<String, dynamic>> replies;
    try {
      replies = await QuoteRepository.instance.replies(quoteId);
    } catch (error) {
      _showMessage('读取语录回复失败：$error');
      return;
    }
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 520 ? screenWidth - 40 : 480.0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('今日语录'),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quote['content'] as String),
                if ((quote['author'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    '— ${quote['author']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                Text('喜欢 ${quote['like_count']} 次'),
                const Divider(height: 24),
                Text('回复 (${replies.length})'),
                if (replies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('还没有回复'),
                  )
                else
                  for (final reply in replies)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.chat_bubble_outline, size: 18),
                      title: Text(reply['content'] as String),
                      subtitle: Text(reply['create_time'] as String),
                    ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    unawaited(_replyToQuote(quoteId));
                  },
                  icon: const Icon(Icons.reply),
                  label: const Text('回复'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    try {
                      final updated = await QuoteRepository.instance.like(
                        quoteId,
                      );
                      if (!mounted) return;
                      setState(() => _quote = updated);
                      _showMessage('已添加喜欢值');
                    } catch (error) {
                      _showMessage('添加喜欢值失败：$error');
                    }
                  },
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('喜欢'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    unawaited(_setMottoFromQuote(quote['content'] as String));
                  },
                  icon: const Icon(Icons.push_pin_outlined),
                  label: const Text('设为座右铭'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _replyToQuote(int quoteId) async {
    final controller = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('回复今日语录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '写下你的想法'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存回复'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (reply == null || reply.isEmpty) return;
    try {
      await QuoteRepository.instance.addReply(quoteId, reply);
      if (mounted) _showMessage('回复已保存');
    } catch (error) {
      _showMessage('保存回复失败：$error');
    }
  }

  Future<void> _editMotto() async {
    final controller = TextEditingController(
      text: AppSettingsController.instance.personalMotto,
    );
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑专属座右铭'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '只会在你主动修改时改变'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (value == null) return;
    try {
      await AppSettingsController.instance.setPersonalMotto(value);
      if (mounted) _showMessage('座右铭已更新');
    } catch (error) {
      _showMessage('更新座右铭失败：$error');
    }
  }

  Future<void> _setMottoFromQuote(String quote) async {
    try {
      await AppSettingsController.instance.setPersonalMotto(quote);
      if (mounted) _showMessage('今日语录已设为座右铭');
    } catch (error) {
      _showMessage('设置座右铭失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshHome() async {
    await refresh();
  }

  Future<void> _loadHomeOverview() async {
    if (mounted) {
      setState(() {
        _overviewLoading = true;
        _overviewError = null;
      });
    }
    try {
      final result = await Future.wait<dynamic>([
        PointsService.getPointsBalance(),
        TaskRepository.instance.loadSpecialTasks(),
        TaskRepository.instance.loadDailyTasks(),
        TaskRepository.instance.loadLongTermTasks(),
        TaskComponentRepository.instance.latestWeight(),
        TaskComponentRepository.instance.latestMood(),
      ]);
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      bool isToday(Object? value) {
        final date = DateTime.tryParse('$value');
        return date != null &&
            date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
      }

      final specialTasks = (result[1] as List<Map<String, dynamic>>)
          .where((task) {
            if (task['status_tag'] != '进行中') return false;
            final start = DateTime.tryParse('${task['start_time']}');
            final end = DateTime.tryParse('${task['end_time']}');
            return start != null &&
                end != null &&
                !todayStart.isBefore(
                  DateTime(start.year, start.month, start.day),
                ) &&
                !todayStart.isAfter(DateTime(end.year, end.month, end.day));
          })
          .map((task) => {
            ...task,
            'kind': '特殊任务',
            'daily_points': task['reward_points'],
          });
      final dailyTasks = (result[2] as List<Map<String, dynamic>>)
          .where((task) {
            if (task['status_tag'] != '进行中') return false;
            if (task['task_mode'] == 'habit') {
              final start = DateTime.tryParse('${task['start_time']}');
              return start != null &&
                  RepeatRule.fromColumns(
                    task['repeat_type'] as String?,
                    task['repeat_value'] as String?,
                  ).isDueOn(today, start);
            }
            return isToday(task['next_review_time']) ||
                isToday(task['start_time']);
          })
          .map((task) => {...task, 'kind': '日常任务'});
      final longTasks = (result[3] as List<Map<String, dynamic>>)
          .where((task) {
            if (task['status'] == '已完成') return false;
            return isToday(task['deadline']);
          })
          .map((task) => {
            ...task,
            'kind': '长期任务',
            'id': task['task_id'],
            'name': task['title'],
            'daily_points': task['reward_points'],
          });
      if (!mounted) return;
      final latestMood = result[5] as MoodRecord?;
      // 心情标签联动任务组件的自定义类别（缺省回退 MoodLevel 五项）。
      final moodCategories = latestMood == null
          ? null
          : await TaskComponentRepository.instance.loadMoodCategories(
              taskKind: latestMood.taskKind,
              taskId: latestMood.taskId,
            );
      if (!mounted) return;
      setState(() {
        _pointsBalance = result[0] as int;
        _todayTasks = [...specialTasks, ...dailyTasks, ...longTasks];
        _latestWeight = result[4] as WeightRecord?;
        _latestMood = latestMood;
        _moodCategories = moodCategories;
        _overviewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _overviewError = error;
        _overviewLoading = false;
      });
    }
  }

  Future<void> _showCalendar() async {
    try {
      var month = DateTime(DateTime.now().year, DateTime.now().month);
      if (!mounted) return;
      DateTime? selectedDate;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final firstWeekday = DateTime(month.year, month.month).weekday;
            final dayCount = DateTime(month.year, month.month + 1, 0).day;
            return AlertDialog(
              title: Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () async {
                      final target = DateTime(month.year, month.month - 1);
                      if (!dialogContext.mounted) return;
                      month = target;
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(child: Text('${month.year}年${month.month}月')),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed:
                        month.year == DateTime.now().year &&
                            month.month == DateTime.now().month
                        ? null
                        : () async {
                            final target = DateTime(
                              month.year,
                              month.month + 1,
                            );
                            if (!dialogContext.mounted) return;
                            month = target;
                            setDialogState(() {});
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text(day),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (var week = 0; week < 6; week++)
                      Row(
                        children: [
                          for (var weekday = 0; weekday < 7; weekday++)
                            Builder(
                              builder: (context) {
                                final day =
                                    week * 7 + weekday - firstWeekday + 2;
                                if (day < 1 || day > dayCount) {
                                  return const Expanded(
                                    child: SizedBox(height: 42),
                                  );
                                }
                                final date = DateTime(
                                  month.year,
                                  month.month,
                                  day,
                                );
                                final isFuture = date.isAfter(DateTime.now());
                                return Expanded(
                                  child: InkWell(
                                    onTap: isFuture
                                        ? null
                                        : () {
                                            selectedDate = date;
                                            Navigator.pop(dialogContext);
                                          },
                                    borderRadius: BorderRadius.circular(22),
                                    child: SizedBox(
                                      height: 42,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '$day',
                                            style: TextStyle(
                                              color: isFuture
                                                  ? Theme.of(context)
                                                        .disabledColor
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '点选日期查看当天记录',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (selectedDate == null) return;
      if (!selectedDate!.isAfter(today)) {
        // 今天同样展示当日实时回顾；只有未来日期不可查看。
        await _showDaySummary(selectedDate!);
      } else {
        _showMessage('无法查看未来日期的回顾');
      }
    } catch (error) {
      _showMessage('读取月历失败：$error');
    }
  }

  /// E1：积分明细展示“动作+对象名”。新流水 remark 已含名称；
  /// 旧通用流水用反查的 source_name 补齐。
  String _pointRemarkSuffix(Map<String, dynamic> row) {
    final remark = (row['remark'] as String?)?.trim() ?? '';
    final sourceName = (row['source_name'] as String?)?.trim() ?? '';
    final text = remark.isNotEmpty
        ? (sourceName.isNotEmpty && !remark.contains(sourceName)
              ? '$remark（来源：$sourceName）'
              : remark)
        : (sourceName.isEmpty ? '' : '来源：$sourceName');
    return text.isEmpty ? '' : '（$text）';
  }

  Future<void> _showDaySummary(DateTime date) async {
    final db = await AppDatabase.instance.database;
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final finance = await db.query(
      'income_expenses',
      where: 'record_date = ?',
      whereArgs: [dateKey],
      orderBy: 'create_time DESC',
    );
    final points = await db.rawQuery(
      'SELECT p.*, ${PointsService.sourceNameColumn} AS source_name '
      'FROM points p WHERE substr(p.create_time, 1, 10) = ? '
      "ORDER BY REPLACE(p.create_time, 'T', ' ') DESC",
      [dateKey],
    );
    final balanceRows = await db.rawQuery(
      'SELECT COALESCE(SUM(point_value), 0) AS balance FROM points '
      'WHERE substr(create_time, 1, 10) <= ?',
      [dateKey],
    );
    final specialTasks = await db.query(
      'special_tasks',
      where: "status_tag = '已完成' AND substr(completed_at, 1, 10) = ?",
      whereArgs: [dateKey],
    );
    final dailyTasks = await db.rawQuery(
      'SELECT daily_tasks.name FROM daily_task_reward_logs '
      'JOIN daily_tasks ON daily_tasks.id = daily_task_reward_logs.task_id '
      'WHERE daily_task_reward_logs.reward_date = ?',
      [dateKey],
    );
    final hopes = await db.query(
      'hopes',
      where: "status = '已兑换' AND redeemed_at = ?",
      whereArgs: [dateKey],
    );
    if (!mounted) return;
    final income = finance
        .where((row) => row['type'] == '收入')
        .fold<double>(0, (sum, row) => sum + toDouble(row['amount']));
    final expense = finance
        .where((row) => row['type'] == '支出')
        .fold<double>(0, (sum, row) => sum + toDouble(row['amount']));
    final pointsDelta = points.fold<int>(
      0,
      (sum, row) => sum + toInt(row['point_value']),
    );
    final pointsBalance = toInt(balanceRows.first['balance']);
    final isToday =
        dateKey ==
        '${DateTime.now().year.toString().padLeft(4, '0')}-'
            '${DateTime.now().month.toString().padLeft(2, '0')}-'
            '${DateTime.now().day.toString().padLeft(2, '0')}';
    final completedTaskNames = [
      ...specialTasks.map((row) => row['name'] as String),
      ...dailyTasks.map((row) => row['name'] as String),
    ];
    final hopeNames = hopes.map((row) => row['name'] as String).toList();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(isToday ? Icons.today : Icons.history_toggle_off, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${date.year}年${date.month}月${date.day}日'
                '${isToday ? ' 今日回顾' : ' 回顾'}',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _summaryStat(
                            '收入',
                            '¥${income.toStringAsFixed(2)}',
                            Colors.green.shade700,
                            Icons.arrow_upward,
                          ),
                          const SizedBox(width: 12),
                          _summaryStat(
                            '支出',
                            '¥${expense.toStringAsFixed(2)}',
                            Colors.red.shade700,
                            Icons.arrow_downward,
                          ),
                          const SizedBox(width: 12),
                          _summaryStat(
                            '结余',
                            '¥${(income - expense).toStringAsFixed(2)}',
                            (income - expense) >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            Icons.account_balance_wallet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _summaryStat(
                            '积分余额',
                            '$pointsBalance',
                            Theme.of(context).colorScheme.primary,
                            Icons.stars,
                          ),
                          const SizedBox(width: 12),
                          _summaryStat(
                            '当日积分',
                            '${pointsDelta >= 0 ? '+' : ''}$pointsDelta',
                            pointsDelta >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            pointsDelta >= 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _detailSection(
                  '收支明细',
                  Icons.receipt_long,
                  finance.map(
                    (row) => _DetailItem(
                      label:
                          '${row['category']}'
                          '${(row['remark'] as String?)?.isNotEmpty == true ? '（${row['remark']}）' : ''}',
                      value:
                          '${row['type'] == '收入' ? '+' : '-'}¥${toDouble(row['amount']).toStringAsFixed(2)}',
                      valueColor: row['type'] == '收入'
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                  emptyText: '当日无收支记录',
                ),
                _detailSection(
                  '积分明细',
                  Icons.stars,
                  points.map(
                    (row) => _DetailItem(
                      label:
                          '${row['operation_type']}'
                          '${_pointRemarkSuffix(row)}',
                      value:
                          '${toInt(row['point_value']) >= 0 ? '+' : ''}${row['point_value']}',
                      valueColor: toInt(row['point_value']) >= 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                  emptyText: '当日无积分变动',
                ),
                _detailSection(
                  '完成任务',
                  Icons.task_alt,
                  completedTaskNames.map(
                    (name) => _DetailItem(
                      label: name,
                      value: '已完成',
                      valueColor: Colors.green.shade700,
                    ),
                  ),
                  emptyText: '当日无完成任务',
                ),
                _detailSection(
                  '兑换希望',
                  Icons.card_giftcard,
                  hopeNames.map(
                    (name) => _DetailItem(
                      label: name,
                      value: '已兑换',
                      valueColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  emptyText: '当日无兑换希望',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(
    String label,
    String value,
    Color valueColor,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: valueColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: valueColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _detailSection(
    String title,
    IconData icon,
    Iterable<_DetailItem> items, {
    String? emptyText,
  }) {
    final list = items.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${list.length}项',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                emptyText ?? '暂无',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.4),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: i == 0 ? 8 : 4,
                        bottom: i == list.length - 1 ? 8 : 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              list[i].label,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            list[i].value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: list[i].valueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, child) {
        final nearestAnniversary = vm.anniversaries.isEmpty
            ? null
            : vm.anniversaries.first;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                InkWell(
                  onTap: _showCalendar,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('今天', style: TextStyle(fontSize: 17)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              vm.currentDate,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.calendar_month_outlined, size: 15),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: InkWell(
                    key: const ValueKey('home-recent-anniversary'),
                    onTap: () {
                      // 无纪念日时进入后直接打开添加对话框，否则仅定位到纪念日分区。
                      // 跳转到记录页的纪念日分区，与首页其他入口的直达闭环一致。
                      widget.onOpenAnniversaries?.call(nearestAnniversary == null);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          // 标题可省略，日期（月日）独立渲染保证永远完整显示。
                          if (nearestAnniversary == null)
                            Text(
                              '添加纪念日',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelMedium,
                            )
                          else ...[
                            Flexible(
                              child: Text(
                                nearestAnniversary.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            Text(
                              ' · ${_anniversaryDateLabel(nearestAnniversary)}',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                _buildMottoLine(context),
                const SizedBox(height: 18),
                _buildQuoteCard(context),
                if (_unopenedCapsules.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildGiftCard(context),
                ],
                const SizedBox(height: 22),
                if (vm.error != null) ...[
                  _buildLoadError(context),
                  const SizedBox(height: 12),
                ],
                _buildPointsCard(context),
                if (vm.hopesInProgress.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildHopesCard(context),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTodayTasksCard(context)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildHealthCard(context)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 特殊礼物卡：有已到时间但尚未开启的特殊语录时展示，
  /// 点击逐条开启，全部开启后自动消失。
  Widget _buildGiftCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _unopenedCapsules.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: () => unawaited(_openCapsule()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                size: 30,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今天收到了一份特殊礼物',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 1 ? '共 $count 份，点击逐一开启' : '点击开启',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMottoLine(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            AppSettingsController.instance.personalMotto,
            key: const ValueKey('personal-motto'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '修改这句话',
          onPressed: _editMotto,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }

  Widget _buildQuoteCard(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => unawaited(_showQuoteDialog()),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.format_quote_rounded,
                color: Theme.of(context).colorScheme.secondary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日语录',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _quote?['content'] as String? ??
                          (_quoteError == null ? '正在读取今日语录…' : '今日语录暂不可用'),
                      style: const TextStyle(height: 1.5),
                    ),
                    if (((_quote?['like_count'] as int?) ?? 0) > 0) ...[
                      const SizedBox(height: 5),
                      Text(
                        '喜欢 ${_quote!['like_count']}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 首页顶部纪念日只显示月与日（如 10月25日），保证长标题下日期完整可见。
  String _anniversaryDateLabel(HomeAnniversary anniversary) {
    final date = anniversary.nextDate;
    return '${date.month}月${date.day}日';
  }

  Widget _buildPointsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = _overviewError != null || _overviewLoading
        ? '--'
        : '${_pointsBalance ?? 0}';
    return Card(
      key: const ValueKey('home-points-balance'),
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: widget.onOpenPoints,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前积分总数',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          balance,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '分',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                    if (_overviewError != null)
                      Text(
                        '积分读取失败，下拉重试',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 希望清单进行中卡片：展示正在推进的希望，名称在上、进度条在下，
  /// 点击进入任务页的希望清单分区。没有进行中的希望时整卡隐藏。
  Widget _buildHopesCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hopes = vm.hopesInProgress;
    return Card(
      key: const ValueKey('home-hopes-progress'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenHopes,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '希望清单 · 进行中',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${hopes.length} 项',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < hopes.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                  child: _buildHopeProgressRow(context, hopes[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单条进行中的希望：名称在上，当前进度（进度条 + 百分比）在下。
  Widget _buildHopeProgressRow(BuildContext context, HopeProgress hope) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hope.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${hope.progress}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: hope.progress / 100,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayTasksCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = _overviewError != null
        ? const <Map<String, dynamic>>[]
        : _todayTasks;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenTasks,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '今天的任务',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!_overviewLoading && tasks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${tasks.length} 项',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_overviewError != null)
                Text(
                  '任务读取失败：$_overviewError',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (_overviewLoading)
                Text('正在读取…', style: Theme.of(context).textTheme.bodySmall)
              else if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '今天没有任务，点击去创建一个吧',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                for (final task in tasks.take(4))
                  _buildTodayTaskRow(context, task),
              if (tasks.length > 4 && !_overviewLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '还有 ${tasks.length - 4} 项 · 点击查看全部',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 首页单条今日任务：类型图标 + 名称 + 奖励分 + 一键完成。
  Widget _buildTodayTaskRow(BuildContext context, Map<String, dynamic> task) {
    final scheme = Theme.of(context).colorScheme;
    final kind = task['kind'] as String? ?? '日常任务';
    final isHabit = kind == '日常任务' && task['task_mode'] == 'habit';
    final done = kind != '长期任务' && toInt(task['reward_claimed_today']) == 1;
    final points = toInt(task['daily_points']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            _taskKindIcon(kind, isHabit),
            size: 15,
            color: _taskKindColor(context, kind, isHabit),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${task['name'] ?? '未命名任务'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (points > 0 && !done) ...[
            const SizedBox(width: 4),
            Text(
              '+$points',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(width: 6),
          if (done)
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: Colors.green,
            )
          else
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                tooltip: kind == '长期任务' ? '标记完成' : '完成/打卡',
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(
                  Icons.check_circle_outline,
                  color: scheme.primary,
                ),
                onPressed: () => unawaited(_completeHomeTask(task)),
              ),
            ),
        ],
      ),
    );
  }

  IconData _taskKindIcon(String kind, bool isHabit) => switch (kind) {
    '特殊任务' => Icons.bolt_rounded,
    '长期任务' => Icons.flag_rounded,
    _ => isHabit ? Icons.repeat_rounded : Icons.event_repeat_rounded,
  };

  Color _taskKindColor(BuildContext context, String kind, bool isHabit) =>
      switch (kind) {
        '特殊任务' => Colors.orange.shade600,
        '长期任务' => Colors.purple.shade400,
        _ => isHabit ? Colors.teal.shade500 : Theme.of(context).colorScheme.primary,
      };

  /// 首页一键完成任务：与任务页完成逻辑一致，自动领取积分并返还逾期扣分。
  Future<void> _completeHomeTask(Map<String, dynamic> task) async {
    final kind = task['kind'] as String? ?? '日常任务';
    final id = toInt(task['id']);
    if (kind == '长期任务') {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('完成长期任务'),
          content: Text(
            '完成「${task['name'] ?? '长期任务'}」？完成后发放奖励积分，'
            '已扣除的逾期积分会自动返还。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('完成'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final reward = switch (kind) {
        '特殊任务' => await PointsService.completeSpecialTask(id),
        '长期任务' => await PointsService.completeLongTermTask(id),
        _ => task['task_mode'] == 'habit'
            ? await PointsService.claimHabitTaskReward(
                taskId: id,
                date: DateTime.now(),
              )
            : await PointsService.claimDailyTaskReward(
                taskId: id,
                date: DateTime.now(),
              ),
      };
      await _loadHomeOverview();
      if (!mounted) return;
      final message = reward == null
          ? (kind == '特殊任务' ? '任务已完成' : '今日奖励已领取，或任务当前不可领取')
          : reward > 0
          ? (kind == '长期任务'
                ? '长期任务完成，获得 $reward 积分（逾期扣分已返还）'
                : '完成成功，获得 $reward 积分')
          : '任务已完成';
      _showMessage(message);
    } catch (error) {
      _showMessage('更新任务失败：$error');
    }
  }

  /// 右侧健康卡：体重 + 心情最新值，支持一键快捷记录。
  Widget _buildHealthCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weight = _latestWeight;
    final mood = _latestMood;
    final moodLevel = MoodLevel.fromScore(mood?.level);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '体重 · 心情',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _buildHealthTile(
              context,
              icon: Icons.monitor_weight_outlined,
              iconColor: Colors.blue.shade500,
              label: '体重',
              value: _overviewLoading
                  ? '…'
                  : weight == null
                  ? '未记录'
                  : '${weight.weight.toStringAsFixed(1)} kg',
              hint: weight == null ? '点击录入' : weight.recordDate,
              onTap: _overviewLoading ? null : () => unawaited(_quickRecordWeight()),
            ),
            Divider(
              height: 16,
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
            _buildHealthTile(
              context,
              icon: moodLevel.icon,
              iconColor: _moodColor(moodLevel),
              label: '心情',
              value: _overviewLoading
                  ? '…'
                  : mood == null
                  ? '未记录'
                  : MoodCategory.labelFor(mood.level, _moodCategories),
              hint: mood == null ? '点击录入' : mood.recordDate,
              onTap: _overviewLoading ? null : () => unawaited(_quickRecordMood()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String hint,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _moodColor(MoodLevel level) => switch (level) {
    MoodLevel.veryLow || MoodLevel.low => Colors.red.shade400,
    MoodLevel.neutral => Colors.amber.shade600,
    _ => Colors.green.shade500,
  };

  /// 尚无任何体重/心情记录时，引导用户先在任务里添加对应组件。
  Future<void> _showRecordGuide(String componentLabel) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('还没有「$componentLabel」记录'),
        content: Text(
          '先在任务编辑器中给任意任务添加「$componentLabel」组件并录入一条数据，'
          '之后就可以在这里快捷记录了。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('去任务页'),
          ),
        ],
      ),
    );
    if (go == true && mounted) widget.onOpenTasks?.call();
  }

  /// 快捷记录体重：写入最近使用的体重任务（与趋势图同源）。
  Future<void> _quickRecordWeight() async {
    final target = _latestWeight;
    if (target == null) {
      await _showRecordGuide('体重记录');
      return;
    }
    final controller = TextEditingController(
      text: target.weight.toStringAsFixed(1),
    );
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('记录体重'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (target.taskName.isNotEmpty)
              Text(
                '将保存到任务「${target.taskName}」的体重曲线',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '今日体重（kg）',
                suffixText: 'kg',
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
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    final parsed = double.tryParse(value ?? '');
    if (parsed == null) return;
    if (parsed <= 0 || parsed > 600) {
      _showMessage('体重需在 0-600 kg 之间');
      return;
    }
    try {
      await TaskComponentRepository.instance.addWeight(
        taskKind: target.taskKind,
        taskId: target.taskId,
        recordDate: TimeUtil.toDateKey(DateTime.now()),
        weight: parsed,
      );
      await _loadHomeOverview();
      if (mounted) _showMessage('已记录今日体重 ${parsed.toStringAsFixed(1)} kg');
    } catch (error) {
      _showMessage('记录体重失败：$error');
    }
  }

  /// 快捷记录心情：按任务心情组件自定义类别（缺省 MoodLevel 五项）选择 + 可选备注，
  /// 写入最近使用的心情任务。
  Future<void> _quickRecordMood() async {
    final target = _latestMood;
    if (target == null) {
      await _showRecordGuide('心情记录');
      return;
    }
    final categories = await TaskComponentRepository.instance
        .loadMoodCategories(taskKind: target.taskKind, taskId: target.taskId);
    if (!mounted) return;
    var selected = categories.any((item) => item.score == target.level)
        ? target.level
        : categories[categories.length ~/ 2].score;
    final noteController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('记录心情'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (target.taskName.isNotEmpty)
                Text(
                  '将保存到任务「${target.taskName}」的情绪曲线',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in categories)
                    ChoiceChip(
                      label: Text(category.label),
                      selected: selected == category.score,
                      onSelected: (_) =>
                          setDialogState(() => selected = category.score),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '今天感觉怎么样？',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    final note = noteController.text;
    noteController.dispose();
    if (saved != true) return;
    try {
      await TaskComponentRepository.instance.addMood(
        taskKind: target.taskKind,
        taskId: target.taskId,
        recordDate: TimeUtil.toDateKey(DateTime.now()),
        level: selected,
        note: note,
      );
      await _loadHomeOverview();
      if (mounted) _showMessage('已记录今日心情');
    } catch (error) {
      _showMessage('记录心情失败：$error');
    }
  }

  Widget _buildLoadError(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: Icon(
          Icons.cloud_off_outlined,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        title: const Text('首页数据加载失败'),
        subtitle: Text('${vm.error}'),
        trailing: TextButton(
          onPressed: vm.refreshData,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _DetailItem {
  const _DetailItem({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;
}
