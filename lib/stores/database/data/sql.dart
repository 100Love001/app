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
  // book_type：本子类型。cognition=认知本（旧“日记本”迁移归入），diary=日记本。
  static const String createFolders = '''
    CREATE TABLE folders (
      folder_id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER NULL,
      folder_name TEXT NOT NULL,
      book_type TEXT NOT NULL DEFAULT 'cognition',
      sort INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime')),
      FOREIGN KEY (parent_id) REFERENCES folders(folder_id) ON DELETE CASCADE
    )
  ''';

  // diaries 日记主表
  // book_type 与文件夹保持一致，用于跨文件夹检索时隔离认知本/日记本；
  // content_format：plaintext=纯文本（历史数据），delta=flutter_quill 富文本 JSON。
  static const String createDiaries = '''
    CREATE TABLE diaries (
      diary_id INTEGER PRIMARY KEY AUTOINCREMENT,
      folder_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT,
      book_type TEXT NOT NULL DEFAULT 'cognition',
      content_format TEXT NOT NULL DEFAULT 'plaintext',
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
  // requirement：非必填的完成要求/验收标准。
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
      requirement TEXT,
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
  // hope_mode：simple=单条+手动进度（历史行为），steps=文件夹+分步任务。
  static const String createHopes = '''
    CREATE TABLE hopes (
      hope_id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      reward_points INTEGER NOT NULL DEFAULT 0,
      progress INTEGER NOT NULL DEFAULT 0,
      difficulty TEXT NOT NULL DEFAULT '中等',
      tag TEXT,
      content TEXT,
      requirement TEXT,
      hope_mode TEXT NOT NULL DEFAULT 'simple',
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

  // hope_steps 希望分步任务（hope_mode='steps' 时使用）
  static const String createHopeSteps = '''
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
  ''';

  // problems 问题清单
  static const String createProblems = '''
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

  // tasks长期任务表（任务类型 long）
  // reward_points/penalty_points：完成奖励与逾期扣分；
  // enable_penalty：逾期扣分开关；component_json：动态组件配置与数据。
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
      reward_points INTEGER NOT NULL DEFAULT 0,
      penalty_points INTEGER NOT NULL DEFAULT 0,
      enable_penalty INTEGER NOT NULL DEFAULT 1,
      component_json TEXT,
      completed_at TEXT,
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
      requirement TEXT,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      task_tag_id INTEGER,
      status_tag TEXT NOT NULL DEFAULT '未开始',
      reward_points INTEGER NOT NULL DEFAULT 0,
      penalty_points INTEGER NOT NULL DEFAULT 0,
      enable_penalty INTEGER NOT NULL DEFAULT 1,
      component_json TEXT,
      completed_at TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (task_tag_id) REFERENCES special_task_tags(id)
    )
  ''';

  // 特殊任务提醒时间表：一条任务可配置多个提前量（分钟，允许负数=准时/延后）。
  static const String createSpecialTaskReminders = '''
    CREATE TABLE special_task_reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      remind_minutes_before INTEGER NOT NULL DEFAULT 15,
      UNIQUE(task_id, remind_minutes_before),
      FOREIGN KEY (task_id) REFERENCES special_tasks(id) ON DELETE CASCADE
    )
  ''';

  // task_mode：review=记忆复习型（艾宾浩斯），habit=自定义习惯型。
  // habit 型使用 repeat_type/repeat_value：
  //   daily（每天）、weekly（repeat_value='1,3,5' 周几）、
  //   monthly（repeat_value='15' 每月几号）、interval（repeat_value='3' 间隔天数）。
  static const String createDailyTasks = '''
    CREATE TABLE daily_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      content TEXT,
      remark TEXT,
      requirement TEXT,
      start_time TEXT NOT NULL,
      task_tag_id INTEGER,
      status_tag TEXT NOT NULL DEFAULT '未开始',
      task_mode TEXT NOT NULL DEFAULT 'review',
      repeat_type TEXT NOT NULL DEFAULT 'daily',
      repeat_value TEXT,
      next_review_time TEXT,
      review_stage INTEGER NOT NULL DEFAULT 0,
      daily_points INTEGER NOT NULL DEFAULT 0,
      penalty_points INTEGER NOT NULL DEFAULT 0,
      enable_penalty INTEGER NOT NULL DEFAULT 1,
      component_json TEXT,
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

  // 日常任务自定义提醒时间点（小时/分钟），仅 habit 型使用；
  // review 型沿用全局 9:00/12:00 复习提醒。
  static const String createDailyTaskReminders = '''
    CREATE TABLE daily_task_reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      hour INTEGER NOT NULL,
      minute INTEGER NOT NULL DEFAULT 0,
      UNIQUE(task_id, hour, minute),
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
  // points_deducted：本笔支出同时从积分中抵扣的数量（0 表示不抵扣）。
  static const String createIncomeExpenses = '''
    CREATE TABLE income_expenses (
      record_id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      category TEXT NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      remark TEXT,
      points_deducted INTEGER NOT NULL DEFAULT 0,
      record_date TEXT NOT NULL,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // period_type：支出分类的预算结算周期。
  //   none=不结算（收入分类），daily=每天，weekly=每周（周一起），
  //   monthly=每月，quarterly=每季度。
  // budget：周期预算金额；balance_rate：结余每元兑换积分；
  // overage_rate：超支每元扣除积分。
  static const String createFinanceCategories = '''
    CREATE TABLE IF NOT EXISTS finance_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      is_system INTEGER NOT NULL DEFAULT 0,
      period_type TEXT NOT NULL DEFAULT 'none',
      budget REAL NOT NULL DEFAULT 0,
      balance_rate INTEGER NOT NULL DEFAULT 0,
      overage_rate INTEGER NOT NULL DEFAULT 0,
      UNIQUE(type, name)
    )
  ''';

  // 支出分类周期结算记录：一个分类一个周期最多一条。
  // period_key 统一存周期起始日（yyyy-MM-dd），与 period_type 共同唯一确定周期；
  // points 带符号：结余兑换为正，超支扣除为负。
  static const String createCategorySettlements = '''
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
  ''';

  static const String createBudgetHistory = '''
    CREATE TABLE IF NOT EXISTS budget_history (
      budget_date TEXT PRIMARY KEY,
      budget_amount REAL NOT NULL CHECK(budget_amount >= 0),
      update_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )
  ''';

  // points积分流水（create_time 统一 ISO8601，与 Dart 端 toIso8601String 一致）
  // biz_key：业务幂等键（如 penalty:daily:9:2026-10-17），同一业务动作
  // 无论扫描多少次只产生一条流水；NULL 不参与唯一约束（历史流水/普通奖励）。
  static const String createPoints = '''
    CREATE TABLE points (
      points_id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_type TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      point_value INTEGER NOT NULL DEFAULT 0,
      operation_type TEXT NOT NULL,
      biz_key TEXT,
      remark TEXT,
      create_time TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now','localtime'))
    )
  ''';

  static const String createPointsBizKeyIndex = '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_points_biz_key
    ON points(biz_key)
    WHERE biz_key IS NOT NULL
  ''';

  // 任务动态组件-体重记录：一个任务多条，支持体重曲线图。
  // task_kind：daily=日常/习惯，special=特殊短期，long=长期。
  static const String createTaskWeightRecords = '''
    CREATE TABLE task_weight_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_kind TEXT NOT NULL,
      task_id INTEGER NOT NULL,
      record_date TEXT NOT NULL,
      weight REAL NOT NULL,
      note TEXT,
      create_time TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now','localtime'))
    )
  ''';

  // 任务动态组件-心情记录：level 1-5，多条记录生成情绪趋势图。
  static const String createTaskMoodRecords = '''
    CREATE TABLE task_mood_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_kind TEXT NOT NULL,
      task_id INTEGER NOT NULL,
      record_date TEXT NOT NULL,
      level INTEGER NOT NULL,
      note TEXT,
      create_time TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now','localtime'))
    )
  ''';

  static const String createTaskRecordIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_task_weight_records_task_date
      ON task_weight_records(task_kind, task_id, record_date)
  ''';

  static const String createTaskMoodRecordIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_task_mood_records_task_date
      ON task_mood_records(task_kind, task_id, record_date)
  ''';

  static const String createTaskPenaltyIndex = '''
    CREATE INDEX IF NOT EXISTS idx_tasks_penalty_scan
      ON tasks(enable_penalty, status, deadline)
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

  /// 特殊语录（时光信箱）：写下话语并设定未来解锁日期，
  /// 到时间前内容保密，到时间后在首页与通知栏以“特殊礼物”形式展示。
  static const String createTimeCapsules = '''
    CREATE TABLE time_capsules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      content TEXT NOT NULL,
      unlock_date TEXT NOT NULL,
      opened INTEGER NOT NULL DEFAULT 0,
      create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
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
    createHopeSteps,
    createProblems,
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
    createSpecialTaskReminders,
    createDailyTasks,
    createDailyTaskRewardLogs,
    createDailyTaskReminders,
    createTaskReviews,
    createIncomeExpenses,
    createFinanceCategories,
    createCategorySettlements,
    createBudgetHistory,
    createPoints,
    createPointsBizKeyIndex,
    createTaskWeightRecords,
    createTaskMoodRecords,
    createTaskRecordIndexes,
    createTaskMoodRecordIndexes,
    createTaskPenaltyIndex,
    createTags,
    createAppSettings,
    createTimeCapsules,
    createQuotes,
    createQuoteReplies,
    ...moodTableSql,
  ];
}
