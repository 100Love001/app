import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';

class FoodPointExchange {
  const FoodPointExchange({required this.amount, required this.points});

  final double amount;
  final int points;
}

class PointsService {
  const PointsService._();

  /// 饭钱结余兑换积分比例（每元 = N 积分），在“我的-个性化参数”中可调。
  static int get foodPointsPerYuan =>
      AppSettingsController.instance.foodPointsPerYuan;

  /// 积分流水反查来源名称的 SQL 片段：
  /// 展示层按 source_type + source_id 关联出任务/愿望/希望/账单名称，
  /// 历史流水也能显示新名称（对象改名后同步生效）。
  static const sourceNameColumn = '''
    CASE
      WHEN p.source_type IN ('special_task', 'special_task_penalty')
        THEN (SELECT name FROM special_tasks WHERE id = p.source_id)
      WHEN p.source_type IN ('daily_task', 'daily_task_penalty')
        THEN (SELECT name FROM daily_tasks WHERE id = p.source_id)
      WHEN p.source_type = 'hope' OR p.source_type = 'hope_step_penalty'
        THEN (SELECT name FROM hopes WHERE hope_id = p.source_id)
      WHEN p.source_type = 'hope_step'
        THEN (SELECT name FROM hope_steps WHERE step_id = p.source_id)
      WHEN p.source_type = 'wish_refund'
        THEN (SELECT name FROM wishes WHERE wish_id = p.source_id)
      WHEN p.source_type = 'wish_redemption'
        THEN (SELECT w.name FROM wish_redemptions r
          JOIN wishes w ON w.wish_id = r.wish_id WHERE r.id = p.source_id)
      WHEN p.source_type = 'expense_deduction' OR p.source_type = 'expense_refund'
        THEN (SELECT category FROM income_expenses WHERE record_id = p.source_id)
    END
  ''';

  static int foodPointsForBalance(double remaining) {
    if (!remaining.isFinite || remaining < 0) {
      throw ArgumentError.value(remaining, 'remaining', '必须是有效的非负金额');
    }
    return (remaining * foodPointsPerYuan).floor();
  }

