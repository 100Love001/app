import 'package:app/stores/tasks/task_component_repository.dart';
import 'package:app/utils/time.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 数据分析趋势页：按组件配置的图表类型渲染记录，
/// 支持录入（日期 + 数值 + 备注）与左滑删除。
class DataChartTrendPage extends StatefulWidget {
  const DataChartTrendPage({
    super.key,
    required this.taskKind,
    required this.taskId,
    required this.taskTitle,
    required this.chartType,
    required this.chartTitle,
    required this.unit,
  });

  final String taskKind;
  final int taskId;
  final String taskTitle;

  /// 图表类型：line / bar / pie / table。
  final String chartType;

  /// 图表名称（组件配置，可为空）。
  final String chartTitle;

  /// 数值单位（组件配置，可为空）。
  final String unit;

  @override
  State<DataChartTrendPage> createState() => _DataChartTrendPageState();
}

class _DataChartTrendPageState extends State<DataChartTrendPage> {
  final _repository = TaskComponentRepository.instance;
  List<DataRecord> _records = [];
  bool _loading = true;

  String get _name =>
      widget.chartTitle.trim().isEmpty ? '数据分析' : widget.chartTitle.trim();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _records = await _repository.loadDataRecords(
        taskKind: widget.taskKind,
        taskId: widget.taskId,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _valueLabel(double value) => widget.unit.trim().isEmpty
      ? value.toStringAsFixed(1)
      : '${value.toStringAsFixed(1)} ${widget.unit.trim()}';

  Future<void> _showAddDialog() async {
    final selectedDate = ValueNotifier<DateTime>(DateTime.now());
    final valueController = TextEditingController();
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('记录$_name'),
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
              TextField(
                controller: valueController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '数值',
                  suffixText: widget.unit.trim().isEmpty
                      ? null
                      : widget.unit.trim(),
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

    if (confirmed != true || !mounted) {
      valueController.dispose();
      noteController.dispose();
      selectedDate.dispose();
      return;
    }

    try {
      final value = double.tryParse(valueController.text.trim());
      if (value == null) {
        _snack('请输入有效数值');
        return;
      }
      await _repository.addDataRecord(
        taskKind: widget.taskKind,
        taskId: widget.taskId,
        recordDate: TimeUtil.toDateKey(selectedDate.value),
        value: value,
        note: noteController.text,
      );
      await _reload();
    } catch (error) {
      _snack('保存失败：$error');
    } finally {
      valueController.dispose();
      noteController.dispose();
      selectedDate.dispose();
    }
  }

  Future<void> _deleteRecord(int id) async {
    try {
      await _repository.deleteDataRecord(id);
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
    return Scaffold(
      appBar: AppBar(title: Text('$_name · ${widget.taskTitle}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _reload, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_records.isEmpty) {
      return Center(
        child: ListView(
          shrinkWrap: true,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 56,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            const Center(child: Text('还没有数据记录，点击下方按钮记一笔')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 96),
      children: [
        _buildStats(),
        const SizedBox(height: 12),
        if (widget.chartType == 'table')
          _buildTable()
        else
          SizedBox(height: 240, child: _buildChart()),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            '历史记录（${_records.length} 条，左滑删除）',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        for (var i = _records.length - 1; i >= 0; i--)
          Dismissible(
            key: ValueKey('data_${_records[i].id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) => _deleteRecord(_records[i].id),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.insights_outlined),
              title: Text(_valueLabel(_records[i].value)),
              subtitle: Text(
                _records[i].note.isEmpty
                    ? _records[i].recordDate
                    : '${_records[i].recordDate} · ${_records[i].note}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStats() {
    var min = _records.first.value;
    var max = min;
    var sum = 0.0;
    for (final record in _records) {
      if (record.value < min) min = record.value;
      if (record.value > max) max = record.value;
      sum += record.value;
    }
    final items = [
      ('最新', _valueLabel(_records.last.value)),
      ('最低', _valueLabel(min)),
      ('最高', _valueLabel(max)),
      ('平均', _valueLabel(sum / _records.length)),
    ];
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
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(item.$1, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTable() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('日期')),
            DataColumn(label: Text(widget.unit.trim().isEmpty ? '数值' : '数值（${widget.unit.trim()}）')),
            const DataColumn(label: Text('备注')),
          ],
          rows: [
            for (final record in _records.reversed)
              DataRow(
                cells: [
                  DataCell(Text(record.recordDate)),
                  DataCell(Text(record.value.toStringAsFixed(1))),
                  DataCell(Text(record.note)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    return switch (widget.chartType) {
      'bar' => _buildBarChart(),
      'pie' => _buildPieChart(),
      _ => _buildLineChart(),
    };
  }

  Widget _buildLineChart() {
    final spots = [
      for (var i = 0; i < _records.length; i++)
        FlSpot(i.toDouble(), _records[i].value),
    ];
    var minY = spots.first.y;
    var maxY = minY;
    for (final spot in spots) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: true),
        titlesData: _titles(),
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
                  '${_records[spot.spotIndex].recordDate}\n'
                  '${_valueLabel(spot.y)}',
                  const TextStyle(fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    var maxY = 0.0;
    for (final record in _records) {
      if (record.value > maxY) maxY = record.value;
    }
    if (maxY <= 0) maxY = 1;
    return BarChart(
      BarChartData(
        maxY: maxY * 1.15,
        gridData: const FlGridData(show: true),
        titlesData: _titles(),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  '${_records[group.x].recordDate}\n${_valueLabel(rod.toY)}',
                  const TextStyle(fontSize: 11),
                ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < _records.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _records[i].value,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPieChart() {
    final colors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.green,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.deepOrange,
    ];
    // 饼图按非负值占比；非正数值记为 0，不参与扇区。
    final values = [
      for (final record in _records)
        record.value > 0 ? record.value : 0.0,
    ];
    final total = values.fold<double>(0, (sum, v) => sum + v);
    if (total <= 0) {
      return const Center(child: Text('饼图需要正数数值'));
    }
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 36,
        sections: [
          for (var i = 0; i < _records.length; i++)
            if (values[i] > 0)
              PieChartSectionData(
                value: values[i],
                color: colors[i % colors.length],
                radius: 72,
                title:
                    '${_shortDate(_records[i].recordDate)}\n'
                    '${(values[i] / total * 100).toStringAsFixed(0)}%',
                titleStyle: const TextStyle(fontSize: 9, color: Colors.white),
              ),
        ],
      ),
    );
  }

  FlTitlesData _titles() => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: _interval(_records.length).toDouble(),
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 || index >= _records.length) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _shortDate(_records[index].recordDate),
              style: const TextStyle(fontSize: 9),
            ),
          );
        },
      ),
    ),
    leftTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
    ),
  );

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
