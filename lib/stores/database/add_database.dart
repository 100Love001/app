import 'package:app/stores/database/data/init_data.dart';
import 'package:app/stores/database/data/sql.dart';
import 'package:app/stores/database/encryption_key_manager.dart';
import 'package:app/stores/database/migrations/migration_runner.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  // 私有构造函数，单例
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Future<Database>? _databaseFuture;

  /// 获取数据库实例
  Future<Database> get database async {
    try {
      return await (_databaseFuture ??= _initDatabase());
    } catch (_) {
      _databaseFuture = null;
      rethrow;
    }
  }

  /// 初始化数据库，打开db
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'myapp.db');
    final password = await EncryptionKeyManager.instance.getOrCreateKey();
    return openDatabase(
      path,
      version: 18,
      password: password,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // 开启外键约束
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await runMigrations(db, oldVersion, newVersion);
  }

  /// 首次创建数据库：执行所有建表语句 + 插入初始种子数据
  Future<void> _onCreate(Database db, int version) async {
    // 循环执行所有建表SQL
    for (final sql in TableSql.allTableSql) {
      await db.execute(sql);
    }
    // 插入默认初始数据
    await InitDbData.insertSeedData(db);
    await InitDbData.insertTaskSeedData(db);
    await InitDbData.insertCollectionSeedData(db);
    await InitDbData.insertQuoteSeedData(db);
    await InitDbData.insertFinanceCategorySeedData(db);
    final foodBudget = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['daily_food_budget'],
      limit: 1,
    );
    final now = DateTime.now();
    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (foodBudget.isNotEmpty) {
      await db.insert('budget_history', {
        'budget_date': dateKey,
        'budget_amount':
            double.tryParse(foodBudget.first['value'] as String) ?? 0,
      });
    }
    // 以“昨天”的 0 元兑换记录作为饭钱结算锚点：新装用户不追溯补发
    // 安装日之前任何日期的饭钱结余积分（与 clearPersonalData 保持一致）。
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    await db.insert('food_point_exchanges', {
      'exchange_date':
          '${yesterday.year.toString().padLeft(4, '0')}-'
          '${yesterday.month.toString().padLeft(2, '0')}-'
          '${yesterday.day.toString().padLeft(2, '0')}',
      'amount': 0,
      'points': 0,
    });
  }

  // ======================【底层通用原始CRUD方法，不带业务逻辑】======================
  /// 通用新增
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  /// 通用更新
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  /// 通用删除
  Future<int> delete(
    String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  /// 通用查询（原始sql）
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  /// 执行原生SQL（例如批量操作）
  Future<void> rawExecute(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    await db.execute(sql, arguments);
  }

  /// 关闭数据库连接
  Future<void> close() async {
    final databaseFuture = _databaseFuture;
    if (databaseFuture == null) return;

    final db = await databaseFuture;
    await db.close();
    if (identical(_databaseFuture, databaseFuture)) {
      _databaseFuture = null;
    }
  }

  Future<void> clearPersonalData() async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final table in [
        'daily_task_reminders',
        'daily_task_reward_logs',
        'special_task_reminders',
        'task_reviews',
        'hope_steps',
        'hope_progress_logs',
        'wish_redemptions',
        'desire_logs',
        'problems',
        'diary_replies',
        'diary_attachments',
        'quote_replies',
        'diaries',
        'mood_record',
        'mood_month_stat',
        'mood_report_log',
        'daily_tasks',
        'special_tasks',
        'tasks',
        'wishes',
        'hopes',
        'points',
        'income_expenses',
        'food_point_exchanges',
        'anniversaries',
        'time_capsules',
        'quotes',
      ]) {
        await transaction.delete(table);
      }
      // 与备份恢复流程保持一致：重置自增序列，清空后 id 从 1 重新开始。
      await transaction.delete('sqlite_sequence');
      final now = DateTime.now();
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      final exchangeDate =
          '${yesterday.year.toString().padLeft(4, '0')}-'
          '${yesterday.month.toString().padLeft(2, '0')}-'
          '${yesterday.day.toString().padLeft(2, '0')}';
      await transaction.insert('food_point_exchanges', {
        'exchange_date': exchangeDate,
        'amount': 0,
        'points': 0,
      });
      await InitDbData.insertQuoteSeedData(transaction);
    });
  }
}
