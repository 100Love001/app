import 'dart:async';

import 'package:app/routes/app_routes.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/home/home_repository.dart';
import 'package:app/stores/home/quote_repository.dart';
import 'package:app/stores/home/time_capsule_repository.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/viewmodels/home/home_view_model.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenTasks});

  final VoidCallback? onOpenTasks;

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

  void _openRoute(String route) {
    Navigator.pushNamed(context, route).then((_) {
      if (mounted) unawaited(vm.refreshData());
    });
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
          .map((task) => {...task, 'kind': '特殊任务'});
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
      if (!mounted) return;
      setState(() {
        _pointsBalance = result[0] as int;
        _todayTasks = [...specialTasks, ...dailyTasks];
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
                    onTap: () => _openRoute(AppRoutes.anniversaries),
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
                          Flexible(
                            child: Text(
                              nearestAnniversary == null
                                  ? '添加纪念日'
                                  : '${nearestAnniversary.title} · '
                                        '${_anniversaryCountdown(nearestAnniversary)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
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
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(child: _buildTodayTasksCard(context)),
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

  String _anniversaryCountdown(HomeAnniversary anniversary) {
    final days = anniversary.daysUntil(DateTime.now());
    if (days <= 0) return '今天';
    if (days == 1) return '明天';
    return '还有 $days 天';
  }

  Widget _buildPointsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('home-points-balance'),
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.stars_rounded,
          color: scheme.onPrimaryContainer,
          size: 28,
        ),
        title: Text(
          '当前积分总数',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        subtitle: Text(
          _overviewError != null
              ? '积分读取失败：$_overviewError'
              : _overviewLoading
              ? '正在读取…'
              : '${_pointsBalance ?? 0} 分',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: scheme.onPrimaryContainer,
        ),
        onTap: widget.onOpenTasks,
      ),
    );
  }

  Widget _buildTodayTasksCard(BuildContext context) {
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
              else if (_todayTasks.isEmpty)
                Text('今天没有任务', style: Theme.of(context).textTheme.bodySmall)
              else
                for (final task in _todayTasks.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '• ${task['name'] ?? '未命名任务'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              if (_todayTasks.length > 4 && !_overviewLoading)
                Text(
                  '还有 ${_todayTasks.length - 4} 项',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
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

class _CarouselSection<T> extends StatefulWidget {
  const _CarouselSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.items,
    required this.emptyMessage,
    required this.emptyHint,
    required this.itemBuilder,
    required this.onViewAll,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<T> items;
  final String emptyMessage;
  final String emptyHint;
  final Widget Function(BuildContext, T) itemBuilder;
  final VoidCallback onViewAll;

  @override
  State<_CarouselSection<T>> createState() => _CarouselSectionState<T>();
}

class _CarouselSectionState<T> extends State<_CarouselSection<T>> {
  final PageController _controller = PageController(viewportFraction: 0.91);
  int _page = 0;
  Timer? _autoAdvanceTimer;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _configureAutoAdvance();
  }

  @override
  void didUpdateWidget(covariant _CarouselSection<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      _configureAutoAdvance();
    }
  }

  void _configureAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (widget.items.length < 2) return;
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted ||
          !_controller.hasClients ||
          widget.items.length < 2 ||
          _animating) {
        return;
      }
      _animating = true;
      final nextPage = (_page + 1) % widget.items.length;
      _controller
          .animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          )
          .then((_) => _animating = false);
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.isEmpty ? 1 : widget.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(widget.icon, color: widget.accent, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    widget.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: widget.onViewAll, child: const Text('查看全部')),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: widget.items.isEmpty
                  ? _EmptySlide(
                      icon: widget.icon,
                      title: widget.emptyMessage,
                      hint: widget.emptyHint,
                    )
                  : widget.itemBuilder(context, widget.items[index]),
            ),
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 17 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? widget.accent
                        : widget.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.68,
    ),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

class _EmptySlide extends StatelessWidget {
  const _EmptySlide({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => _SlideCard(
    accent: Theme.of(context).colorScheme.primary,
    child: Row(
      children: [
        Icon(icon, size: 35, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
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
