import 'package:app/stores/database/data/sql.dart';
import 'package:app/stores/database/migrations/migration.dart';
import 'package:app/utils/time.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v20：任务奖惩与动态组件。
/// 1. 三类任务表新增 enable_penalty（逾期扣分开关）、component_json（动态组件）；
///    长期任务表 tasks 补齐奖惩列与 completed_at；
/// 2. points 新增 biz_key 业务幂等键（部分唯一索引），同一任务同一周期
///    的逾期扣分无论扫描多少次只入账一次；
/// 3. 新增 task_weight_records / task_mood_records，支撑组件化的体重、
///    心情多次记录与趋势图；
/// 4. 写入习惯扣分锚点日期：升级前错过的打卡日不追溯扣分，
///    仅对锚点日期之后错过的打卡日生效。
class MigrationV20 extends Migration {
  @override
  int get targetVersion => 20;

  @override
  Future<void> up(Database db) async {
    // 长期任务表补齐奖惩与组件字段。
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN reward_points INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN penalty_points INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN enable_penalty INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute('ALTER TABLE tasks ADD COLUMN component_json TEXT');
    await db.execute('ALTER TABLE tasks ADD COLUMN completed_at TEXT');

    // 特殊短期、日常（含习惯）任务。
    await db.execute(
      'ALTER TABLE special_tasks ADD COLUMN enable_penalty INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute(
      'ALTER TABLE special_tasks ADD COLUMN component_json TEXT',
    );
    await db.execute(
      'ALTER TABLE daily_tasks ADD COLUMN enable_penalty INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute('ALTER TABLE daily_tasks ADD COLUMN component_json TEXT');

    // 积分流水幂等键（历史流水保持 NULL，不参与唯一约束）。
    await db.execute('ALTER TABLE points ADD COLUMN biz_key TEXT');
    await db.execute(TableSql.createPointsBizKeyIndex);

    // 组件记录表。
    await db.execute(TableSql.createTaskWeightRecords);
    await db.execute(TableSql.createTaskMoodRecords);
    await db.execute(TableSql.createTaskRecordIndexes);
    await db.execute(TableSql.createTaskMoodRecordIndexes);
    await db.execute(TableSql.createTaskPenaltyIndex);

    // 习惯扣分锚点：升级当日之前不追溯。
    await db.rawInsert(
      'INSERT OR IGNORE INTO app_settings(key, value) VALUES(?, ?)',
      ['habit_penalty_anchor_date', TimeUtil.toDateKey(DateTime.now())],
    );
  }
}
