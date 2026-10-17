import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/time.dart';

/// 单日积分收支。
class PointsDayStat {
  const PointsDayStat({
    required this.day,
    required this.income,
    required this.expense,
  });

  final String day;
  final int income;
  final int expense;
}

/// 任务完成概览。
class TaskCompletionStat {
  const TaskCompletionStat({
    required this.todayDone,
    required this.weekRewards,
    required this.streak,
    required this.specialDone,
    required this.specialTotal,
  });

  final int todayDone;
  final int weekRewards;
  final int streak;
  final int specialDone;
  final int specialTotal;
}

/// 支出分类占比项。
class CategoryAmount {
  const CategoryAmount({required this.category, required this.amount});

  final String category;
  final double amount;
}

/// 愿望进度项。
class WishProgressItem {
  const WishProgressItem({
    required this.name,
    required this.currentPoints,
    required this.requiredPoints,
    required this.status,
  });

  final String name;
  final int currentPoints;
  final int requiredPoints;
  final String status;

  double get ratio =>
      requiredPoints <= 0 ? 0 : (currentPoints / requiredPoints).clamp(0, 1);
}

class AnalysisData {
  const AnalysisData({
    required this.pointsTrend,
    required this.tasks,
    required this.monthIncome,
    required this.monthExpense,
    required this.topExpenseCategories,
    required this.activeWishes,
    required this.redeemedWishCount,
  });

  final List<PointsDayStat> pointsTrend;
  final TaskCompletionStat tasks;
  final double monthIncome;
  final double monthExpense;
  final List<CategoryAmount> topExpenseCategories;
  final List<WishProgressItem> activeWishes;
  final int redeemedWishCount;
}

/// 数据分析：积分趋势、任务完成、财务收支、愿望进度四个维度的只读统计。
class AnalysisRepository {
  const AnalysisRepository();

  Future<AnalysisData> load() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final todayKey = TimeUtil.toDateKey(now);

    // ---- 积分收支趋势（近 14 天，缺日补 0）----
    final trendStart = now.subtract(const Duration(days: 13));
    final trendRows = await db.rawQuery(
      'SELECT substr(create_time, 1, 10) AS day, '
      'SUM(CASE WHEN point_value > 0 THEN point_value ELSE 0 END) AS income, '
      'SUM(CASE WHEN point_value < 0 THEN -point_value ELSE 0 END) AS expense '
      'FROM points WHERE substr(create_time, 1, 10) >= ? '
      'GROUP BY day',
      [TimeUtil.toDateKey(trendStart)],
    );
    final trendByDay = {
      for (final row in trendRows)
        row['day'] as String: (
          income: toInt(row['income']),
          expense: toInt(row['expense']),
        ),
    };
    final pointsTrend = <PointsDayStat>[];
    for (var i = 0; i < 14; i++) {
      final day = trendStart.add(Duration(days: i));
      final key = TimeUtil.toDateKey(day);
      final stat = trendByDay[key];
      pointsTrend.add(
        PointsDayStat(
          day: key,
          income: stat?.income ?? 0,
          expense: stat?.expense ?? 0,
        ),
      );
    }

    // ---- 任务完成统计 ----
    final todayRows = await db.rawQuery(
      'SELECT COUNT(DISTINCT task_id) AS c FROM daily_task_reward_logs '
      'WHERE reward_date = ?',
      [todayKey],
    );
    final todayDaily = toInt(todayRows.first['c']);
    final todaySpecialRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM special_tasks "
      "WHERE is_deleted = 0 AND completed_at IS NOT NULL "
      "AND substr(completed_at, 1, 10) = ?",
      [todayKey],
    );
    final todayDone = todayDaily + toInt(todaySpecialRows.first['c']);

    final weekStart = TimeUtil.toDateKey(
      now.subtract(const Duration(days: 6)),
    );
    final weekRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM daily_task_reward_logs '
      'WHERE reward_date >= ?',
      [weekStart],
    );
    final weekRewards = toInt(weekRows.first['c']);

    final specialRows = await db.rawQuery(
      "SELECT "
      "SUM(CASE WHEN status_tag = '已完成' THEN 1 ELSE 0 END) AS done, "
      'COUNT(*) AS total '
      'FROM special_tasks WHERE is_deleted = 0',
    );
    final specialDone = toInt(specialRows.first['done']);
    final specialTotal = toInt(specialRows.first['total']);

    // 连续打卡：以今天为终点向前回推有领奖记录的连续自然日数。
    var streak = 0;
    var day = DateTime(now.year, now.month, now.day);
    while (true) {
      final rows = await db.rawQuery(
        'SELECT 1 FROM daily_task_reward_logs WHERE reward_date = ? LIMIT 1',
        [TimeUtil.toDateKey(day)],
      );
      if (rows.isEmpty) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
      if (streak > 3650) break;
    }

    // ---- 财务收支（本月）----
    final monthKey = todayKey.substring(0, 7);
    final financeRows = await db.rawQuery(
      'SELECT type, SUM(amount) AS total FROM income_expenses '
      'WHERE substr(record_date, 1, 7) = ? GROUP BY type',
      [monthKey],
    );
    var monthIncome = 0.0;
    var monthExpense = 0.0;
    for (final row in financeRows) {
      if (row['type'] == '收入') {
        monthIncome = toDouble(row['total']);
      } else {
        monthExpense = toDouble(row['total']);
      }
    }
    final categoryRows = await db.rawQuery(
      'SELECT category, SUM(amount) AS total FROM income_expenses '
      "WHERE type = '支出' AND substr(record_date, 1, 7) = ? "
      'GROUP BY category ORDER BY total DESC LIMIT 5',
      [monthKey],
    );
    final topExpenseCategories = [
      for (final row in categoryRows)
        CategoryAmount(
          category: '${row['category']}',
          amount: toDouble(row['total']),
        ),
    ];

    // ---- 愿望进度回顾 ----
    final wishRows = await db.query(
      'wishes',
      columns: ['name', 'current_points', 'required_points', 'status'],
      orderBy: 'sort, wish_id',
    );
    final activeWishes = <WishProgressItem>[];
    var redeemedWishCount = 0;
    for (final row in wishRows) {
      final status = '${row['status']}';
      if (status == '已兑换' || status == '已完成') {
        redeemedWishCount++;
        continue;
      }
      activeWishes.add(
        WishProgressItem(
          name: '${row['name']}',
          currentPoints: toInt(row['current_points']),
          requiredPoints: toInt(row['required_points']),
          status: status,
        ),
      );
    }

    return AnalysisData(
      pointsTrend: pointsTrend,
      tasks: TaskCompletionStat(
        todayDone: todayDone,
        weekRewards: weekRewards,
        streak: streak,
        specialDone: specialDone,
        specialTotal: specialTotal,
      ),
      monthIncome: monthIncome,
      monthExpense: monthExpense,
      topExpenseCategories: topExpenseCategories,
      activeWishes: activeWishes,
      redeemedWishCount: redeemedWishCount,
    );
  }
}
