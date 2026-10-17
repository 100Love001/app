import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:app/constants/app_constants.dart';
import 'package:app/utils/budget_period.dart';

class InitDbData {
  /// 默认支出分类：名称、结算周期、周期预算、结余兑换比例、超支扣除比例。
  /// 这些只是初始状态，用户可在账单体系中任意修改或删除。
  static const _expenseCategorySeeds = <(String, String, double, int, int)>[
    ('今日饭钱', BudgetPeriods.daily, 40, AppConstants.foodPointsPerYuan,
        AppConstants.foodOveragePointsPerYuan),
    ('今季度衣服费用', BudgetPeriods.quarterly, 0, 0, 0),
    ('今季度日用品费用', BudgetPeriods.quarterly, 0, 0, 0),
    ('路费', BudgetPeriods.quarterly, 0, 0, 0),
    ('其他', BudgetPeriods.quarterly, 0, 0, 0),
  ];

  static Future<void> insertFinanceCategorySeedData(DatabaseExecutor db) async {
    for (final (name, period, budget, balanceRate, overageRate)
        in _expenseCategorySeeds) {
      await db.insert('finance_categories', {
        'type': '支出',
        'name': name,
        'is_system': 1,
        'period_type': period,
        'budget': budget,
        'balance_rate': balanceRate,
        'overage_rate': overageRate,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final name in const ['工资', '奖金', '其他收入']) {
      await db.insert('finance_categories', {
        'type': '收入',
        'name': name,
        'is_system': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// 为每个可结算支出分类写入「上一个已结束周期」的 0 值结算锚点，
  /// 使结算循环不会追溯补发安装/升级之前周期的积分。
  static Future<void> insertCategorySettlementAnchors(
    DatabaseExecutor db, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final rows = await db.query(
      'finance_categories',
      columns: ['name', 'period_type'],
      where: "type = '支出' AND period_type != 'none'",
    );
    for (final row in rows) {
      final periodType = row['period_type'] as String;
      if (!BudgetPeriods.isSettled(periodType)) continue;
      final currentStart = BudgetPeriods.startOf(periodType, current);
      final previousStart = BudgetPeriods.startOf(
        periodType,
        currentStart.subtract(const Duration(days: 1)),
      );
      await db.insert('category_settlements', {
        'category_name': row['name'],
        'period_type': periodType,
        'period_key': BudgetPeriods.keyOf(previousStart),
        'spent': 0.0,
        'budget': 0.0,
        'points': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> insertQuoteSeedData(DatabaseExecutor db) async {
    const quotes = [
      ('慢慢来，所有值得等待的事情，都有它发生的时间。', '生活手账'),
      ('专注当下，慢慢成为想成为的人。', '生活手账'),
      ('每一个微小的行动，都会带你靠近想要的生活。', '生活手账'),
      ('允许自己慢一点，但不要停下脚步。', '生活手账'),
      ('今天的努力，是明天从容的底气。', '生活手账'),
      ('把注意力放回当下，答案会在行动中出现。', '生活手账'),
    ];
    for (final quote in quotes) {
      final existing = await db.query(
        'quotes',
        columns: ['quote_id'],
        where: 'content = ?',
        whereArgs: [quote.$1],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await db.insert('quotes', {
        'content': quote.$1,
        'author': quote.$2,
        'like_count': 0,
        'create_time': DateTime.now().toIso8601String(),
      });
    }
  }

  static Future<void> insertCollectionSeedData(DatabaseExecutor db) async {
    final wishTag = await db.insert('wish_tags', {
      'name': '生活',
      'remark': '生活愿望',
    });
    final hopeTag = await db.insert('hope_tags', {
      'name': '成长',
      'remark': '成长目标',
    });
    await db.insert('wishes', {
      'name': '一台新相机',
      'content': '记录旅行和生活中的美好瞬间。',
      'note': '先完成积分积累',
      'tag_id': wishTag,
      'required_points': 500,
      'current_points': 120,
      'status': '进行中',
      'desire': 3,
    });
    await db.insert('hopes', {
      'name': '完成年度阅读计划',
      'content': '全年阅读 24 本书并留下笔记。',
      'notes': '每月完成两本',
      'tag_id': hopeTag,
      'reward_points': 300,
      'status': '进行中',
      'desire': 4,
    });
  }

  static Future<void> insertTaskSeedData(DatabaseExecutor db) async {
    final specialWorkTag = await db.insert('special_task_tags', {
      'name': '工作',
      'remark': '需要在指定时间完成的工作事项',
    });
    final specialLifeTag = await db.insert('special_task_tags', {
      'name': '生活',
      'remark': '生活中的重要事项',
    });
    final dailyStudyTag = await db.insert('daily_task_tags', {
      'name': '学习',
      'remark': '需要按记忆曲线复习的内容',
    });
    final dailyHealthTag = await db.insert('daily_task_tags', {
      'name': '健康',
      'remark': '持续保持的健康习惯',
    });
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String time(DateTime value) => value.toIso8601String();

    await db.insert('special_tasks', {
      'name': '完成项目方案初稿',
      'content': '整理需求并完成方案初稿，提交给团队评审。',
      'remark': '今天优先完成核心章节',
      'start_time': time(today),
      'end_time': time(today.add(const Duration(hours: 18))),
      'task_tag_id': specialWorkTag,
      'status_tag': '进行中',
      'reward_points': 50,
    });
    await db.insert('special_tasks', {
      'name': '预约年度体检',
      'content': '确认体检机构和可预约时间。',
      'remark': '记得带身份证',
      'start_time': time(today.add(const Duration(days: 1))),
      'end_time': time(today.add(const Duration(days: 2))),
      'task_tag_id': specialLifeTag,
      'status_tag': '未开始',
    });
    await db.insert('special_tasks', {
      'name': '整理上周会议记录',
      'content': '归档会议记录并同步行动项。',
      'remark': '已完成归档',
      'start_time': time(today.subtract(const Duration(days: 2))),
      'end_time': time(today.subtract(const Duration(days: 1))),
      // completed_at 必须有值，否则首页日回顾按 substr(completed_at,1,10)
      // 永远查不到这条“已完成”任务。
      'completed_at': time(today.subtract(const Duration(days: 1))),
      'task_tag_id': specialWorkTag,
      'status_tag': '已完成',
    });
    await db.insert('daily_tasks', {
      'name': '复习 Flutter 状态管理',
      'content': '复习 Provider 与 ListenableBuilder 的使用场景。',
      'remark': '艾宾浩斯第 2 次复习',
      'start_time': time(today.subtract(const Duration(days: 1))),
      'task_tag_id': dailyStudyTag,
      'status_tag': '进行中',
      'next_review_time': time(today),
      'review_stage': 2,
      'daily_points': 5,
    });
    await db.insert('daily_tasks', {
      'name': '晚间拉伸 10 分钟',
      'content': '睡前进行肩颈和腿部拉伸。',
      'remark': '保持每日习惯',
      'start_time': time(today),
      'task_tag_id': dailyHealthTag,
      'status_tag': '进行中',
      'next_review_time': time(today),
      'review_stage': 1,
      'daily_points': 5,
    });
    await db.insert('daily_tasks', {
      'name': '阅读 20 分钟',
      'content': '阅读当前书籍并记录一个收获。',
      'remark': '今日已完成',
      'start_time': time(today.subtract(const Duration(days: 3))),
      'task_tag_id': dailyStudyTag,
      'status_tag': '进行中',
      'next_review_time': time(today),
      'review_stage': 3,
    });
  }

  static Future<void> insertSeedData(Database db) async {
    // 默认文件夹
    await db.insert('folders', {
      'folder_id': 1,
      'parent_id': null,
      'folder_name': '个人世界观',
      'sort': 0,
    });
    await db.insert('folders', {
      'folder_id': 2,
      'parent_id': 1,
      'folder_name': '生活感悟',
      'sort': 0,
    });
    await db.insert('folders', {
      'folder_id': 3,
      'parent_id': 1,
      'folder_name': '学习思考',
      'sort': 1,
    });
    // C2：独立“日记本”的默认根文件夹（与认知本数据隔离）。
    await db.insert('folders', {
      'folder_id': 4,
      'parent_id': null,
      'folder_name': '日常日记',
      'book_type': 'diary',
      'sort': 0,
    });

    // 默认日记
    await db.insert('diaries', {
      'diary_id': 1,
      'folder_id': 2,
      'title': '2026.09.24 今日情绪日记',
      'content': '今天状态很好，完成了重点任务，希望明天继续保持。',
    });
    await db.insert('diaries', {
      'diary_id': 2,
      'folder_id': 3,
      'title': '读书笔记',
      'content': '学习计划推进顺利，今天复盘了行动节奏。',
    });

    // 默认标签
    await db.insert('tags', {'tag_name': '工作', 'tag_group': 'global'});
    await db.insert('tags', {'tag_name': '学习', 'tag_group': 'global'});
    await db.insert('tags', {'tag_name': '生活', 'tag_group': 'global'});
    await db.insert('tags', {'tag_name': '健康', 'tag_group': 'global'});

    // 默认积分
    await db.insert('points', {
      'source_type': 'initial',
      'source_id': 1,
      'point_value': 1280,
      'operation_type': '奖励',
      'remark': '初始积分',
    });
    await insertMoodSeedData(db);
  }

  static Future<void> insertMoodSeedData(DatabaseExecutor db) async {
    final tags = [
      ['开心', '今天很愉悦'],
      ['平静', '没有大喜大悲'],
      ['疲惫', '身体或精神很累'],
      ['难过', '情绪低落'],
      ['焦虑', '烦躁、担心'],
    ];
    for (final tag in tags) {
      await db.insert('mood_tag', {'name': tag[0], 'remark': tag[1]});
    }
  }
}
