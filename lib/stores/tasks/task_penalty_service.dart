import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/time.dart';

/// 本次扫描实际入账的扣分（供 UI 提示「已扣除 XX 积分」）。
class SettledPenalty {
  const SettledPenalty({
    required this.kind,
    required this.taskId,
    required this.taskName,
    required this.periodKey,
    required this.points,
  });

  final String kind; // daily / habit / special / long
  final int taskId;
  final String taskName;
  final String periodKey;
  final int points;
}

/// 任务逾期扣分扫描服务。
///
/// 覆盖四类任务（愿望/希望不扣分）：
/// - special 特殊短期：过截止时间未完成，一次性扣分（周期键=截止日）；
/// - daily   日常复习：下次复习日逾期超过宽限 1 天，停留期间每打开一天扣一次
///           （周期键=扫描日，与历史行为一致）；
/// - habit   习惯：错过的每个打卡日各扣一次（周期键=应打卡日），
///           升级前的历史打卡日不追溯（habit_penalty_anchor_date 锚点）；
/// - long    长期：过截止日期未完成，一次性扣分（周期键=截止日）。
///
/// 全部扣分通过 [PointsService.applyTaskPenaltyOnce] 幂等入账，
/// 同一任务同一周期无论扫描多少次只扣一次；补完成时由积分引擎等额返还。
class TaskPenaltyService {
  const TaskPenaltyService._();

