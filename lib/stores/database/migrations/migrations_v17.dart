import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v17：体验优化批次
/// - 任务/愿望/希望新增非必填“要求”字段（requirement）
/// - 特殊任务自定义提前提醒（special_task_reminders，多提醒点）
/// - 日常任务新增习惯型模式（task_mode/repeat_type/repeat_value）
///   与多个自定义提醒时间点（daily_task_reminders）
/// - 支出支持积分抵扣（income_expenses.points_deducted）
/// - 文件夹/日记新增本子类型（book_type：认知本/日记本），
///   日记支持富文本内容标记（content_format）
/// - 希望支持分步任务（hope_steps）
/// - 新增问题清单（problems）
class MigrationV17 extends Migration {
  @override
  int get targetVersion => 17;

  @override
  Future<void> up(Database db) async {
    // ---- 新列 ----
    await db.execute('ALTER TABLE special_tasks ADD COLUMN requirement TEXT');
    await db.execute('ALTER TABLE daily_tasks ADD COLUMN requirement TEXT');
    await db.execute(
      "ALTER TABLE daily_tasks ADD COLUMN task_mode TEXT NOT NULL DEFAULT 'review'",
    );
    await db.execute(
      "ALTER TABLE daily_tasks ADD COLUMN repeat_type TEXT NOT NULL DEFAULT 'daily'",
    );
    await db.execute('ALTER TABLE daily_tasks ADD COLUMN repeat_value TEXT');
    await db.execute('ALTER TABLE wishes ADD COLUMN requirement TEXT');
    await db.execute('ALTER TABLE hopes ADD COLUMN requirement TEXT');
    await db.execute(
      "ALTER TABLE hopes ADD COLUMN hope_mode TEXT NOT NULL DEFAULT 'simple'",
    );
    await db.execute(
      'ALTER TABLE income_expenses ADD COLUMN points_deducted INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      "ALTER TABLE folders ADD COLUMN book_type TEXT NOT NULL DEFAULT 'cognition'",
    );
    await db.execute(
      "ALTER TABLE diaries ADD COLUMN book_type TEXT NOT NULL DEFAULT 'cognition'",
    );
    await db.execute(
      "ALTER TABLE diaries ADD COLUMN content_format TEXT NOT NULL DEFAULT 'plaintext'",
    );

    // ---- 新表 ----
    await db.execute('''
      CREATE TABLE special_task_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        remind_minutes_before INTEGER NOT NULL DEFAULT 15,
        UNIQUE(task_id, remind_minutes_before),
        FOREIGN KEY (task_id) REFERENCES special_tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_task_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL DEFAULT 0,
        UNIQUE(task_id, hour, minute),
        FOREIGN KEY (task_id) REFERENCES daily_tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE hope_steps (
        step_id INTEGER PRIMARY KEY AUTOINCREMENT,
        hope_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        content TEXT,
        requirement TEXT,
        reward_points INTEGER NOT NULL DEFAULT 0,
        sort INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT '未进行',
        completed_at TEXT,
        create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
        update_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
        FOREIGN KEY (hope_id) REFERENCES hopes(hope_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE problems (
        problem_id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT '待解决',
        solution_note TEXT,
        resolved_at TEXT,
        sort INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
        update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
      )
    ''');

    // ---- 历史数据兼容 ----
    // 已有特殊任务沿用固定提前 15 分钟提醒；已完成/已删除任务不排提醒，
    // 但仍补一条配置，保证编辑页能看到默认值。
    await db.execute('''
      INSERT OR IGNORE INTO special_task_reminders (task_id, remind_minutes_before)
      SELECT id, 15 FROM special_tasks
    ''');
    // 旧库的文件夹/日记全部默认归入“认知本”；为新“日记本”补一个根文件夹，
    // 保证升级后日记本不是空的入口且新建日记有文件夹可选。
    final diaryBookFolders = await db.query(
      'folders',
      where: "book_type = 'diary'",
      limit: 1,
    );
    if (diaryBookFolders.isEmpty) {
      await db.insert('folders', {
        'folder_name': '日常日记',
        'book_type': 'diary',
        'sort': 0,
      });
    }
  }
}
