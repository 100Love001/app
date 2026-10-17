import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/num_cast.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MoodRepository {
  MoodRepository._();
  static final MoodRepository instance = MoodRepository._();
  final _database = AppDatabase.instance;

  String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> tags() =>
      _database.rawQuery('SELECT * FROM mood_tag ORDER BY id');

  Future<Map<String, dynamic>?> recordForDate(DateTime date) async {
    final rows = await _database.rawQuery(
      'SELECT mood_record.*, mood_tag.name AS tag_name '
      'FROM mood_record JOIN mood_tag ON mood_tag.id = mood_record.tag_id '
      'WHERE record_date = ?',
      [dateKey(date)],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> recordsForMonth(int year, int month) =>
      _database.rawQuery(
        'SELECT mood_record.*, mood_tag.name AS tag_name '
        'FROM mood_record JOIN mood_tag ON mood_tag.id = mood_record.tag_id '
        'WHERE record_date >= ? AND record_date < ? ORDER BY record_date DESC',
        [dateKey(DateTime(year, month)), dateKey(DateTime(year, month + 1))],
      );

  Future<bool> addRecord({
    required int tagId,
    required String? reason,
    required DateTime date,
  }) async {
    final db = await _database.database;
    final recordDate = dateKey(date);
    try {
      await db.transaction((txn) async {
        await txn.insert('mood_record', {
          'tag_id': tagId,
          'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
          'record_date': recordDate,
          'create_timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        await txn.rawInsert(
          'INSERT INTO mood_month_stat '
          '(year, month, tag_id, count, updated_at) VALUES (?, ?, ?, 1, ?) '
          'ON CONFLICT(year, month, tag_id) DO UPDATE SET '
          'count = count + 1, updated_at = excluded.updated_at',
          [date.year, date.month, tagId, DateTime.now().millisecondsSinceEpoch],
        );
      });
      return true;
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) return false;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> monthStats(int year, int month) =>
      _database.rawQuery(
        '''
        SELECT mood_record.tag_id, mood_tag.name AS tag_name,
          COUNT(*) AS count
        FROM mood_record
        JOIN mood_tag ON mood_tag.id = mood_record.tag_id
        WHERE mood_record.record_date >= ? AND mood_record.record_date < ?
        GROUP BY mood_record.tag_id, mood_tag.name
        ORDER BY count DESC
        ''',
        [dateKey(DateTime(year, month)), dateKey(DateTime(year, month + 1))],
      );

  /// 读取年统计前先按 mood_record 重算该年各月统计（幂等），
  /// 自愈 month_stat 与明细之间可能的漂移，rebuildMonthStats 不再是无入口死方法。
  Future<List<Map<String, dynamic>>> yearStats(int year) async {
    for (var month = 1; month <= 12; month++) {
      await rebuildMonthStats(year, month);
    }
    return _database.rawQuery(
      'SELECT mood_month_stat.tag_id, mood_tag.name AS tag_name, '
      'SUM(mood_month_stat.count) AS count '
      'FROM mood_month_stat JOIN mood_tag ON mood_tag.id = mood_month_stat.tag_id '
      'WHERE year = ? GROUP BY mood_month_stat.tag_id ORDER BY count DESC',
      [year],
    );
  }

  Future<List<Map<String, dynamic>>> recentMonthCounts({
    required int months,
    required DateTime endingAt,
  }) async {
    if (months < 1) throw ArgumentError.value(months, 'months');
    final end = DateTime(endingAt.year, endingAt.month + 1);
    final start = DateTime(end.year, end.month - months);
    final rows = await _database.rawQuery(
      '''
      SELECT substr(record_date, 1, 7) AS month_key, COUNT(*) AS count
      FROM mood_record
      WHERE record_date >= ? AND record_date < ?
      GROUP BY substr(record_date, 1, 7)
      ''',
      [dateKey(start), dateKey(end)],
    );
    final counts = {
      for (final row in rows)
        row['month_key'] as String: toInt(row['count']),
    };
    return [
      for (var offset = months - 1; offset >= 0; offset--)
        () {
          final month = DateTime(end.year, end.month - offset - 1);
          final key =
              '${month.year.toString().padLeft(4, '0')}-'
              '${month.month.toString().padLeft(2, '0')}';
          return {'month_label': '${month.month}月', 'count': counts[key] ?? 0};
        }(),
    ];
  }

  Future<void> rebuildMonthStats(int year, int month) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'mood_month_stat',
        where: 'year = ? AND month = ?',
        whereArgs: [year, month],
      );
      await txn.rawInsert(
        'INSERT INTO mood_month_stat (year, month, tag_id, count, updated_at) '
        'SELECT ?, ?, tag_id, COUNT(*), ? FROM mood_record '
        'WHERE record_date >= ? AND record_date < ? GROUP BY tag_id',
        [
          year,
          month,
          DateTime.now().millisecondsSinceEpoch,
          dateKey(DateTime(year, month)),
          dateKey(DateTime(year, month + 1)),
        ],
      );
    });
  }

  Future<bool> hasReport(int year, int month, String type) async {
    final rows = await _database.rawQuery(
      'SELECT id FROM mood_report_log WHERE year = ? AND month = ? AND report_type = ?',
      [year, month, type],
    );
    return rows.isNotEmpty;
  }

  Future<void> markReport(int year, int month, String type) =>
      _database.insert('mood_report_log', {
        'year': year,
        'month': month,
        'report_type': type,
        'generated_at': DateTime.now().millisecondsSinceEpoch,
      });
}