  /// 扫描并结算全部逾期扣分。单个任务失败不阻断其余任务。
  static Future<List<SettledPenalty>> settleAll({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final result = <SettledPenalty>[];
    result.addAll(await _settleSpecial(current));
    result.addAll(await _settleDailyReview(current));
    result.addAll(await _settleHabit(current));
    result.addAll(await _settleLong(current));
    return result;
  }

  /// 特殊短期任务：过 end_time 且未完成，一次性扣分。
  static Future<List<SettledPenalty>> _settleSpecial(DateTime now) async {
    final db = await AppDatabase.instance.database;
    final tasks = await db.rawQuery(
      '''
      SELECT id, name, end_time, penalty_points
      FROM special_tasks
      WHERE is_deleted = 0
        AND enable_penalty = 1
        AND penalty_points > 0
        AND status_tag != '已完成'
        AND end_time < ?
      ''',
      [now.toIso8601String()],
    );
    final result = <SettledPenalty>[];
    for (final task in tasks) {
      try {
        final end = DateTime.tryParse('${task['end_time']}');
        if (end == null) continue;
        final points = toInt(task['penalty_points']);
        final periodKey = TimeUtil.toDateKey(end);
        final applied = await PointsService.applyTaskPenaltyOnce(
          kind: 'special',
          taskId: toInt(task['id']),
          periodKey: periodKey,
          points: points,
          operationType: '特殊任务逾期扣除',
          remark:
              '特殊任务逾期未完成：${task['name']}'
              '（截止 $periodKey 扣除 $points 积分）',
        );
        if (applied) {
          result.add(
            SettledPenalty(
              kind: 'special',
              taskId: toInt(task['id']),
              taskName: '${task['name']}',
              periodKey: periodKey,
              points: points,
            ),
          );
        }
      } catch (_) {
        // 单任务失败下次扫描自动重试。
      }
    }
    return result;
  }

  /// 日常复习任务：保留历史口径——下次复习日逾期 >1 天，
  /// 每个扫描日最多扣一次（幂等键=扫描日）。
  static Future<List<SettledPenalty>> _settleDailyReview(DateTime now) async {
    final db = await AppDatabase.instance.database;
    final today = DateTime(now.year, now.month, now.day);
    final tasks = await db.rawQuery(
      '''
      SELECT id, name, penalty_points, next_review_time
      FROM daily_tasks
      WHERE is_deleted = 0
        AND enable_penalty = 1
        AND penalty_points > 0
        AND status_tag = '进行中'
        AND task_mode = 'review'
      ''',
    );
    final result = <SettledPenalty>[];
    final periodKey = TimeUtil.toDateKey(today);
    for (final task in tasks) {
      try {
        final nextReview = DateTime.tryParse('${task['next_review_time']}');
        if (nextReview == null) continue;
        final reviewDay = DateTime(
          nextReview.year,
          nextReview.month,
          nextReview.day,
        );
        final daysOverdue = today.difference(reviewDay).inDays;
        if (daysOverdue <= 1) continue;
        final points = toInt(task['penalty_points']);
        final applied = await PointsService.applyTaskPenaltyOnce(
          kind: 'daily',
          taskId: toInt(task['id']),
          periodKey: periodKey,
          points: points,
          operationType: '日常任务未完成扣除',
          remark:
              '日常任务逾期：${task['name']}'
              '（逾期 $daysOverdue 天扣除 $points 积分）',
        );
        if (applied) {
          result.add(
            SettledPenalty(
              kind: 'daily',
              taskId: toInt(task['id']),
              taskName: '${task['name']}',
              periodKey: periodKey,
              points: points,
            ),
          );
        }
      } catch (_) {
        // 忽略单任务异常。
      }
    }
    return result;
  }

  /// 习惯任务：错过且未补打卡的历史打卡日逐日扣分；当天不扣（宽限当日）。
  static Future<List<SettledPenalty>> _settleHabit(DateTime now) async {
    final db = await AppDatabase.instance.database;
    final today = DateTime(now.year, now.month, now.day);
    final anchorRows = await db.rawQuery(
      "SELECT value FROM app_settings WHERE key = 'habit_penalty_anchor_date'",
    );
    final anchor =
        DateTime.tryParse(
          anchorRows.isEmpty ? '' : '${anchorRows.first['value']}',
        ) ??
        DateTime(2000);

    final tasks = await db.rawQuery(
      '''
      SELECT id, name, start_time, penalty_points, repeat_type, repeat_value
      FROM daily_tasks
      WHERE is_deleted = 0
        AND enable_penalty = 1
        AND penalty_points > 0
        AND status_tag = '进行中'
        AND task_mode = 'habit'
      ''',
    );
    final result = <SettledPenalty>[];
    for (final task in tasks) {
      try {
        final startAll = DateTime.tryParse('${task['start_time']}');
        if (startAll == null) continue;
        final start = DateTime(startAll.year, startAll.month, startAll.day);
        var cursor = start.isAfter(anchor) ? start : DateTime(
          anchor.year,
          anchor.month,
          anchor.day,
        );
        final rule = RepeatRule.fromColumns(
          task['repeat_type'] as String?,
          task['repeat_value'] as String?,
        );
        final points = toInt(task['penalty_points']);
        final taskId = toInt(task['id']);
        final yesterday = today.subtract(const Duration(days: 1));
        // 一次性取出该任务从游标到昨天的全部领奖日期，避免逐日查库。
        final claimedRows = await db.rawQuery(
          '''
          SELECT reward_date FROM daily_task_reward_logs
          WHERE task_id = ? AND reward_date BETWEEN ? AND ?
          ''',
          [
            taskId,
            TimeUtil.toDateKey(cursor),
            TimeUtil.toDateKey(yesterday),
          ],
        );
        final claimedDays = {
          for (final row in claimedRows) '${row['reward_date']}',
        };
        // 防御性上限：最多回溯 10 年，避免脏数据长循环。
        for (var guard = 0;
            cursor.isBefore(today) && guard < 3650;
            guard++) {
          if (rule.isDueOn(cursor, start)) {
            final periodKey = TimeUtil.toDateKey(cursor);
            if (!claimedDays.contains(periodKey)) {
              final applied = await PointsService.applyTaskPenaltyOnce(
                kind: 'habit',
                taskId: taskId,
                periodKey: periodKey,
                points: points,
                operationType: '习惯打卡逾期扣除',
                remark:
                    '习惯打卡逾期：${task['name']}'
                    '（$periodKey 应打卡未打卡，扣除 $points 积分）',
              );
              if (applied) {
                result.add(
                  SettledPenalty(
                    kind: 'habit',
                    taskId: taskId,
                    taskName: '${task['name']}',
                    periodKey: periodKey,
                    points: points,
                  ),
                );
              }
            }
          }
          cursor = cursor.add(const Duration(days: 1));
        }
      } catch (_) {
        // 忽略单任务异常。
      }
    }
    return result;
  }

  /// 长期任务：过 deadline 且未完成，一次性扣分。
  static Future<List<SettledPenalty>> _settleLong(DateTime now) async {
    final db = await AppDatabase.instance.database;
    final tasks = await db.rawQuery(
      '''
      SELECT task_id, title, deadline, penalty_points
      FROM tasks
      WHERE task_type = 'long'
        AND enable_penalty = 1
        AND penalty_points > 0
        AND status != '已完成'
        AND deadline IS NOT NULL
        AND deadline < ?
      ''',
      [now.toIso8601String()],
    );
    final result = <SettledPenalty>[];
    for (final task in tasks) {
      try {
        final deadline = DateTime.tryParse('${task['deadline']}');
        if (deadline == null) continue;
        final points = toInt(task['penalty_points']);
        final periodKey = TimeUtil.toDateKey(deadline);
        final applied = await PointsService.applyTaskPenaltyOnce(
          kind: 'long',
          taskId: toInt(task['task_id']),
          periodKey: periodKey,
          points: points,
          operationType: '长期任务逾期扣除',
          remark:
              '长期任务逾期未完成：${task['title']}'
              '（截止 $periodKey 扣除 $points 积分）',
        );
        if (applied) {
          result.add(
            SettledPenalty(
              kind: 'long',
              taskId: toInt(task['task_id']),
              taskName: '${task['title']}',
              periodKey: periodKey,
              points: points,
            ),
          );
        }
      } catch (_) {
        // 忽略单任务异常。
      }
    }
    return result;
  }
}
