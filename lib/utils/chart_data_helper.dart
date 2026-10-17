import 'package:fl_chart/fl_chart.dart';

import '../stores/tasks/task_component_repository.dart';

/// 图表数据助手：把体重 / 心情原始记录转换为 fl_chart 数据源。
class ChartDataHelper {
  const ChartDataHelper._();

  static List<FlSpot> weightSpots(List<WeightRecord> records) => [
    for (var i = 0; i < records.length; i++)
      FlSpot(i.toDouble(), records[i].weight),
  ];

  static List<FlSpot> moodSpots(List<MoodRecord> records) => [
    for (var i = 0; i < records.length; i++)
      FlSpot(i.toDouble(), records[i].level.toDouble()),
  ];

  /// 体重统计（无数据返回 null）。
  static ({double min, double max, double avg, double latest})? weightStats(
    List<WeightRecord> records,
  ) {
    if (records.isEmpty) return null;
    final values = records.map((r) => r.weight).toList();
    final sum = values.fold<double>(0, (a, b) => a + b);
    return (
      min: values.reduce((a, b) => a < b ? a : b),
      max: values.reduce((a, b) => a > b ? a : b),
      avg: sum / values.length,
      latest: values.last,
    );
  }

  /// 心情均值（1-5）。
  static double? moodAverage(List<MoodRecord> records) {
    if (records.isEmpty) return null;
    return records.map((r) => r.level).reduce((a, b) => a + b) /
        records.length;
  }
}
