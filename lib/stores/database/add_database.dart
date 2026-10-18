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
      version: 20,
      password: password,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // WAL 模式：读写互不阻塞，崩溃后恢复快，
        // 避免残留事务回滚导致启动时长时间等锁。
        // 该 PRAGMA 会返回结果行，必须用 rawQuery（execute 底层是
        // SQLiteStatement，不允许返回值，会抛 DatabaseException code 0）。
        await db.rawQuery('PRAGMA journal_mode = WAL');
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
    // 结算锚点：新装用户不追溯补发安装日之前周期的分类预算积分。
    await InitDbData.insertCategorySettlementAnchors(db);
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
        'task_weight_records',
        'task_mood_records',
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
        'category_settlements',
        'anniversaries',
        'time_capsules',
        'quotes',
      ]) {
        await transaction.delete(table);
      }
      // 与备份恢复流程保持一致：重置自增序列，清空后 id 从 1 重新开始。
      await transaction.delete('sqlite_sequence');
      // 重新写入结算锚点：清空后不追溯补发此前周期的分类预算积分。
      await InitDbData.insertCategorySettlementAnchors(transaction);
      await InitDbData.insertQuoteSeedData(transaction);
    });
  }
}
