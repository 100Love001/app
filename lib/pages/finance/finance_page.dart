import 'dart:async';

import 'package:app/pages/finance/finance_category_management_page.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/finance/finance_repository.dart';
import 'package:app/utils/budget_period.dart';
import 'package:app/utils/csv_exporter.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  FinancePageState createState() => FinancePageState();
}

class FinancePageState extends State<FinancePage> {
  int _tab = 0;
  bool _loading = true;
  String? _error;
  double _balance = 0;
  final Map<String, double> _categoryTotals = {};
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _pointRecordsAll = [];
  // 积分明细查看的月份偏移：0=本月、1=上月…；null=全部流水。
  int? _pointMonthOffset = 0;
  List<Map<String, dynamic>> _categories = [];
  int _points = 0;
  int _monthPointIncome = 0;
  int _monthPointExpense = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void refresh() {
    if (!_loading) unawaited(_loadData());
  }

  /// 供首页积分卡直达积分体系 tab。
  void showPoints() {
    setState(() => _tab = 1);
  }

  String _date(DateTime value) => TimeUtil.toDateKey(value);

  /// 导出 CSV：账单或积分流水，生成后调起系统分享，
  /// 用户可保存到手机存储或发送给他人。
  Future<void> _exportCsv({required bool pointsFlow}) async {
    final rows = pointsFlow ? _pointRecordsAll : _records;
    if (_loading || rows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可导出的数据')));
      return;
    }
    try {
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      if (pointsFlow) {
        await CsvExporter.shareCsv(
          fileName: '积分流水_$stamp.csv',
          subject: '生活手账积分流水',
          rows: [
            ['时间', '动作', '对象', '积分变动', '说明'],
            for (final record in rows)
              [
                CsvExporter.normalizeTime(record['create_time']),
                '${record['operation_type'] ?? ''}',
                '${record['source_name'] ?? ''}',
                toInt(record['point_value']),
                '${record['remark'] ?? ''}',
              ],
          ],
        );
      } else {
        await CsvExporter.shareCsv(
          fileName: '收支账单_$stamp.csv',
          subject: '生活手账收支账单',
          rows: [
            ['记账日期', '类型', '分类', '金额', '备注', '抵扣积分', '创建时间'],
            for (final record in rows)
              [
                '${record['record_date'] ?? ''}',
                '${record['type'] ?? ''}',
                '${record['category'] ?? ''}',
                toDouble(record['amount']).toStringAsFixed(2),
                '${record['remark'] ?? ''}',
                toInt(record['points_deducted']),
                CsvExporter.normalizeTime(record['create_time']),
              ],
          ],
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成 CSV（共 ${rows.length} 条）')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    }
  }

  /// 进入财务页时结算所有支出分类「已结束周期」的结余/超支积分。
  /// 单分类失败不阻断页面加载（结算记录未写入，下次进入自动重试）。
  Future<void> _settleExpiredBudgets(DateTime now) async {
    try {
      await PointsService.settleCategoryBudgets(now);
    } catch (_) {
      // deliberately ignored: 保持页面可用，等待下次启动重试
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      await _settleExpiredBudgets(now);
      final repo = FinanceRepository.instance;
      final results = await Future.wait([
        repo.loadRecords(),
        repo.loadCategories(),
        repo.loadPointRecords(),
      ]);
      final records = results[0];
      final categories = results[1];
      final pointRecords = results[2];
      // 支出分类配置：卡片与统计只展示仍存在的分类；
      // 分类被删除后历史账单保留文本名称，但不再出现在预算卡片区。
      final configsByName = <String, Map<String, dynamic>>{
        for (final category in categories)
          if (category['type'] == '支出')
            category['name'] as String: category,
      };
      double income = 0;
      double expense = 0;
      int totalPoints = 0;
      var monthPointIncome = 0;
      var monthPointExpense = 0;
      final categoryTotals = <String, double>{};
      for (final record in records) {
        final amount = toDouble(record['amount']);
        if (record['type'] == '收入') {
          income += amount;
        } else {
          expense += amount;
          final config = configsByName[record['category']];
          final periodType = config?['period_type'] as String?;
          final date = DateTime.tryParse('${record['record_date']}');
          // 统计该分类「当前周期」已花金额；历史自动饭钱记录不参与统计。
          if (config != null &&
              periodType != null &&
              BudgetPeriods.isSettled(periodType) &&
              date != null &&
              BudgetPeriods.startOf(periodType, date) ==
                  BudgetPeriods.startOf(periodType, now) &&
              record['remark'] != '自动添加每日饭钱') {
            final category = record['category'] as String;
            categoryTotals[category] =
                (categoryTotals[category] ?? 0) + amount;
          }
        }
      }
      for (final record in pointRecords) {
        final value = toInt(record['point_value']);
        totalPoints += value;
        final createdAt = DateTime.tryParse('${record['create_time']}');
        if (createdAt != null &&
            createdAt.year == now.year &&
            createdAt.month == now.month) {
          if (value > 0) {
            monthPointIncome += value;
          } else {
            monthPointExpense += -value;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _balance = income - expense;
        _categoryTotals
          ..clear()
          ..addAll(categoryTotals);
        _records = records;
        _categories = categories;
        // 保留全部流水，由月份切换器在展示层过滤。
        _pointRecordsAll = pointRecords;
        _points = totalPoints;
        _monthPointIncome = monthPointIncome;
        _monthPointExpense = monthPointExpense;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '财务数据加载失败：$error';
      });
    }
  }

  Future<void> _showRecordEditor({Map<String, dynamic>? record}) async {
    final amountController = TextEditingController(
      text: record == null ? '' : toDouble(record['amount']).toStringAsFixed(2),
    );
    final remarkController = TextEditingController(
      text: record?['remark'] as String? ?? '',
    );
    final pointsController = TextEditingController();
    String type = record?['type'] as String? ?? '支出';
    final initialCategories = _categories
        .where((item) => item['type'] == type)
        .map((item) => item['name'] as String)
        .toList();
    String category =
        record?['category'] as String? ??
        (initialCategories.isEmpty ? '' : initialCategories.first);
    DateTime recordDate =
        DateTime.tryParse('${record?['record_date']}') ?? DateTime.now();
    // 仅新建支出时允许设置积分抵扣；历史抵扣额保存后不可修改
    // （删除账单会自动退还，保证积分不丢）。
    var deductPoints = false;
    final existingDeducted = toInt(record?['points_deducted']);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(record == null ? '添加资金记录' : '编辑资金记录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '支出', label: Text('添加支出')),
                    ButtonSegment(value: '收入', label: Text('添加资金')),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) => setDialogState(() {
                    type = value.first;
                    final typeCategories = _categories
                        .where((item) => item['type'] == type)
                        .map((item) => item['name'] as String)
                        .toList();
                    category = typeCategories.isEmpty
                        ? ''
                        : typeCategories.first;
                  }),
                ),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '金额 *',
                    prefixText: '¥ ',
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('$type:$category'),
                        initialValue:
                            category.isEmpty ||
                                !_categories.any(
                                  (item) =>
                                      item['type'] == type &&
                                      item['name'] == category,
                                )
                            ? null
                            : category,
                        decoration:
                            const InputDecoration(labelText: '记账分类'),
                        items: _categories
                            .where((item) => item['type'] == type)
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item['name'] as String,
                                child: Text(item['name'] as String),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => category = value);
                          }
                        },
                      ),
                    ),
                    // 常驻“新建/管理分类”入口：新增分类后立即可选。
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (context) =>
                                  const FinanceCategoryManagementPage(),
                            ),
                          ).then((_) async {
                            await _loadData();
                            if (!context.mounted) return;
                            setDialogState(() {
                              final available = _categories
                                  .where((item) => item['type'] == type)
                                  .toList();
                              if (available.isNotEmpty &&
                                  !available.any(
                                    (item) => item['name'] == category,
                                  )) {
                                category = available.first['name'] as String;
                              }
                            });
                          }),
                      icon: const Icon(Icons.tune, size: 20),
                      label: const Text('管理'),
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '日期：${TimeUtil.toChineseDate(recordDate)}',
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: recordDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) {
                      setDialogState(
                        () => recordDate = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                        ),
                      );
                    }
                  },
                ),
                TextField(
                  controller: remarkController,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
                if (record == null && type == '支出')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同时从积分中扣除'),
                    subtitle: Text('当前积分余额：$_points 分'),
                    value: deductPoints,
                    onChanged: (value) =>
                        setDialogState(() => deductPoints = value),
                  ),
                if (record == null && type == '支出' && deductPoints)
                  TextField(
                    controller: pointsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '扣除积分数量 *',
                      suffixText: '分（不超过余额 $_points）',
                    ),
                  ),
                if (existingDeducted > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '该笔支出已抵扣 $existingDeducted 积分，删除账单时自动退还。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
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
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || !amount.isFinite || amount <= 0) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('请输入有效且大于零的金额')));
                  return;
                }
                if (category.isEmpty) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text('请先添加并选择记账分类')));
                  return;
                }
                var pointsToDeduct = 0;
                if (record == null && type == '支出' && deductPoints) {
                  pointsToDeduct =
                      int.tryParse(pointsController.text.trim()) ?? -1;
                  if (pointsToDeduct <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('请输入大于零的积分数量')),
                    );
                    return;
                  }
                  if (pointsToDeduct > _points) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('积分余额不足（当前 $_points 分）'),
                      ),
                    );
                    return;
                  }
                }
                try {
                  final values = {
                    'type': type,
                    'category': category,
                    'amount': amount,
                    'remark': remarkController.text.trim(),
                    'record_date': _date(recordDate),
                  };
                  if (record == null) {
                    await PointsService.createExpenseWithDeduction(
                      values: values,
                      pointsToDeduct: pointsToDeduct,
                    );
                  } else {
                    await FinanceRepository.instance.saveRecord(
                      values,
                      id: record['record_id'] as int,
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text('保存收支记录失败：$error')));
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    amountController.dispose();
    remarkController.dispose();
    pointsController.dispose();
    if (saved == true && mounted) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('财务'),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: '添加收支',
              onPressed: _loading ? null : () => _showRecordEditor(),
              icon: const Icon(Icons.add),
            ),
          PopupMenuButton<bool>(
            tooltip: '导出数据',
            icon: const Icon(Icons.ios_share),
            onSelected: (pointsFlow) => _exportCsv(pointsFlow: pointsFlow),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('导出账单 CSV')),
              PopupMenuItem(value: true, child: Text('导出积分流水 CSV')),
            ],
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('收支记账')),
                ButtonSegment(value: 1, label: Text('积分体系')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) =>
                  setState(() => _tab = value.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadData)
                : (_tab == 0 ? _buildLedger() : _buildPoints()),
          ),
        ],
      ),
    );
  }

  Widget _buildLedger() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 20),
          _SectionHeader(
            title: '支出预算',
            trailing: Text(
              '${_categories.where((item) => item['type'] == '支出').length} 个分类',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          _buildBudgetSection(),
          const SizedBox(height: 20),
          _SectionHeader(title: '近 6 个月收支趋势'),
          const SizedBox(height: 8),
          _buildMonthlyTrend(),
          const SizedBox(height: 20),
          _SectionHeader(
            title: '收支明细',
            trailing: Text(
              '${_records.length} 笔',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          if (_records.isEmpty)
            _EmptyState(message: '暂无记账记录', icon: Icons.receipt_long_outlined)
          else
            ..._buildRecordGroups(),
        ],
      ),
    );
  }

  // ---- A1：收支明细按日期分组、备注完整展示、收入/支出色彩区分 ----

  List<Widget> _buildRecordGroups() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final record in _records) {
      final dateKey = record['record_date'] as String;
      groups.putIfAbsent(dateKey, () => []).add(record);
    }
    final widgets = <Widget>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final entry in groups.entries) {
      final date = DateTime.tryParse(entry.key);
      var label = entry.key;
      if (date != null) {
        final day = DateTime(date.year, date.month, date.day);
        final diff = today.difference(day).inDays;
        if (diff == 0) {
          label = '今天 · ${DateFormat('M月d日 EEEE', 'zh_CN').format(date)}';
        } else if (diff == 1) {
          label = '昨天 · ${DateFormat('M月d日 EEEE', 'zh_CN').format(date)}';
        } else {
          label = DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(date);
        }
      }
      var income = 0.0;
      var expense = 0.0;
      for (final record in entry.value) {
        final amount = toDouble(record['amount']);
        if (record['type'] == '收入') {
          income += amount;
        } else {
          expense += amount;
        }
      }
      widgets
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (expense > 0)
                Text(
                  '支 ¥${expense.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
              if (expense > 0 && income > 0) const SizedBox(width: 10),
              if (income > 0)
                Text(
                  '收 ¥${income.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
            ],
          ),
        ))
        ..add(Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 64),
                _buildRecordRow(entry.value[i]),
              ],
            ],
          ),
        ));
    }
    return widgets;
  }

  Widget _buildRecordRow(Map<String, dynamic> record) {
    final income = record['type'] == '收入';
    final color = income ? Colors.green : Colors.redAccent;
    final remark = (record['remark'] as String? ?? '').trim();
    final deducted = toInt(record['points_deducted']);
    final isLegacyAuto = remark == '自动添加每日饭钱';
    return InkWell(
      onTap: () => _showRecordActions(record),
      onLongPress: () => _showRecordActions(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                income ? Icons.south_west : Icons.north_east,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          record['category'] as String,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (deducted > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '抵 $deducted 分',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (remark.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      isLegacyAuto ? '（旧版自动记录）' : remark,
                      // 备注多行自适应、完整展示，不再单行截断。
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isLegacyAuto
                            ? Theme.of(context).hintColor
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${income ? '+' : '-'}¥${toDouble(record['amount']).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '账单操作',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showRecordEditor(record: record);
                    } else {
                      _deleteRecord(record);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部总资金英雄卡：主色渐变 + 大数字，对标主流记账应用首页卡。
  Widget _buildSummaryCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: scheme.onPrimary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                '总资金',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '¥${_balance.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '全部收支记录的累计结余',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  /// 预算区：卡片完全由「我的-账单体系-记账分类管理」驱动，
  /// 每个支出分类一格，金额按其结算周期统计，额度取其配置预算。
  Widget _buildBudgetSection() {
    final expenseCategories = _categories
        .where((item) => item['type'] == '支出')
        .toList();
    if (expenseCategories.isEmpty) {
      return const _EmptyState(
        message: '还没有支出分类，记账时可随时新建分类',
        icon: Icons.savings_outlined,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in expenseCategories)
                  SizedBox(
                    width: itemWidth,
                    child: _BudgetItem(
                      category: item['name'] as String,
                      period: BudgetPeriods.labelOf(
                        item['period_type'] as String? ?? 'none',
                      ),
                      spent: _categoryTotals[item['name'] as String] ?? 0,
                      limit: toDouble(item['budget']),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMonthlyTrend() {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    // 近 6 个月均无收支时展示占位，避免渲染一张空白坐标图。
    final hasTrendData = _records.any((record) {
      final date = DateTime.tryParse('${record['record_date']}');
      if (date == null) return false;
      return months.any(
        (month) => date.year == month.year && date.month == month.month,
      );
    });
    if (!hasTrendData) {
      return Card(
        child: _EmptyState(
          message: '近 6 个月暂无收支记录，点击右上角 + 记一笔吧',
          icon: Icons.show_chart_rounded,
        ),
      );
    }
    final groups = <BarChartGroupData>[];
    for (var index = 0; index < months.length; index++) {
      final month = months[index];
      double income = 0;
      double expense = 0;
      for (final record in _records) {
        final date = DateTime.tryParse('${record['record_date']}');
        if (date == null ||
            date.year != month.year ||
            date.month != month.month) {
          continue;
        }
        final amount = toDouble(record['amount']);
        if (record['type'] == '收入') {
          income += amount;
        } else {
          expense += amount;
        }
      }
      groups.add(
        BarChartGroupData(
          x: index,
          barsSpace: 3,
          barRods: [
            BarChartRodData(
              toY: income,
              color: Colors.green,
              width: 8,
              borderRadius: BorderRadius.circular(3),
            ),
            BarChartRodData(
              toY: expense,
              color: Colors.redAccent,
              width: 8,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 18, 12),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  barGroups: groups,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final month = months[group.x];
                        return BarTooltipItem(
                          '${DateFormat('yyyy年M月').format(month)}\n'
                          '${rodIndex == 0 ? '收入' : '支出'} ¥${rod.toY.toStringAsFixed(2)}',
                          const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= months.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat('M月').format(months[index]),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                duration: const Duration(milliseconds: 350),
              ),
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 20,
              children: [
                _ChartLegend(color: Colors.green, label: '收入'),
                _ChartLegend(color: Colors.redAccent, label: '支出'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecordActions(Map<String, dynamic> record) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑记录'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('删除记录'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _showRecordEditor(record: record);
    if (action == 'delete') await _deleteRecord(record);
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收支记录'),
        content: Text(
          '确定删除”${record['category']}” ¥${toDouble(record['amount']).toStringAsFixed(2)} 这笔记录吗？',
        ),
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
    if (confirmed != true || !mounted) return;
    try {
      // 走积分服务删除：若该账单曾抵扣积分，会自动生成退还流水。
      final changed = await PointsService.deleteExpenseAndRefund(
        record['record_id'] as int,
      );
      if (changed == 0) throw StateError('记录不存在或已删除');
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除记录失败：$error')));
      }
    }
  }

  Widget _buildPoints() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPointsHeroCard(),
        const SizedBox(height: 20),
        _SectionHeader(title: '本月收支'),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _PointSummaryItem(
                    label: '本月获得',
                    value: '+$_monthPointIncome',
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _PointSummaryItem(
                    label: '本月支出',
                    value: _monthPointExpense == 0
                        ? '0'
                        : '-$_monthPointExpense',
                    color: Colors.red,
                  ),
                ),
                Expanded(
                  child: _PointSummaryItem(
                    label: '本月净收支',
                    value: '${_monthPointIncome - _monthPointExpense}',
                    color: _monthPointIncome - _monthPointExpense >= 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader(title: '本月积分收支分布'),
        const SizedBox(height: 8),
        _buildPointsPieChart(),
        const SizedBox(height: 20),
        // 历史月份流水可回溯：‹ 本月/上月… ›，也可查看全部。
        _SectionHeader(
          title: _pointMonthOffset == null ? '全部流水' : '$_pointFilterLabel 明细',
          trailing: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            children: [
              IconButton(
                tooltip: '上一月',
                visualDensity: VisualDensity.compact,
                onPressed: _pointMonthOffset == null
                    ? null
                    : () => setState(
                        () => _pointMonthOffset = _pointMonthOffset! + 1,
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                _pointMonthOffset == null ? '全部' : _pointFilterLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                tooltip: '下一月',
                visualDensity: VisualDensity.compact,
                onPressed: (_pointMonthOffset ?? 1) <= 0
                    ? null
                    : () => setState(
                        () => _pointMonthOffset = _pointMonthOffset! - 1,
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _pointMonthOffset = _pointMonthOffset == null ? 0 : null,
                ),
                child: Text(_pointMonthOffset == null ? '回到本月' : '全部'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_visiblePointRecords.isEmpty)
          _EmptyState(
            message: _pointMonthOffset == null
                ? '暂无积分流水'
                : '$_pointFilterLabel暂无积分流水',
            icon: Icons.stars_outlined,
          )
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _visiblePointRecords.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68),
                  _buildPointRecord(_visiblePointRecords[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 积分英雄卡：琥珀渐变 + 大数字，对标主流积分账户头部。
  Widget _buildPointsHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.amber.shade700, Colors.deepOrange.shade400],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text('当前积分', style: TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_points',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '完成任务获得积分，支出可抵扣',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  String get _pointFilterLabel {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - (_pointMonthOffset ?? 0));
    if (_pointMonthOffset == 0) return '本月';
    return DateFormat('yyyy年M月').format(month);
  }

  List<Map<String, dynamic>> get _visiblePointRecords {
    final offset = _pointMonthOffset;
    if (offset == null) return _pointRecordsAll;
    final now = DateTime.now();
    final month = DateTime(now.year, now.month - offset);
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return _pointRecordsAll.where((record) {
      final createdAt = DateTime.tryParse('${record['create_time']}');
      return createdAt != null &&
          !createdAt.isBefore(start) &&
          createdAt.isBefore(end);
    }).toList();
  }

  Widget _buildPointsPieChart() {
    final values = <(String, int)>[
      ('获得积分', _monthPointIncome),
      ('支出积分', _monthPointExpense),
    ].where((entry) => entry.$2 > 0).toList();
    if (values.isEmpty) {
      return const _EmptyState(
        message: '本月暂无积分收支数据',
        icon: Icons.pie_chart_outline,
      );
    }
    final total = values.fold<int>(0, (sum, value) => sum + value.$2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 136,
              height: 136,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 28,
                  sectionsSpace: 2,
                  sections: [
                    for (var index = 0; index < values.length; index++)
                      PieChartSectionData(
                        value: values[index].$2.toDouble(),
                        title:
                            '${(values[index].$2 * 100 / total).toStringAsFixed(0)}%',
                        color: index == 0 ? Colors.green : Colors.redAccent,
                        radius: 54,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 300),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < values.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 5,
                            backgroundColor: index == 0
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(values[index].$1)),
                          Text('${values[index].$2} 分'),
                        ],
                      ),
                    ),
                  Text(
                    '合计 $total 分',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointRecord(Map<String, dynamic> record) {
    final value = toInt(record['point_value']);
    final date = DateTime.tryParse('${record['create_time']}');
    final remark = (record['remark'] as String? ?? '').trim();
    final sourceName = (record['source_name'] as String?)?.trim();
    // E1：新流水 remark 已含对象名；旧流水 remark 是通用文案时，
    // 用 source_type+source_id 反查出的名称补齐“来源：xxx”。
    final detail = remark.isEmpty
        ? (sourceName == null || sourceName.isEmpty
              ? '积分变动'
              : '来源：$sourceName')
        : (sourceName != null &&
                sourceName.isNotEmpty &&
                !remark.contains(sourceName)
            ? '$remark（来源：$sourceName）'
            : remark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: (value >= 0 ? Colors.green : Colors.redAccent)
                .withValues(alpha: 0.12),
            child: Icon(
              value >= 0 ? Icons.add : Icons.remove,
              color: value >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record['operation_type'] as String? ?? '积分变动',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (date != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${value > 0 ? '+' : ''}$value 分',
            style: TextStyle(
              color: value >= 0 ? Colors.green : Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区标题：左标题 + 可选右侧操作区，统一财务页各分区的视觉层级。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _BudgetItem extends StatelessWidget {
  const _BudgetItem({
    required this.category,
    required this.period,
    required this.spent,
    required this.limit,
  });

  final String category;
  final String period;
  final double spent;
  final double limit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOverBudget = limit > 0 && spent > limit;
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final barColor = isOverBudget ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: isOverBudget
            ? Border.all(color: colorScheme.error.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isOverBudget)
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: colorScheme.error,
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.8),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$period ¥${spent.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isOverBudget ? colorScheme.error : null,
                    fontWeight: isOverBudget ? FontWeight.w600 : null,
                  ),
                ),
              ),
              Text(
                '/ ¥${limit.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointSummaryItem extends StatelessWidget {
  const _PointSummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          '$value 分',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color.withValues(alpha: 0.55)),
              const SizedBox(height: 10),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