  static DateTime nextDailyReviewDate(DateTime date, int stage) {
    if (stage < 0) throw ArgumentError.value(stage, 'stage', '不能小于零');
    final intervalIndex = stage.clamp(
      0,
      AppConstants.reviewIntervals.length - 1,
    );
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(days: AppConstants.reviewIntervals[intervalIndex]));
  }

  static Future<int?> completeSpecialTask(int taskId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'special_tasks',
        columns: [
          'name',
          'reward_points',
          'status_tag',
          'start_time',
          'end_time',
          'is_deleted',
        ],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty || toInt(rows.first['is_deleted']) != 0) {
        return null;
      }
      final storedStatus = rows.first['status_tag'] as String;
      if (storedStatus == '已完成') return null;
      final start = DateTime.tryParse('${rows.first['start_time']}');
      final end = DateTime.tryParse('${rows.first['end_time']}');
      final now = DateTime.now();
      if (start == null ||
          end == null ||
          now.isBefore(start) ||
          now.isAfter(end)) {
        return null;
      }
      final reward = toInt(rows.first['reward_points']);
      final changed = await transaction.update(
        'special_tasks',
        {'status_tag': '已完成', 'completed_at': now.toIso8601String()},
        where: 'id = ? AND status_tag = ?',
        whereArgs: [taskId, storedStatus],
      );
      if (changed == 0) return null;
      if (reward > 0) {
        await transaction.insert('points', {
          'source_type': 'special_task',
          'source_id': taskId,
          'point_value': reward,
          'operation_type': '任务奖励',
          'remark': '完成特殊任务：${rows.first['name']}（${_date(now)} 奖励 $reward 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return reward;
    });
  }

  /// 逾期补完成特殊任务：仅允许在 end_time 之后操作，只归档状态、不发积分。
  /// 返回 false 表示任务不存在、已删除、已完成或仍在有效时间窗内
  /// （在时间窗内应走 completeSpecialTask 正常计分）。
  static Future<bool> closeExpiredSpecialTask(int taskId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'special_tasks',
        columns: ['name', 'status_tag', 'end_time', 'is_deleted', 'penalty_points'],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty || toInt(rows.first['is_deleted']) != 0) {
        return false;
      }
      final storedStatus = rows.first['status_tag'] as String;
      if (storedStatus == '已完成') return false;
      final end = DateTime.tryParse('${rows.first['end_time']}');
      if (end == null || !DateTime.now().isAfter(end)) return false;
      final changed = await transaction.update(
        'special_tasks',
        {'status_tag': '已完成', 'completed_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND status_tag = ?',
        whereArgs: [taskId, storedStatus],
      );
      if (changed == 1) {
        final penalty = toInt(rows.first['penalty_points']);
        if (penalty > 0) {
          await transaction.insert('points', {
            'source_type': 'special_task_penalty',
            'source_id': taskId,
            'point_value': -penalty,
            'operation_type': '特殊任务未完成扣除',
            'remark': '特殊任务未完成：${rows.first['name']}（扣除 $penalty 积分）',
            'create_time': DateTime.now().toIso8601String(),
          });
        }
      }
      return changed == 1;
    });
  }

  static Future<int?> claimDailyTaskReward({
    required int taskId,
    required DateTime date,
  }) async {
    final db = await AppDatabase.instance.database;
    final rewardDate = _date(date);
    return db.transaction((transaction) async {
      final tasks = await transaction.query(
        'daily_tasks',
        columns: [
          'name',
          'daily_points',
          'status_tag',
          'review_stage',
          'is_deleted',
          'start_time',
          'next_review_time',
        ],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (tasks.isEmpty ||
          tasks.first['status_tag'] != '进行中' ||
          toInt(tasks.first['is_deleted']) != 0) {
        return null;
      }

      // 艾宾浩斯复习窗口校验：仅在开始日期之后、且到达（或错过）下次复习日
      // 时才能领奖，防止非复习日每日刷分。错过的复习日允许补领一次。
      final claimDay = DateTime(date.year, date.month, date.day);
      final start = DateTime.tryParse('${tasks.first['start_time']}');
      final scheduledReview = DateTime.tryParse(
        '${tasks.first['next_review_time']}',
      );
      if (start == null || scheduledReview == null) return null;
      final startDay = DateTime(start.year, start.month, start.day);
      final reviewDay = DateTime(
        scheduledReview.year,
        scheduledReview.month,
        scheduledReview.day,
      );
      if (claimDay.isBefore(startDay) || claimDay.isBefore(reviewDay)) {
        return null;
      }

      await transaction.rawInsert(
        '''
        INSERT OR IGNORE INTO daily_task_reward_logs (task_id, reward_date)
        VALUES (?, ?)
        ''',
        [taskId, rewardDate],
      );
      final insertResult = await transaction.rawQuery(
        'SELECT changes() AS inserted',
      );
      if ((insertResult.first['inserted'] as int) == 0) return null;

      final reward = toInt(tasks.first['daily_points']);
      final stage = toInt(tasks.first['review_stage']);
      final nextReview = nextDailyReviewDate(date, stage);
      await transaction.update(
        'daily_tasks',
        {
          'review_stage': stage + 1,
          'next_review_time': nextReview.toIso8601String(),
        },
        where: 'id = ? AND status_tag = ?',
        whereArgs: [taskId, '进行中'],
      );
      if (reward > 0) {
        await transaction.insert('points', {
          'source_type': 'daily_task',
          'source_id': taskId,
          'point_value': reward,
          'operation_type': '日常任务每日奖励',
          'remark': '完成日常任务：${tasks.first['name']}（$rewardDate 奖励 $reward 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return reward;
    });
  }

  /// B1：习惯型日常任务打卡领奖。
  ///
  /// 与艾宾浩斯复习型的区别：不推进 review_stage/next_review_time，
  /// 仅按 repeat_type/repeat_value 校验当天是否为打卡日；
  /// reward_logs 与复习型共用，同一天同一任务只能领取一次（防刷分）。
  static Future<int?> claimHabitTaskReward({
    required int taskId,
    required DateTime date,
  }) async {
    final db = await AppDatabase.instance.database;
    final claimDate = _date(date);
    final claimDay = DateTime(date.year, date.month, date.day);
    return db.transaction((transaction) async {
      final tasks = await transaction.query(
        'daily_tasks',
        columns: [
          'name',
          'daily_points',
          'status_tag',
          'is_deleted',
          'start_time',
          'task_mode',
          'repeat_type',
          'repeat_value',
        ],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (tasks.isEmpty ||
          tasks.first['status_tag'] != '进行中' ||
          toInt(tasks.first['is_deleted']) != 0 ||
          tasks.first['task_mode'] != 'habit') {
        return null;
      }
      final start = DateTime.tryParse('${tasks.first['start_time']}');
      if (start == null) return null;
      final rule = RepeatRule.fromColumns(
        tasks.first['repeat_type'] as String?,
        tasks.first['repeat_value'] as String?,
      );
      if (!rule.isDueOn(claimDay, start)) return null;

      await transaction.rawInsert(
        '''
        INSERT OR IGNORE INTO daily_task_reward_logs (task_id, reward_date)
        VALUES (?, ?)
        ''',
        [taskId, claimDate],
      );
      final insertResult = await transaction.rawQuery(
        'SELECT changes() AS inserted',
      );
      if ((insertResult.first['inserted'] as int) == 0) return null;

      final reward = toInt(tasks.first['daily_points']);
      if (reward > 0) {
        await transaction.insert('points', {
          'source_type': 'daily_task',
          'source_id': taskId,
          'point_value': reward,
          'operation_type': '日常习惯打卡奖励',
          'remark': '习惯打卡：${tasks.first['name']}'
              '（$claimDate ${rule.displayText} 奖励 $reward 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return reward;
    });
  }

  static Future<int?> advanceHope(int hopeId, DateTime date, {int amount = 1}) async {
    if (amount <= 0) amount = 1;
    final db = await AppDatabase.instance.database;
    final progressDate = _date(date);
    return db.transaction((transaction) async {
      final hopes = await transaction.query(
        'hopes',
        columns: ['progress', 'status'],
        where: 'hope_id = ?',
        whereArgs: [hopeId],
        limit: 1,
      );
      if (hopes.isEmpty ||
          hopes.first['status'] != '进行中' ||
          toInt(hopes.first['progress']) >= 100) {
        return null;
      }

      await transaction.insert('hope_progress_logs', {
        'hope_id': hopeId,
        'progress_date': progressDate,
        'amount': amount,
      });
      final progress = toInt(hopes.first['progress']);
      final nextProgress = (progress + amount).clamp(0, 100);
      await transaction.update(
        'hopes',
        {'progress': nextProgress},
        where: 'hope_id = ?',
        whereArgs: [hopeId],
      );
      return nextProgress;
    });
  }

  static Future<bool> startHope(int hopeId) async {
    final db = await AppDatabase.instance.database;
    final changed = await db.update(
      'hopes',
      {'status': '进行中'},
      where: "hope_id = ? AND status = '未进行'",
      whereArgs: [hopeId],
    );
    return changed == 1;
  }

  /// D1：完成某个希望的分步任务。自动按已完成步骤比例刷新希望总进度，
  /// 全部步骤完成时进度置 100%；步骤本身的奖励积分单独发放。
  static Future<({int progress, int? stepReward})> completeHopeStep(
    int stepId,
    DateTime date,
  ) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final steps = await transaction.query(
        'hope_steps',
        columns: ['step_id', 'hope_id', 'name', 'reward_points', 'status'],
        where: 'step_id = ?',
        whereArgs: [stepId],
        limit: 1,
      );
      if (steps.isEmpty) throw StateError('步骤不存在');
      final step = steps.first;
      if (step['status'] == '已完成') {
        throw StateError('该步骤已完成');
      }
      final hopeId = step['hope_id'] as int;
      final hopeRows = await transaction.query(
        'hopes',
        columns: ['hope_id', 'status'],
        where: 'hope_id = ?',
        whereArgs: [hopeId],
        limit: 1,
      );
      if (hopeRows.isEmpty || hopeRows.first['status'] != '进行中') {
        throw StateError('所属希望未在进行中');
      }
      await transaction.update(
        'hope_steps',
        {
          'status': '已完成',
          'completed_at': _date(date),
          'update_time': DateTime.now().toIso8601String(),
        },
        where: 'step_id = ?',
        whereArgs: [stepId],
      );
      final allSteps = await transaction.query(
        'hope_steps',
        columns: ['status'],
        where: 'hope_id = ?',
        whereArgs: [hopeId],
      );
      final total = allSteps.length;
      final done = allSteps.where((s) => s['status'] == '已完成').length;
      final progress = total == 0 ? 0 : (done * 100 / total).round().clamp(0, 100);
      await transaction.update(
        'hopes',
        {'progress': progress},
        where: 'hope_id = ?',
        whereArgs: [hopeId],
      );
      int? stepReward;
      final reward = toInt(step['reward_points']);
      if (reward > 0) {
        await transaction.insert('points', {
          'source_type': 'hope_step',
          'source_id': stepId,
          'point_value': reward,
          'operation_type': '分步任务奖励',
          'remark': '完成步骤：${step['name']}（+$reward 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
        stepReward = reward;
      }
      return (progress: progress, stepReward: stepReward);
    });
  }

  /// 依据已完成步骤数重算某希望的总进度，返回新进度（0-100）。
  /// 编辑分步希望（增删/改名步骤）后调用，保持进度一致。
  static Future<int> refreshHopeProgress(int hopeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'hope_steps',
      columns: ['status'],
      where: 'hope_id = ?',
      whereArgs: [hopeId],
    );
    final total = rows.length;
    final done = rows.where((s) => s['status'] == '已完成').length;
    final progress =
        total == 0 ? 0 : (done * 100 / total).round().clamp(0, 100);
    await db.update(
      'hopes',
      {'progress': progress},
      where: 'hope_id = ?',
      whereArgs: [hopeId],
    );
    return progress;
  }

  /// 当前积分总余额。
  static Future<int> getPointsBalance() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(point_value), 0) AS balance FROM points',
    );
    return toInt(rows.first['balance']);
  }

  /// 新建一笔支出，可选同时从积分中抵扣 [pointsToDeduct] 分。
  /// 抵扣与支出写入同一事务：余额不足时整笔失败，不产生半截数据。
  /// 返回新建账单的 record_id。
  static Future<int> createExpenseWithDeduction({
    required Map<String, Object?> values,
    required int pointsToDeduct,
  }) async {
    if (pointsToDeduct < 0) {
      throw ArgumentError.value(pointsToDeduct, 'pointsToDeduct', '不能为负数');
    }
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      if (pointsToDeduct > 0) {
        final balanceRows = await transaction.rawQuery(
          'SELECT COALESCE(SUM(point_value), 0) AS balance FROM points',
        );
        final balance = toInt(balanceRows.first['balance']);
        if (pointsToDeduct > balance) {
          throw StateError('积分余额不足（当前余额 $balance 分）');
        }
      }
      final recordId = await transaction.insert('income_expenses', {
        ...values,
        'points_deducted': pointsToDeduct,
      });
      if (pointsToDeduct > 0) {
        final category = values['category'] as String? ?? '';
        final remark = (values['remark'] as String? ?? '').trim();
        final target = remark.isEmpty ? category : '$category（$remark）';
        await transaction.insert('points', {
          'source_type': 'expense_deduction',
          'source_id': recordId,
          'point_value': -pointsToDeduct,
          'operation_type': '支出积分抵扣',
          'remark': '支出积分抵扣：$target（扣除 $pointsToDeduct 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return recordId;
    });
  }

  /// 删除支出记录；若该笔曾抵扣积分，则退还等额积分，避免误删丢分。
  static Future<int> deleteExpenseAndRefund(int recordId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'income_expenses',
        columns: ['points_deducted', 'category', 'remark'],
        where: 'record_id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final deducted = toInt(rows.first['points_deducted']);
      final changed = await transaction.delete(
        'income_expenses',
        where: 'record_id = ?',
        whereArgs: [recordId],
      );
      if (changed == 1 && deducted > 0) {
        final category = rows.first['category'] as String? ?? '';
        await transaction.insert('points', {
          'source_type': 'expense_refund',
          'source_id': recordId,
          'point_value': deducted,
          'operation_type': '支出抵扣退还',
          'remark': '删除支出“$category”退还抵扣积分 $deducted 分',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return changed;
    });
  }

  static Future<bool> startWish(int wishId) async {
    final db = await AppDatabase.instance.database;
    final changed = await db.update(
      'wishes',
      {'status': WishStatus.inProgress},
      where: 'wish_id = ? AND status = ? AND current_points = 0',
      whereArgs: [wishId, WishStatus.notStarted],
    );
    return changed == 1;
  }

  static Future<int?> redeemHope(int hopeId, DateTime date) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'hopes',
        columns: ['name', 'progress', 'reward_points', 'status'],
        where: 'hope_id = ?',
        whereArgs: [hopeId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('希望不存在');
      if (rows.first['status'] != '进行中' ||
          toInt(rows.first['progress']) < 100) {
        throw StateError('希望进度达到 100% 后才能兑换');
      }
      final changed = await transaction.update(
        'hopes',
        {'status': '已兑换', 'redeemed_at': _date(date)},
        where: "hope_id = ? AND status = '进行中' AND progress >= 100",
        whereArgs: [hopeId],
      );
      if (changed != 1) return null;
      final reward = toInt(rows.first['reward_points']);
      if (reward > 0) {
        await transaction.insert('points', {
          'source_type': 'hope',
          'source_id': hopeId,
          'point_value': reward,
          'operation_type': '希望完成奖励',
          'remark': '达成希望：${rows.first['name']}（奖励 $reward 积分）',
          'create_time': DateTime.now().toIso8601String(),
        });
      }
      return reward;
    });
  }

  static Future<int> contributeToWish({
    required int wishId,
    required int pointsToSpend,
  }) async {
    if (pointsToSpend <= 0) {
      throw ArgumentError.value(pointsToSpend, 'pointsToSpend', '必须大于零');
    }
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final wishes = await transaction.query(
        'wishes',
        columns: ['name', 'required_points', 'current_points', 'status'],
        where: 'wish_id = ?',
        whereArgs: [wishId],
        limit: 1,
      );
      if (wishes.isEmpty) throw StateError('愿望不存在');
      if (WishStatus.isTerminal(wishes.first['status'] as String?)) {
        throw StateError('该愿望已兑换');
      }
      final requiredPoints = toInt(wishes.first['required_points']);
      final currentPoints = toInt(wishes.first['current_points']);
      if (requiredPoints <= 0) throw StateError('愿望目标积分无效');
      final balanceRows = await transaction.rawQuery(
        'SELECT COALESCE(SUM(point_value), 0) AS balance FROM points',
      );
      final balance = toInt(balanceRows.first['balance']);
      if (pointsToSpend > balance) throw StateError('积分余额不足');
      if (pointsToSpend > requiredPoints - currentPoints) {
        throw StateError('兑换积分超过愿望剩余进度');
      }

      final redemptionId = await transaction.insert('wish_redemptions', {
        'wish_id': wishId,
        'points_spent': pointsToSpend,
      });
      final nextProgress = currentPoints + pointsToSpend;
      final changed = await transaction.update(
        'wishes',
        {
          'current_points': nextProgress,
          'status': nextProgress >= requiredPoints
              ? WishStatus.readyToRedeem
              : nextProgress > 0
              ? WishStatus.inProgress
              : WishStatus.notStarted,
        },
        where: 'wish_id = ? AND status NOT IN (?, ?)',
        whereArgs: [wishId, WishStatus.redeemed, WishStatus.completed],
      );
      if (changed != 1) throw StateError('愿望状态已改变，请刷新后重试');
      await transaction.insert('points', {
        'source_type': 'wish_redemption',
        'source_id': redemptionId,
        'point_value': -pointsToSpend,
        'operation_type': '愿望兑换',
        'remark': '兑换愿望：${wishes.first['name']}（投入 $pointsToSpend 积分）',
        'create_time': DateTime.now().toIso8601String(),
      });
      return pointsToSpend;
    });
  }

  static Future<bool> redeemWish(int wishId, DateTime date) async {
    final db = await AppDatabase.instance.database;
    final changed = await db.update(
      'wishes',
      {'status': WishStatus.redeemed, 'redeemed_at': _date(date)},
      where:
          'wish_id = ? AND status NOT IN (?, ?) '
          'AND current_points >= required_points',
      whereArgs: [wishId, WishStatus.redeemed, WishStatus.completed],
    );
    return changed == 1;
  }

  static Future<void> deleteWishAndRefund(int wishId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final rows = await transaction.query(
        'wishes',
        columns: ['name', 'status'],
        where: 'wish_id = ?',
        whereArgs: [wishId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if (rows.first['status'] != WishStatus.redeemed) {
        final spent = await transaction.rawQuery(
          'SELECT COALESCE(SUM(points_spent), 0) AS total '
          'FROM wish_redemptions WHERE wish_id = ?',
          [wishId],
        );
        final refund = toInt(spent.first['total']);
        if (refund > 0) {
          await transaction.insert('points', {
            'source_type': 'wish_refund',
            'source_id': wishId,
            'point_value': refund,
            'operation_type': '愿望退款',
            'remark': '删除愿望“${rows.first['name']}”退还积分',
            'create_time': DateTime.now().toIso8601String(),
          });
        }
      }
      await transaction.delete(
        'wish_redemptions',
        where: 'wish_id = ?',
        whereArgs: [wishId],
      );
      await transaction.delete(
        'desire_logs',
        where: 'item_type = ? AND item_id = ?',
        whereArgs: ['wish', wishId],
      );
      await transaction.delete(
        'wishes',
        where: 'wish_id = ?',
        whereArgs: [wishId],
      );
    });
  }

  static Future<void> deleteHope(int hopeId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'desire_logs',
        where: 'item_type = ? AND item_id = ?',
        whereArgs: ['hope', hopeId],
      );
      await transaction.delete(
        'hopes',
        where: 'hope_id = ?',
        whereArgs: [hopeId],
      );
    });
  }

  static Future<FoodPointExchange?> exchangeTodayFoodBalance(
    DateTime date,
  ) async {
    final db = await AppDatabase.instance.database;
    final exchangeDate = _date(date);
    return db.transaction((transaction) async {
      final existing = await transaction.query(
        'food_point_exchanges',
        where: 'exchange_date = ?',
        whereArgs: [exchangeDate],
        limit: 1,
      );
      if (existing.isNotEmpty) return null;

      // 饭钱改为用户每日自行记账：当天没有任何手动饭钱记录时
      // 不结算、不发积分，防止“不吃饭 = 结余全额兑积分”的刷分入口。
      // 历史自动记录（remark='自动添加每日饭钱'）不计为手动记录。
      final foodCountRows = await transaction.rawQuery(
        '''
        SELECT COUNT(*) AS cnt
        FROM income_expenses
        WHERE type = ? AND category = ? AND record_date = ?
          AND (remark IS NULL OR remark != '自动添加每日饭钱')
        ''',
        ['支出', '今日饭钱', exchangeDate],
      );
      if (toInt(foodCountRows.first['cnt']) == 0) return null;

      final budgets = await transaction.rawQuery(
        '''
        SELECT value
        FROM (
          SELECT budget_amount AS value
          FROM budget_history
          WHERE budget_date <= ?
          ORDER BY budget_date DESC
          LIMIT 1
        )
        UNION ALL
        SELECT value
        FROM app_settings
        WHERE key = ? AND NOT EXISTS (
          SELECT 1 FROM budget_history WHERE budget_date <= ?
        )
        LIMIT 1
        ''',
        [exchangeDate, 'daily_food_budget', exchangeDate],
      );
      final budget = budgets.isEmpty ? 0.0 : toDouble(budgets.first['value']);
      if (!budget.isFinite || budget < 0) {
        throw StateError('今日饭钱预算必须是有效的非负金额');
      }
      final spentRows = await transaction.rawQuery(
        '''
        SELECT COALESCE(SUM(amount), 0) AS spent
        FROM income_expenses
        WHERE type = ? AND category = ? AND record_date = ?
          AND (remark IS NULL OR remark != '自动添加每日饭钱')
        ''',
        ['支出', '今日饭钱', exchangeDate],
      );
      final spent = toDouble(spentRows.first['spent']);
      final remaining = budget - spent;
      final clampedRemaining = remaining.clamp(0.0, budget);
      final points = foodPointsForBalance(clampedRemaining);

      await transaction.insert('food_point_exchanges', {
        'exchange_date': exchangeDate,
        'amount': clampedRemaining,
        'points': points,
      });
      if (points > 0) {
        await transaction.insert('points', {
          'source_type': 'food_balance',
          'source_id': _dateKey(date),
          'point_value': points,
          'operation_type': '饭钱兑换',
          'remark': '饭钱结余 ¥${clampedRemaining.toStringAsFixed(2)} 自动兑换',
          'create_time': DateTime.now().toIso8601String(),
        });
      }

      if (remaining < 0) {
        final overage = -remaining;
        final overagePoints =
            (overage * AppConstants.foodOveragePointsPerYuan).ceil();
        if (overagePoints > 0) {
          await transaction.insert('points', {
            'source_type': 'food_overage',
            'source_id': _dateKey(date),
            'point_value': -overagePoints,
            'operation_type': '饭钱超支扣除',
            'remark': '饭钱超支 ¥${overage.toStringAsFixed(2)} 扣除 $overagePoints 积分',
            'create_time': DateTime.now().toIso8601String(),
          });
        }
      }

      return FoodPointExchange(amount: clampedRemaining, points: points);
    });
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int _dateKey(DateTime value) =>
      value.year * 10000 + value.month * 100 + value.day;

  /// 结算日常任务未完成扣除：检查所有进行中的日常任务，如果下次复习时间已过
  /// （超过1天未领取奖励），则扣除相应的惩罚积分。每个任务每天只扣除一次。
  static Future<void> settleDailyTaskPenalties() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tasks = await db.query(
      'daily_tasks',
      columns: [
        'id',
        'name',
        'daily_points',
        'penalty_points',
        'next_review_time',
        'task_mode',
      ],
      where: "status_tag = '进行中' AND is_deleted = 0",
    );

    await db.transaction((txn) async {
      for (final task in tasks) {
        final penalty = toInt(task['penalty_points']);
        if (penalty <= 0) continue;
        // B1：自定义习惯型任务按打卡日领奖、不适用艾宾浩斯逾期扣分。
        if (task['task_mode'] == 'habit') continue;

        final nextReview = DateTime.tryParse('${task['next_review_time']}');
        if (nextReview == null) continue;

        final reviewDay = DateTime(
          nextReview.year,
          nextReview.month,
          nextReview.day,
        );
        final daysOverdue = today.difference(reviewDay).inDays;

        if (daysOverdue > 1) {
          final taskId = toInt(task['id']);
          final penaltyDate = _date(today);

          final existing = await txn.query(
            'points',
            columns: ['points_id'],
            where:
                'source_type = ? AND source_id = ? AND operation_type = ? '
                'AND DATE(create_time) = ?',
            whereArgs: [
              'daily_task_penalty',
              taskId,
              '日常任务未完成扣除',
              penaltyDate,
            ],
            limit: 1,
          );

          if (existing.isEmpty) {
            await txn.insert('points', {
              'source_type': 'daily_task_penalty',
              'source_id': taskId,
              'point_value': -penalty,
              'operation_type': '日常任务未完成扣除',
              'remark': '日常任务逾期：${task['name']}（逾期 $daysOverdue 天扣除 $penalty 积分）',
              'create_time': now.toIso8601String(),
            });
          }
        }
      }
    });
  }
}
