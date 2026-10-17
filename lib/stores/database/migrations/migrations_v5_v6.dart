import 'package:app/stores/database/data/sql.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String column,
  String alterSql,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.any((info) => info['name'] == column)) return;
  await db.execute(alterSql);
}

class MigrationV5 extends Migration {
  @override
  int get targetVersion => 5;

  @override
  Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db, 'hopes', 'progress',
      'ALTER TABLE hopes ADD COLUMN progress INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db, 'special_tasks', 'reward_points',
      'ALTER TABLE special_tasks ADD COLUMN reward_points INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db, 'daily_tasks', 'daily_points',
      'ALTER TABLE daily_tasks ADD COLUMN daily_points INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('ALTER TABLE desire_logs RENAME TO desire_logs_v4');
    await db.execute(TableSql.createDesireLogs);
    await db.execute('''
      INSERT INTO desire_logs (id, item_type, item_id, desire_date, amount)
      SELECT id, item_type, item_id, desire_date, amount FROM desire_logs_v4
    ''');
    await db.execute('DROP TABLE desire_logs_v4');
    for (final sql in [
      TableSql.createHopeProgressLogs,
      TableSql.createWishRedemptions,
      TableSql.createFoodPointExchanges,
    ]) {
      await db.execute(sql);
    }
    final points = await db.rawQuery('SELECT COUNT(*) AS count FROM points');
    if ((points.first['count'] as int) == 0) {
      final settings = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['total_points'],
        limit: 1,
      );
      final openingBalance = settings.isEmpty
          ? 0
          : int.tryParse(settings.first['value'] as String) ?? 0;
      if (openingBalance != 0) {
        await db.insert('points', {
          'source_type': 'initial',
          'source_id': 1,
          'point_value': openingBalance,
          'operation_type': '奖励',
          'remark': '迁移前积分余额',
        });
      }
    }
  }
}

class MigrationV6 extends Migration {
  @override
  int get targetVersion => 6;

  @override
  Future<void> up(Database db) async {
    await db.execute(TableSql.createDailyTaskRewardLogs);
    await db.execute(
      "UPDATE daily_tasks SET status_tag = '进行中' WHERE status_tag = '已完成'",
    );
  }
}
