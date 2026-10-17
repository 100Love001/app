import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/foundation.dart';

/// 特殊语录（时光信箱）：写下话语并设定未来解锁日期。
/// 到时间前内容对所有列表保密（仅可见“在路上”的数量），
/// 到时间后在首页以礼物卡展示并在通知栏推送，开启后进入已解锁列表。
class TimeCapsuleRepository extends ChangeNotifier {
  TimeCapsuleRepository._();

  static final TimeCapsuleRepository instance = TimeCapsuleRepository._();

  /// 写入新语录。解锁日期必须晚于今天，内容不能为空。
  Future<int> create({
    required String content,
    required DateTime unlockDate,
  }) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('内容不能为空');
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final unlockStart = DateTime(
      unlockDate.year,
      unlockDate.month,
      unlockDate.day,
    );
    if (!unlockStart.isAfter(todayStart)) {
      throw ArgumentError('解锁日期必须是将来的某一天');
    }
    final db = await AppDatabase.instance.database;
    final id = await db.insert('time_capsules', {
      'content': text,
      'unlock_date': TimeUtil.toDateKey(unlockStart),
    });
    notifyListeners();
    return id;
  }

  /// 已到解锁日期的语录（可查看内容），按解锁日倒序。
  Future<List<Map<String, dynamic>>> unlocked() async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'time_capsules',
      where: 'unlock_date <= ?',
      whereArgs: [TimeUtil.toDateKey(DateTime.now())],
      orderBy: 'unlock_date DESC, id DESC',
    );
  }

  /// 仍在路上的数量（内容保密，只展示数量）。
  Future<int> pendingCount() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM time_capsules WHERE unlock_date > ?',
      [TimeUtil.toDateKey(DateTime.now())],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 已到时间但尚未开启的语录，供首页礼物卡逐条开启。
  Future<List<Map<String, dynamic>>> unopened() async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'time_capsules',
      where: 'unlock_date <= ? AND opened = 0',
      whereArgs: [TimeUtil.toDateKey(DateTime.now())],
      orderBy: 'unlock_date, id',
    );
  }

  Future<void> markOpened(int id) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'time_capsules',
      {'opened': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('time_capsules', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }
}
