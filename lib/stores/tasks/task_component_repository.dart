import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/task_component.dart';

/// 体重记录（动态组件「体重记录」的多条历史数据）。
class WeightRecord {
  const WeightRecord({
    required this.id,
    required this.taskKind,
    required this.taskId,
    required this.recordDate,
    required this.weight,
    this.note = '',
    this.taskName = '',
  });

  final int id;
  final String taskKind;
  final int taskId;
  final String recordDate;
  final double weight;
  final String note;

  /// 反查出的所属任务名（仅跨任务汇总查询携带，趋势页查询为空）。
  final String taskName;

  factory WeightRecord.fromMap(Map<String, dynamic> map) => WeightRecord(
    id: toInt(map['id']),
    taskKind: '${map['task_kind']}',
    taskId: toInt(map['task_id']),
    recordDate: '${map['record_date']}',
    weight: toDouble(map['weight']),
    note: '${map['note'] ?? ''}',
    taskName: '${map['task_name'] ?? ''}',
  );
}

/// 心情记录（动态组件「心情记录」的多条历史数据，level 1-5）。
class MoodRecord {
  const MoodRecord({
    required this.id,
    required this.taskKind,
    required this.taskId,
    required this.recordDate,
    required this.level,
    this.note = '',
    this.taskName = '',
  });

  final int id;
  final String taskKind;
  final int taskId;
  final String recordDate;
  final int level;
  final String note;

  /// 反查出的所属任务名（仅跨任务汇总查询携带，趋势页查询为空）。
  final String taskName;

  factory MoodRecord.fromMap(Map<String, dynamic> map) => MoodRecord(
    id: toInt(map['id']),
    taskKind: '${map['task_kind']}',
    taskId: toInt(map['task_id']),
    recordDate: '${map['record_date']}',
    level: toInt(map['level']),
    note: '${map['note'] ?? ''}',
    taskName: '${map['task_name'] ?? ''}',
  );
}

/// 数据分析记录（动态组件「数据分析」的多条历史数据）。
class DataRecord {
  const DataRecord({
    required this.id,
    required this.taskKind,
    required this.taskId,
    required this.recordDate,
    required this.value,
    this.note = '',
  });

  final int id;
  final String taskKind;
  final int taskId;
  final String recordDate;
  final double value;
  final String note;

  factory DataRecord.fromMap(Map<String, dynamic> map) => DataRecord(
    id: toInt(map['id']),
    taskKind: '${map['task_kind']}',
    taskId: toInt(map['task_id']),
    recordDate: '${map['record_date']}',
    value: toDouble(map['value']),
    note: '${map['note'] ?? ''}',
  );
}

/// 动态组件业务数据仓储：体重 / 心情 / 数据分析记录表的增删查。
/// 组件配置本身（标题、组件清单、进度等）存在任务表 component_json 列，
/// 只有需要多条历史、支撑趋势图的体重/心情/数据分析数据独立建表。
class TaskComponentRepository {
  TaskComponentRepository._();
  static final TaskComponentRepository instance = TaskComponentRepository._();

