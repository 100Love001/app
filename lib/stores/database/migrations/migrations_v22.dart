import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v22：体重 / 心情记录与任务彻底解耦。
/// 历史上记录挂在任务上（task_kind/task_id 指向来源任务），
/// 现改为应用级全局记录（约定 task_kind='app'、task_id=0），
/// 首页独立的体重 / 心情页面统一展示，不再依附任何任务。
class MigrationV22 extends Migration {
  @override
  int get targetVersion => 22;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      "UPDATE task_weight_records SET task_kind = 'app', task_id = 0",
    );
    await db.execute(
      "UPDATE task_mood_records SET task_kind = 'app', task_id = 0",
    );
  }
}
