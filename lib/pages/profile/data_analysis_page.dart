import 'dart:async';
import 'dart:math' as math;

import 'package:app/stores/analysis/analysis_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 数据分析：积分收支趋势、任务完成、财务收支、愿望进度四个维度，
/// 帮助用户回顾一段时间内的投入与产出。
class DataAnalysisPage extends StatefulWidget {
  const DataAnalysisPage({super.key});

  @override
  State<DataAnalysisPage> createState() => _DataAnalysisPageState();
}

class _DataAnalysisPageState extends State<DataAnalysisPage> {
  AnalysisData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await const AnalysisRepository().load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据分析')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: const Text('统计数据加载失败'),
                  subtitle: Text('$_error'),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('重试'),
                  ),
                ),
              )
            else if (_data == null)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildPointsTrend(context, _data!),
              const SizedBox(height: 16),
              _buildTaskStats(context, _data!.tasks),
              const SizedBox(height: 16),
              _buildFinanceStats(context, _data!),
              const SizedBox(height: 16),
              _buildWishProgress(context, _data!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPointsTrend(BuildContext context, AnalysisData data) {
    final trend = data.pointsTrend;
    final maxValue = trend.fold<int>(
      0,
      (max, day) => math.max(max, math.max(day.income, day.expense)),
    );
    final hasData = maxValue > 0;
    return _sectionCard(
      context: context,
      icon: Icons.stacked_line_chart_rounded,
      title: '积分收支趋势（近14天）',
      child: hasData
          ? SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: [
                    for (var i = 0; i < trend.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 3,
                        barRods: [
                          BarChartRodData(
                            toY: trend[i].income.toDouble(),
                            color: Theme.of(context).colorScheme.primary,
                            width: 5,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          BarChartRodData(
                            toY: trend[i].expense.toDouble(),
                            color: Colors.orange.shade300,
                            width: 5,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                  ],
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final day = trend[group.x];
                        return BarTooltipItem(
                          '${day.day}\n${rodIndex == 0 ? '入账' : '支出'} ${rod.toY.round()} 分',
                          const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index % 3 != 1 ||
                              index < 0 ||
                              index >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          final day = trend[index].day;
                          return Text(
                            '${int.parse(day.substring(5, 7))}/'
                            '${int.parse(day.substring(8, 10))}',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            )
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('近14天暂无积分变动')),
            ),
    );
  }

  Widget _buildTaskStats(BuildContext context, TaskCompletionStat tasks) {
    return _sectionCard(
      context: context,
      icon: Icons.task_alt_rounded,
      title: '任务完成统计',
      child: Row(
        children: [
          _statCell(context, '今日完成', '${tasks.todayDone} 项'),
          _statCell(context, '近7天打卡', '${tasks.weekRewards} 次'),
          _statCell(context, '连续打卡', '${tasks.streak} 天'),
          _statCell(
            context,
            '特殊任务',
            '${tasks.specialDone}/${tasks.specialTotal}',
          ),
        ],
      ),
    );
  }

  Widget _statCell(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _buildFinanceStats(BuildContext context, AnalysisData data) {
    final balance = data.monthIncome - data.monthExpense;
    final maxCategory = data.topExpenseCategories.fold<double>(
      0,
      (max, item) => math.max(max, item.amount),
    );
    return _sectionCard(
      context: context,
      icon: Icons.account_balance_wallet_outlined,
      title: '财务收支（本月）',
      child: Column(
        children: [
          Row(
            children: [
              _statCell(
                context,
                '收入',
                '¥${data.monthIncome.toStringAsFixed(0)}',
              ),
              _statCell(
                context,
                '支出',
                '¥${data.monthExpense.toStringAsFixed(0)}',
              ),
              _statCell(context, '结余', '¥${balance.toStringAsFixed(0)}'),
            ],
          ),
          if (data.topExpenseCategories.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            for (final item in data.topExpenseCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxCategory == 0
                              ? 0
                              : item.amount / maxCategory,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '¥${item.amount.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: Text('本月暂无支出记录')),
            ),
        ],
      ),
    );
  }

  Widget _buildWishProgress(BuildContext context, AnalysisData data) {
    return _sectionCard(
      context: context,
      icon: Icons.auto_awesome_rounded,
      title: '愿望进度回顾',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.redeemedWishCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '已兑换 ${data.redeemedWishCount} 个愿望',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (data.activeWishes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text('暂无进行中的愿望')),
            )
          else
            for (final wish in data.activeWishes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            wish.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${wish.currentPoints}/${wish.requiredPoints} 分',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: wish.ratio,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
