import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/time.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class TaskRepository {
  TaskRepository._();
  static final TaskRepository instance = TaskRepository._();

  Future<List<Map<String, dynamic>>> loadSpecialTasks() =>
      AppDatabase.instance.rawQuery('''
        SELECT special_tasks.*, special_task_tags.name AS tag_name,
          '特殊任务' AS kind
        FROM special_tasks
        LEFT JOIN special_task_tags ON special_tasks.task_tag_id = special_task_tags.id
        WHERE special_tasks.is_deleted = 0
        ORDER BY start_time
      ''');

  /// 读取指定特殊任务的提前提醒分钟数列表（升序、去重）。
  Future<List<int>> loadSpecialTaskReminders(int taskId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'special_task_reminders',
      columns: ['remind_minutes_before'],
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'remind_minutes_before',
    );
    return rows
        .map((row) => row['remind_minutes_before'] as int)
        .toSet()
        .toList();
  }

  /// 批量读取所有特殊任务的提醒配置：taskId -> 分钟数列表。
  /// 未配置提醒的任务不出现在 map 中（调用方按默认值兜底）。
  Future<Map<int, List<int>>> loadAllSpecialTaskReminders() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT task_id, remind_minutes_before
      FROM special_task_reminders
      ORDER BY task_id, remind_minutes_before
      ''',
    );
    final result = <int, List<int>>{};
    for (final row in rows) {
      final taskId = row['task_id'] as int;
      final minutes = row['remind_minutes_before'] as int;
      result.putIfAbsent(taskId, () => <int>[]).add(minutes);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> loadDailyTasks() {
    final today = TimeUtil.toDateKey(DateTime.now());
    return AppDatabase.instance.rawQuery('''
      SELECT daily_tasks.*, daily_task_tags.name AS tag_name,
        '日常任务' AS kind,
        EXISTS (
          SELECT 1 FROM daily_task_reward_logs
          WHERE daily_task_reward_logs.task_id = daily_tasks.id
            AND daily_task_reward_logs.reward_date = ?
        ) AS reward_claimed_today
      FROM daily_tasks
      LEFT JOIN daily_task_tags ON daily_tasks.task_tag_id = daily_task_tags.id
      WHERE daily_tasks.is_deleted = 0
      ORDER BY next_review_time, start_time
    ''', [today]);
  }

  Future<List<Map<String, dynamic>>> loadSpecialTags() async {
    final db = await AppDatabase.instance.database;
    return db.query('special_task_tags', orderBy: 'id');
  }

  Future<List<Map<String, dynamic>>> loadDailyTags() async {
    final db = await AppDatabase.instance.database;
    return db.query('daily_task_tags', orderBy: 'id');
  }

  /// 保存特殊任务并同步覆盖其提前提醒配置（同事务）。
  /// [remindMinutesBefore] 为提前分钟数集合（0 = 准时提醒）；
  /// 传 null 表示不修改提醒配置（仅更新任务字段）。
  Future<int> saveSpecialTask(
    Map<String, dynamic> values, {
    int? id,
    Set<int>? remindMinutesBefore,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction<int>((txn) async {
      int taskId;
      if (id == null) {
        taskId = await txn.insert('special_tasks', {
          ...values,
          'status_tag': '未开始',
        });
      } else {
        taskId = id;
        await txn.update(
          'special_tasks',
          values,
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [taskId],
        );
      }
      if (remindMinutesBefore != null) {
        await _replaceSpecialTaskReminders(txn, taskId, remindMinutesBefore);
      }
      return taskId;
    });
  }

  Future<void> _replaceSpecialTaskReminders(
    DatabaseExecutor txn,
    int taskId,
    Set<int> remindMinutesBefore,
  ) async {
    await txn.delete(
      'special_task_reminders',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    // 空集合时补一条默认提前量，保证任务至少有一个提醒。
    final minutesList = remindMinutesBefore.isEmpty
        ? <int>[AppSettingsController.instance.defaultRemindMinutes]
        : remindMinutesBefore.toList()
      ..sort();
    for (final minutes in minutesList) {
      await txn.insert('special_task_reminders', {
        'task_id': taskId,
        'remind_minutes_before': minutes,
      });
    }
  }

  /// 保存日常任务。[reminders] 非 null 时同事务覆盖
  /// daily_task_reminders（B1 习惯型多提醒点；传空列表表示清空）。
  Future<int> saveDailyTask(
    Map<String, dynamic> values, {
    int? id,
    List<({int hour, int minute})>? reminders,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction<int>((txn) async {
      int taskId;
      if (id == null) {
        taskId = await txn.insert('daily_tasks', {
          ...values,
          'status_tag': '未开始',
          'next_review_time': values['start_time'],
          'review_stage': 0,
        });
      } else {
        taskId = id;
        await txn.update(
          'daily_tasks',
          values,
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [taskId],
        );
      }
      if (reminders != null) {
        await txn.delete(
          'daily_task_reminders',
          where: 'task_id = ?',
          whereArgs: [taskId],
        );
        final unique = <({int hour, int minute})>{...reminders};
        for (final reminder in unique) {
          await txn.insert('daily_task_reminders', {
            'task_id': taskId,
            'hour': reminder.hour,
            'minute': reminder.minute,
          });
        }
      }
      return taskId;
    });
  }

  /// B1：读取单个日常任务的提醒时刻（升序）。
  Future<List<({int hour, int minute})>> loadDailyTaskReminders(
    int taskId,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_task_reminders',
      columns: ['hour', 'minute'],
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'hour, minute',
    );
    return rows
        .map(
          (row) => (hour: row['hour'] as int, minute: row['minute'] as int),
        )
        .toList();
  }

  /// B1：批量读取所有日常任务提醒时刻：taskId -> 时刻列表。
  Future<Map<int, List<({int hour, int minute})>>>
  loadAllDailyTaskReminders() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT task_id, hour, minute FROM daily_task_reminders '
      'ORDER BY task_id, hour, minute',
    );
    final result = <int, List<({int hour, int minute})>>{};
    for (final row in rows) {
      result.putIfAbsent(row['task_id'] as int, () => []).add(
        (hour: row['hour'] as int, minute: row['minute'] as int),
      );
    }
    return result;
  }

  Future<int> softDeleteTask({required String table, required int id}) =>
      AppDatabase.instance.update(
        table,
        {'is_deleted': 1},
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [id],
      );

  Future<void> setDailyStatus(int id, String status) =>
      AppDatabase.instance.update(
        'daily_tasks',
        {'status_tag': status},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<List<Map<String, dynamic>>> loadDailyTaskRewardLogs({
    required int taskId,
    required String startDate,
    required String endDate,
  }) =>
      AppDatabase.instance.rawQuery('''
        SELECT reward_date
        FROM daily_task_reward_logs
        WHERE task_id = ? AND reward_date >= ? AND reward_date < ?
        ORDER BY reward_date
      ''', [taskId, startDate, endDate]);
}
