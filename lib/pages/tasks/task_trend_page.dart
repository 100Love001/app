import 'package:app/constants/app_constants.dart';
import 'package:app/stores/tasks/task_component_repository.dart';
import 'package:app/utils/chart_data_helper.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/task_component.dart';
import 'package:app/utils/time.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TrendMetric { weight, mood }

/// 体重 / 心情独立页：应用级记录（与任务无关），
/// 多条历史记录 + 折线图 + 录入与删除。
class TaskTrendPage extends StatefulWidget {
  const TaskTrendPage({
    super.key,
    required this.metric,
  });

  final TrendMetric metric;

  @override
  State<TaskTrendPage> createState() => _TaskTrendPageState();
}

class _TaskTrendPageState extends State<TaskTrendPage> {
  final _repository = TaskComponentRepository.instance;
  List<WeightRecord> _weights = [];
  List<MoodRecord> _moods = [];
  bool _loading = true;

  bool get _isWeight => widget.metric == TrendMetric.weight;

  /// 心情类别：独立页使用默认五项（很差/较差/一般/不错/很好）。
  List<MoodCategory> get _categories => MoodCategory.defaults;

  String _moodLabel(int score) => MoodCategory.labelFor(score, _categories);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      if (_isWeight) {
        _weights = await _repository.loadAllWeights();
      } else {
        _moods = await _repository.loadAllMoods();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddDialog() async {
    final selectedDate = ValueNotifier<DateTime>(DateTime.now());
    final valueController = TextEditingController();
    final noteController = TextEditingController();
    final categories = _categories;
    var moodLevel = ValueNotifier<int>(
      categories[categories.length ~/ 2].score,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isWeight ? '记录体重' : '记录心情'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<DateTime>(
                valueListenable: selectedDate,
                builder: (_, date, _) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.event),
                  title: Text(DateFormat('yyyy-MM-dd').format(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) selectedDate.value = picked;
                  },
                ),
              ),
              if (_isWeight)
                TextField(
                  controller: valueController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '体重',
                    suffixText: 'kg',
                  ),
                )
              else
                ValueListenableBuilder<int>(
                  valueListenable: moodLevel,
                  builder: (_, level, _) => Wrap(
                    spacing: 6,
                    children: [
                      for (final category in categories)
                        ChoiceChip(
                          label: Text(category.label),
                          selected: level == category.score,
                          onSelected: (_) => moodLevel.value = category.score,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: '备注（可选）'),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    // 等待退场动画结束，再在下方路径中释放控制器（避免断言红屏）。
    await waitForDialogDismissal();
    if (confirmed != true || !mounted) {
      valueController.dispose();
      noteController.dispose();
      moodLevel.dispose();
      selectedDate.dispose();
      return;
    }

    final dateKey = TimeUtil.toDateKey(selectedDate.value);
    try {
      if (_isWeight) {
        final weight = double.tryParse(valueController.text.trim());
        if (weight == null || weight <= 0 || weight > 600) {
          _snack('请输入合理的体重数值（0-600 kg）');
          return;
        }
        await _repository.addWeight(
          recordDate: dateKey,
          weight: weight,
          note: noteController.text,
        );
      } else {
        await _repository.addMood(
          recordDate: dateKey,
          level: moodLevel.value,
          note: noteController.text,
        );
      }
      await _reload();
    } catch (error) {
      _snack('保存失败：$error');
    } finally {
      valueController.dispose();
      noteController.dispose();
      moodLevel.dispose();
      selectedDate.dispose();
    }
  }

  Future<void> _deleteRecord(int id) async {
    try {
      if (_isWeight) {
        await _repository.deleteWeight(id);
      } else {
        await _repository.deleteMood(id);
      }
      await _reload();
    } catch (error) {
      _snack('删除失败：$error');
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isWeight ? '体重' : '心情';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: Text(_isWeight ? '记体重' : '记心情'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    final empty = Center(
      child: ListView(
        shrinkWrap: true,
        children: [
          Icon(
            _isWeight ? Icons.monitor_weight_outlined : Icons.mood_outlined,
            size: 56,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _isWeight ? '还没有体重记录，点击下方按钮记一条' : '还没有心情记录，点击下方按钮记一条',
            ),
          ),
        ],
      ),
    );

    if (_isWeight) {
      if (_weights.isEmpty) return empty;
      return _buildWeightContent();
    }
    if (_moods.isEmpty) return empty;
    return _buildMoodContent();
  }

  // ---------------- 体重 ----------------

  Widget _buildWeightContent() {
    final stats = ChartDataHelper.weightStats(_weights);
    final spots = ChartDataHelper.weightSpots(_weights);
    final minY = (stats!.min - 1).floorToDouble();
    final maxY = (stats.max + 1).ceilToDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 96),
      children: [
        _StatsRow(
          items: [
            ('最新', '${stats.latest.toStringAsFixed(1)} kg'),
            ('最低', '${stats.min.toStringAsFixed(1)} kg'),
            ('最高', '${stats.max.toStringAsFixed(1)} kg'),
            ('平均', '${stats.avg.toStringAsFixed(1)} kg'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: (_interval(spots.length)).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= _weights.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortDate(_weights[index].recordDate),
                          style: const TextStyle(fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => [
                    for (final spot in touchedSpots)
                      LineTooltipItem(
                        '${_weights[spot.spotIndex].recordDate}\n'
                        '${spot.y.toStringAsFixed(1)} kg',
                        const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _RecordListHeader(count: _weights.length),
        for (var i = _weights.length - 1; i >= 0; i--)
          Dismissible(
            key: ValueKey('weight_${_weights[i].id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) => _deleteRecord(_weights[i].id),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.monitor_weight_outlined),
              title: Text('${_weights[i].weight.toStringAsFixed(1)} kg'),
              subtitle: Text(
                _weights[i].note.isEmpty
                    ? _weights[i].recordDate
                    : '${_weights[i].recordDate} · ${_weights[i].note}',
              ),
            ),
          ),
      ],
    );
  }

  // ---------------- 心情 ----------------

  Widget _buildMoodContent() {
    final average = ChartDataHelper.moodAverage(_moods);
    final spots = ChartDataHelper.moodSpots(_moods);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 96),
      children: [
        _StatsRow(
          items: [
            ('记录', '${_moods.length} 条'),
            ('平均心情', average == null ? '-' : average.toStringAsFixed(1)),
            ('最新', _moodLabel(_moods.last.level)),
            ('', ''),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minY: 0.5,
              maxY: 5.5,
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: (_interval(spots.length)).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= _moods.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortDate(_moods[index].recordDate),
                          style: const TextStyle(fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      if (value < 1 || value > 5) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        _moodLabel(value.round()),
                        style: const TextStyle(fontSize: 9),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => [
                    for (final spot in touchedSpots)
                      LineTooltipItem(
                        '${_moods[spot.spotIndex].recordDate}\n'
                        '${_moodLabel(spot.y.round())}',
                        const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _RecordListHeader(count: _moods.length),
        for (var i = _moods.length - 1; i >= 0; i--)
          Dismissible(
            key: ValueKey('mood_${_moods[i].id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) => _deleteRecord(_moods[i].id),
            child: ListTile(
              dense: true,
              leading: Icon(MoodLevel.fromScore(_moods[i].level).icon),
              title: Text(_moodLabel(_moods[i].level)),
              subtitle: Text(
                _moods[i].note.isEmpty
                    ? _moods[i].recordDate
                    : '${_moods[i].recordDate} · ${_moods[i].note}',
              ),
            ),
          ),
      ],
    );
  }

  int _interval(int count) {
    if (count <= 6) return 1;
    return (count / 6).ceil();
  }

  String _shortDate(String dateKey) {
    final date = DateTime.tryParse(dateKey);
    if (date == null) return dateKey;
    return DateFormat('MM-dd').format(date);
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecordListHeader extends StatelessWidget {
  const _RecordListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text('历史记录（$count 条，左滑删除）',
          style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