  Future<List<WeightRecord>> loadWeights({
    required String taskKind,
    required int taskId,
  }) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''SELECT * FROM task_weight_records
         WHERE task_kind = ? AND task_id = ?
         ORDER BY record_date, id''',
      [taskKind, taskId],
    );
    return rows.map(WeightRecord.fromMap).toList();
  }

  Future<int> addWeight({
    required String taskKind,
    required int taskId,
    required String recordDate,
    required double weight,
    String note = '',
  }) => AppDatabase.instance.insert('task_weight_records', {
    'task_kind': taskKind,
    'task_id': taskId,
    'record_date': recordDate,
    'weight': weight,
    'note': note.trim().isEmpty ? null : note.trim(),
  });

  Future<void> deleteWeight(int id) =>
      AppDatabase.instance.delete('task_weight_records', where: 'id = ?', whereArgs: [id]);

  Future<List<MoodRecord>> loadMoods({
    required String taskKind,
    required int taskId,
  }) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''SELECT * FROM task_mood_records
         WHERE task_kind = ? AND task_id = ?
         ORDER BY record_date, id''',
      [taskKind, taskId],
    );
    return rows.map(MoodRecord.fromMap).toList();
  }

  Future<int> addMood({
    required String taskKind,
    required int taskId,
    required String recordDate,
    required int level,
    String note = '',
  }) => AppDatabase.instance.insert('task_mood_records', {
    'task_kind': taskKind,
    'task_id': taskId,
    'record_date': recordDate,
    'level': level.clamp(1, 5),
    'note': note.trim().isEmpty ? null : note.trim(),
  });

  Future<void> deleteMood(int id) =>
      AppDatabase.instance.delete('task_mood_records', where: 'id = ?', whereArgs: [id]);

  Future<List<DataRecord>> loadDataRecords({
    required String taskKind,
    required int taskId,
  }) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''SELECT * FROM task_data_records
         WHERE task_kind = ? AND task_id = ?
         ORDER BY record_date, id''',
      [taskKind, taskId],
    );
    return rows.map(DataRecord.fromMap).toList();
  }

  Future<int> addDataRecord({
    required String taskKind,
    required int taskId,
    required String recordDate,
    required double value,
    String note = '',
  }) => AppDatabase.instance.insert('task_data_records', {
    'task_kind': taskKind,
    'task_id': taskId,
    'record_date': recordDate,
    'value': value,
    'note': note.trim().isEmpty ? null : note.trim(),
  });

  Future<void> deleteDataRecord(int id) => AppDatabase.instance.delete(
    'task_data_records',
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 全局最新一条体重记录（跨任务，最近使用优先）。
  /// 供首页快捷记录定位目标任务；习惯任务存于 daily_tasks（task_kind='daily'）。
  Future<WeightRecord?> latestWeight() async {
    final rows = await AppDatabase.instance.rawQuery('''
      SELECT w.*, COALESCE(d.name, t.title, s.name, '') AS task_name
      FROM task_weight_records w
      LEFT JOIN daily_tasks d ON w.task_kind = 'daily' AND d.id = w.task_id
      LEFT JOIN tasks t ON w.task_kind = 'long' AND t.task_id = w.task_id
      LEFT JOIN special_tasks s ON w.task_kind = 'special' AND s.id = w.task_id
      ORDER BY w.record_date DESC, w.id DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : WeightRecord.fromMap(rows.first);
  }

  /// 全局最新一条心情记录（跨任务，最近使用优先）。
  Future<MoodRecord?> latestMood() async {
    final rows = await AppDatabase.instance.rawQuery('''
      SELECT m.*, COALESCE(d.name, t.title, s.name, '') AS task_name
      FROM task_mood_records m
      LEFT JOIN daily_tasks d ON m.task_kind = 'daily' AND d.id = m.task_id
      LEFT JOIN tasks t ON m.task_kind = 'long' AND t.task_id = m.task_id
      LEFT JOIN special_tasks s ON m.task_kind = 'special' AND s.id = m.task_id
      ORDER BY m.record_date DESC, m.id DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : MoodRecord.fromMap(rows.first);
  }

  /// 目标任务心情组件的自定义类别（读任务 component_json）；
  /// 任务不存在 / 无配置 / 解析失败时回退 MoodLevel 默认五项。
  Future<List<MoodCategory>> loadMoodCategories({
    required String taskKind,
    required int taskId,
  }) async {
    try {
      final (table, idColumn) = switch (taskKind) {
        'daily' => ('daily_tasks', 'id'),
        'long' => ('tasks', 'task_id'),
        _ => ('special_tasks', 'id'),
      };
      final rows = await AppDatabase.instance.rawQuery(
        'SELECT component_json FROM $table WHERE $idColumn = ?',
        [taskId],
      );
      if (rows.isEmpty) return MoodCategory.defaults;
      final raw = rows.first['component_json'] as String?;
      final doc = TaskComponentDocument.decode(raw);
      return MoodCategory.parse(doc.dataOf(ComponentType.mood));
    } catch (_) {
      return MoodCategory.defaults;
    }
  }

  /// 删除任务时清理其全部组件历史（长期任务为物理删除时调用）。
  Future<void> deleteForTask(String taskKind, int taskId) async {
    await AppDatabase.instance.delete(
      'task_weight_records',
      where: 'task_kind = ? AND task_id = ?',
      whereArgs: [taskKind, taskId],
    );
    await AppDatabase.instance.delete(
      'task_mood_records',
      where: 'task_kind = ? AND task_id = ?',
      whereArgs: [taskKind, taskId],
    );
    await AppDatabase.instance.delete(
      'task_data_records',
      where: 'task_kind = ? AND task_id = ?',
      whereArgs: [taskKind, taskId],
    );
  }
}
