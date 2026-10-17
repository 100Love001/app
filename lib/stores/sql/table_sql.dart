// lib/stores/sql/table_sql.dart
class TableSql {
  static const String createAnniversaries = '''
    CREATE TABLE anniversaries (
      anniversary_id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      event_date TEXT NOT NULL,
      note TEXT,
      tag TEXT NOT NULL DEFAULT '',
      repeat_annually INTEGER NOT NULL DEFAULT 1,
      calendar_type INTEGER NOT NULL DEFAULT 0,
      repeat_type INTEGER NOT NULL DEFAULT 1,
      repeat_custom_days INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // folders 多层文件夹表
  static const String createFolders = '''
    CREATE TABLE folders (
      folder_id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER NULL,
      folder_name TEXT NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (parent_id) REFERENCES folders(folder_id) ON DELETE CASCADE
    )
  ''';

  // diaries 日记主表
  static const String createDiaries = '''
    CREATE TABLE diaries (
      diary_id INTEGER PRIMARY KEY AUTOINCREMENT,
      folder_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (folder_id) REFERENCES folders(folder_id) ON DELETE CASCADE
    )
  ''';

  // diary_replies 日记回复表
  static const String createDiaryReplies = '''
    CREATE TABLE diary_replies (
      reply_id INTEGER PRIMARY KEY AUTOINCREMENT,
      diary_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (diary_id) REFERENCES diaries(diary_id) ON DELETE CASCADE
    )
  ''';

  // diary_attachments 附件表
  static const String createDiaryAttachments = '''
    CREATE TABLE diary_attachments (
      attachment_id INTEGER PRIMARY KEY AUTOINCREMENT,
      diary_id INTEGER NOT NULL,
      file_type TEXT NOT NULL,
      file_name TEXT NOT NULL,
      file_path TEXT NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (diary_id) REFERENCES diaries(diary_id) ON DELETE CASCADE
    )
  ''';

  // wishes愿望清单
  static const String createWishes = '''
    CREATE TABLE wishes (
      wish_id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      required_points INTEGER NOT NULL DEFAULT 0,
      current_points INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT '未开始',
      tag TEXT,
      note TEXT,
      content TEXT,
      tag_id INTEGER,
      desire INTEGER NOT NULL DEFAULT 0,
      target_date TEXT,
      image_path TEXT,
      wish_type TEXT NOT NULL DEFAULT '实物',
      sort INTEGER NOT NULL DEFAULT 0,
      redeemed_at TEXT,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // hopes希望清单
  static const String createHopes = '''
    CREATE TABLE hopes (
      hope_id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      reward_points INTEGER NOT NULL DEFAULT 0,
      progress INTEGER NOT NULL DEFAULT 0,
      difficulty TEXT NOT NULL DEFAULT '中等',
      tag TEXT,
      content TEXT,
      tag_id INTEGER,
      desire INTEGER NOT NULL DEFAULT 0,
      deadline TEXT,
      status TEXT NOT NULL DEFAULT '未进行',
      redeemed_at TEXT,
      repeat_type TEXT DEFAULT 'none',
      notes TEXT,
      sort INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  static const String createWishTags = '''
    CREATE TABLE wish_tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      remark TEXT
    )
  ''';

  static const String createHopeTags = '''
    CREATE TABLE hope_tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      remark TEXT
    )
  ''';

  static const String createDesireLogs = '''
    CREATE TABLE desire_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_type TEXT NOT NULL,
      item_id INTEGER NOT NULL,
      desire_date TEXT NOT NULL,
      amount INTEGER NOT NULL DEFAULT 1,
      UNIQUE(item_type, item_id, desire_date)
    )
  ''';

  static const String createHopeProgressLogs = '''
    CREATE TABLE hope_progress_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hope_id INTEGER NOT NULL,
      progress_date TEXT NOT NULL,
      amount INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (hope_id) REFERENCES hopes(hope_id) ON DELETE CASCADE
    )
  ''';

  static const String createWishRedemptions = '''
    CREATE TABLE wish_redemptions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      wish_id INTEGER NOT NULL,
      points_spent INTEGER NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (wish_id) REFERENCES wishes(wish_id) ON DELETE CASCADE
    )
  ''';

  static const String createFoodPointExchanges = '''
    CREATE TABLE food_point_exchanges (
      exchange_date TEXT PRIMARY KEY,
      amount REAL NOT NULL,
      points INTEGER NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // tasks任务表
  static const String createTasks = '''
    CREATE TABLE tasks (
      task_id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_type TEXT NOT NULL,
      title TEXT NOT NULL,
      tag TEXT,
      priority TEXT NOT NULL DEFAULT '中',
      deadline TEXT,
      status TEXT NOT NULL DEFAULT '未开始',
      note TEXT,
      difficulty INTEGER NOT NULL DEFAULT 1,
      parent_task_id INTEGER NULL,
      is_repeatable INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (parent_task_id) REFERENCES tasks(task_id) ON DELETE CASCADE
    )
  ''';

  static const String createSpecialTaskTags = '''
    CREATE TABLE special_task_tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      remark TEXT
    )
  ''';

  static const String createDailyTaskTags = '''
    CREATE TABLE daily_task_tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      remark TEXT
    )
  ''';

  static const String createSpecialTasks = '''
    CREATE TABLE special_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      content TEXT,
      remark TEXT,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      task_tag_id INTEGER,
      status_tag TEXT NOT NULL DEFAULT '未开始',
      reward_points INTEGER NOT NULL DEFAULT 0,
      penalty_points INTEGER NOT NULL DEFAULT 0,
      completed_at TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (task_tag_id) REFERENCES special_task_tags(id)
    )
  ''';

  static const String createDailyTasks = '''
    CREATE TABLE daily_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      content TEXT,
      remark TEXT,
      start_time TEXT NOT NULL,
      task_tag_id INTEGER,
      status_tag TEXT NOT NULL DEFAULT '未开始',
      next_review_time TEXT,
      review_stage INTEGER NOT NULL DEFAULT 0,
      daily_points INTEGER NOT NULL DEFAULT 0,
      penalty_points INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (task_tag_id) REFERENCES daily_task_tags(id)
    )
  ''';

  static const String createDailyTaskRewardLogs = '''
    CREATE TABLE daily_task_reward_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      reward_date TEXT NOT NULL,
      UNIQUE(task_id, reward_date),
      FOREIGN KEY (task_id) REFERENCES daily_tasks(id) ON DELETE CASCADE
    )
  ''';

  // task_reviews任务复习记录
  static const String createTaskReviews = '''
    CREATE TABLE task_reviews (
      review_id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      review_time TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT '待复习',
      notes TEXT,
      FOREIGN KEY (task_id) REFERENCES tasks(task_id) ON DELETE CASCADE
    )
  ''';

  // income_expenses收支记录
  static const String createIncomeExpenses = '''
    CREATE TABLE income_expenses (
      record_id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      category TEXT NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      remark TEXT,
      record_date TEXT NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  static const String createFinanceCategories = '''
    CREATE TABLE IF NOT EXISTS finance_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      is_system INTEGER NOT NULL DEFAULT 0,
      UNIQUE(type, name)
    )
  ''';

  static const String createBudgetHistory = '''
    CREATE TABLE IF NOT EXISTS budget_history (
      budget_date TEXT PRIMARY KEY,
      budget_amount REAL NOT NULL CHECK(budget_amount >= 0),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // points积分流水（create_time 统一 ISO8601，与 Dart 端 toIso8601String 一致）
  static const String createPoints = '''
    CREATE TABLE points (
      points_id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_type TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      point_value INTEGER NOT NULL DEFAULT 0,
      operation_type TEXT NOT NULL,
      remark TEXT,
      create_time TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now','localtime'))
    )
  ''';

  // tags全局标签
  static const String createTags = '''
    CREATE TABLE tags (
      tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
      tag_name TEXT NOT NULL UNIQUE,
      tag_group TEXT NOT NULL DEFAULT 'global',
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // app_settings全局配置
  static const String createAppSettings = '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''';

  static const String createQuotes = '''
    CREATE TABLE IF NOT EXISTS quotes (
      quote_id INTEGER PRIMARY KEY AUTOINCREMENT,
      content TEXT NOT NULL UNIQUE,
      author TEXT,
      like_count INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  static const String createQuoteReplies = '''
    CREATE TABLE IF NOT EXISTS quote_replies (
      reply_id INTEGER PRIMARY KEY AUTOINCREMENT,
      quote_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (quote_id) REFERENCES quotes(quote_id) ON DELETE CASCADE
    )
  ''';
  //心情标签表
  static const String createMoodTags = '''
    CREATE TABLE mood_tag (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      remark TEXT
    )
  ''';

  static const String createMoodRecords = '''
    CREATE TABLE mood_record (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tag_id INTEGER NOT NULL,
      reason TEXT,
      record_date TEXT NOT NULL UNIQUE,
      create_timestamp INTEGER NOT NULL,
      FOREIGN KEY (tag_id) REFERENCES mood_tag(id)
    )
  ''';

  static const String createMoodMonthStats = '''
    CREATE TABLE mood_month_stat (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      tag_id INTEGER NOT NULL,
      count INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE (year, month, tag_id),
      FOREIGN KEY (tag_id) REFERENCES mood_tag(id)
    )
  ''';

  static const String createMoodReportLogs = '''
    CREATE TABLE mood_report_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      report_type TEXT NOT NULL,
      generated_at INTEGER NOT NULL,
      UNIQUE (year, month, report_type)
    )
  ''';

  static const moodTableSql = [
    createMoodTags,
    createMoodRecords,
    createMoodMonthStats,
    createMoodReportLogs,
  ];

  // Tables are ordered so referenced tables exist before foreign keys use them.
  static const List<String> allTableSql = [
    createAnniversaries,
    createFolders,
    createDiaries,
    createDiaryReplies,
    createDiaryAttachments,
    createWishes,
    createHopes,
    createWishTags,
    createHopeTags,
    createDesireLogs,
    createHopeProgressLogs,
    createWishRedemptions,
    createFoodPointExchanges,
    createTasks,
    createSpecialTaskTags,
    createDailyTaskTags,
    createSpecialTasks,
    createDailyTasks,
    createDailyTaskRewardLogs,
    createTaskReviews,
    createIncomeExpenses,
    createFinanceCategories,
    createBudgetHistory,
    createPoints,
    createTags,
    createAppSettings,
    createQuotes,
    createQuoteReplies,
    ...moodTableSql,
  ];
}
