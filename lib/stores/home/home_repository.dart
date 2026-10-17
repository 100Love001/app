import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/date_range.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/viewmodels/home/home_view_model.dart';

class HomeAnniversary {
  const HomeAnniversary({
    required this.title,
    required this.note,
    required this.tag,
    required this.nextDate,
  });

  final String title;
  final String note;
  final String tag;
  final DateTime nextDate;

  int daysUntil(DateTime date) {
    final today = DateTime(date.year, date.month, date.day);
    return nextDate.difference(today).inDays;
  }
}

class HomeRepository {
  const HomeRepository();

  /// 读取用户设为“目标”的愿望及其投入进度；未设置或已删除返回 null。
  /// 目标一旦达成（已兑换）也返回 null，首页自动隐藏卡片。
  Future<WishGoalProgress?> loadWishGoal() async {
    final goalId = AppSettingsController.instance.wishGoalId;
    if (goalId == null) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'wishes',
      columns: ['wish_id', 'name', 'current_points', 'required_points', 'status'],
      where: 'wish_id = ?',
      whereArgs: [goalId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    // 已兑换/已完成的愿望不再是目标，首页不再牵引。
    final status = row['status'] as String?;
    if (status == '已兑换' || status == '已完成') return null;
    return WishGoalProgress(
      wishId: toInt(row['wish_id']),
      name: row['name'] as String? ?? '',
      currentPoints: toInt(row['current_points']),
      requiredPoints: toInt(row['required_points']),
    );
  }

  Future<List<HomeAnniversary>> loadAnniversaries(DateTime date) async {
    final db = await AppDatabase.instance.database;
    final dayStart = DateTime(date.year, date.month, date.day);
    final rows = await db.query('anniversaries');
    final allAnniversaries = <HomeAnniversary>[];
    for (final item in rows) {
      final eventDate = DateTime.tryParse('${item['event_date']}');
      if (eventDate == null) continue;
      final calendarType = item['calendar_type'] as int? ?? 0;
      final repeatType = item['repeat_type'] as int? ?? 1;
      final repeatCustomDays = item['repeat_custom_days'] as int? ?? 0;
      final nextDate = computeNextAnniversaryDate(
        eventDate: eventDate,
        today: date,
        calendarType: calendarType,
        repeatType: repeatType,
        repeatCustomDays: repeatCustomDays,
      );
      if (nextDate.isBefore(dayStart)) continue;
      allAnniversaries.add(
        HomeAnniversary(
          title: item['title'] as String,
          note: item['note'] as String? ?? '',
          tag: (item['tag'] as String? ?? '').trim(),
          nextDate: nextDate,
        ),
      );
    }
    allAnniversaries.sort(
      (first, second) => first.daysUntil(date).compareTo(second.daysUntil(date)),
    );

    final within100 = allAnniversaries
        .where((anniversary) => anniversary.daysUntil(date) <= 100)
        .toList();
    if (within100.length >= 5) {
      return within100.take(5).toList();
    }

    final beyond100 = allAnniversaries
        .where((anniversary) => anniversary.daysUntil(date) > 100)
        .toList();
    final supplementCount = 5 - within100.length;
    return [
      ...within100,
      ...beyond100.take(supplementCount),
    ];
  }
}
