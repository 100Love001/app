import 'package:app/stores/database/data/sql.dart';
import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v21：任务动态组件「数据分析」记录表（数值 + 日期，
/// 支撑折线 / 柱状 / 饼图 / 表格多种图表形态）。
class MigrationV21 extends Migration {
  @override
  int get targetVersion => 21;

  @override
  Future<void> up(Database db) async {
    await db.execute(TableSql.createTaskDataRecords);
    await db.execute(TableSql.createTaskDataRecordIndexes);
  }
}
