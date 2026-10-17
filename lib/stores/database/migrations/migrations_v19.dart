import 'package:app/stores/database/data/init_data.dart';
import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v19：账单体系动态化。
/// 1. finance_categories 增加结算周期、预算、结余兑换比例、超支扣除比例；
/// 2. 原饭钱预算（daily_food_budget）与兑换比例（food_points_per_yuan）
///    迁移到「今日饭钱」分类行；
/// 3. 新增 category_settlements 周期结算表，并为存量用户写入结算锚点，
///    避免升级后追溯补发历史周期的积分。
class MigrationV19 extends Migration {
  @override
  int get targetVersion => 19;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      "ALTER TABLE finance_categories ADD COLUMN period_type TEXT NOT NULL DEFAULT 'none'",
    );
    await db.execute(
      'ALTER TABLE finance_categories ADD COLUMN budget REAL NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE finance_categories ADD COLUMN balance_rate INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE finance_categories ADD COLUMN overage_rate INTEGER NOT NULL DEFAULT 0',
    );

    // 历史默认支出分类按季度结算；饭钱保持每日结算。
    await db.update(
      'finance_categories',
      {'period_type': 'quarterly'},
      where: "type = '支出' AND name != '今日饭钱'",
    );
    await db.execute('''
      UPDATE finance_categories
      SET period_type = 'daily',
          budget = COALESCE(
            (SELECT CAST(value AS REAL) FROM app_settings
             WHERE key = 'daily_food_budget'), 40),
          balance_rate = COALESCE(
            (SELECT CAST(value AS INTEGER) FROM app_settings
             WHERE key = 'food_points_per_yuan'), 5),
          overage_rate = 15
      WHERE type = '支出' AND name = '今日饭钱'
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS category_settlements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_name TEXT NOT NULL,
        period_type TEXT NOT NULL,
        period_key TEXT NOT NULL,
        spent REAL NOT NULL DEFAULT 0,
        budget REAL NOT NULL DEFAULT 0,
        points INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now','localtime')),
        UNIQUE(category_name, period_type, period_key)
      )
    ''');

    await InitDbData.insertCategorySettlementAnchors(db);
  }
}
