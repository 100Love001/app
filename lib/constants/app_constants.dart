import 'package:flutter/material.dart';

class AppConstants {
  const AppConstants._();

  static const reminderMorningHour = 9;
  static const reminderEveningHour = 21;

  /// 复习日 9 点提醒错过后（当天晚些时候才同步）的补提醒小时，
  /// 取固定正午时刻以保证重复同步也不会产生多条通知。
  static const reviewReminderCatchupHour = 12;
  static const specialTaskReminderMinutes = 15;

  static const foodPointsPerYuan = 5;
  static const foodOveragePointsPerYuan = 15;
  static const wishPointsPerYuan = 10;

  static const reviewIntervals = [1, 2, 4, 7, 15, 30];

  static const specialTaskNotificationIdOffset = 1000000;
  static const dailyTaskNotificationIdOffset = 2000000;

  /// B1：习惯型日常任务的多提醒通知使用独立 ID 段，
  /// 与复习型日常任务（2000000 段）错开。
  static const habitTaskNotificationIdOffset = 3000000;

  /// 纪念日提醒通知使用独立 ID 段。
  static const anniversaryNotificationIdOffset = 4000000;

  /// 特殊语录（时光信箱）解锁提醒通知使用独立 ID 段。
  static const timeCapsuleNotificationIdOffset = 5000000;

  /// 长期任务截止提醒通知使用独立 ID 段（每个任务一条）。
  static const longTaskNotificationIdOffset = 6000000;

  /// 即时业务通知（逾期扣分提示等）ID 段基准，循环取 0-99999。
  static const transientNotificationIdBase = 8000000;

  /// “今日任务”常驻轮播通知 ID（单一固定 ID，内容原地更新）。
  static const todayOverviewNotificationId = 2;

  /// 每日小结推送通知 ID（单一固定 ID，内容原地更新）。
  static const dailySummaryNotificationId = 3;

  /// 常驻通知轮播切换间隔。
  static const todayOverviewCarouselInterval = Duration(seconds: 12);
}

/// 任务大类：日常、长期、特殊短期、习惯参与逾期扣分；
/// 愿望（wish）只消耗积分，希望（hope）完成获得积分，均不触发逾期扣分。
enum TaskType {
  daily('daily', '日常任务'),
  longTerm('long', '长期任务'),
  shortTerm('special', '特殊短期任务'),
  habit('habit', '习惯任务'),
  wish('wish', '愿望清单'),
  hope('hope', '希望清单');

  const TaskType(this.id, this.label);

  /// 数据库 task_kind 取值 / 存储归属（daily 与 habit 共用 daily_tasks 表）。
  final String id;
  final String label;

  /// 实际落表归属：habit → daily_tasks，shortTerm → special_tasks，
  /// longTerm → tasks，其余保持自身 id。
  String get storageKind => switch (this) {
    TaskType.habit => 'daily',
    TaskType.shortTerm => 'special',
    _ => id,
  };

  bool get supportsOverduePenalty =>
      this == TaskType.daily ||
      this == TaskType.longTerm ||
      this == TaskType.shortTerm ||
      this == TaskType.habit;

  static TaskType? fromId(String? id) {
    if (id == null) return null;
    for (final value in TaskType.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// 动态表单组件类型。除任务标题（必填）与任务类型选择器固定外，
/// 其余字段全部以组件形式自由添加 / 删除 / 排序，序列化为 JSON 存储。
enum ComponentType {
  // 时间类
  timeRange('time_range', '起止时间', Icons.date_range_outlined),
  deadline('deadline', '截止日期', Icons.event_available_outlined),
  repeatRule('repeat_rule', '重复规则', Icons.repeat_rounded),
  reminders('reminders', '提醒时间', Icons.alarm_add_outlined),
  // 分类
  tag('tag', '任务标签', Icons.label_outline),
  // 文本类
  content('content', '任务内容', Icons.notes_outlined),
  requirement('requirement', '完成要求', Icons.fact_check_outlined),
  remark('remark', '文字备注', Icons.sticky_note_2_outlined),
  // 积分类
  rewardPoints('reward_points', '完成奖励积分', Icons.stars_outlined),
  penaltyPoints('penalty_points', '逾期惩罚积分', Icons.warning_amber_outlined),
  // 数据记录类（多条历史，支撑曲线图）
  weight('weight', '体重记录', Icons.monitor_weight_outlined),
  mood('mood', '心情记录', Icons.mood_outlined),
  dataChart('data_chart', '数据分析', Icons.insights_outlined),
  // 进度类
  progress('progress', '进度百分比', Icons.percent),
  subtasks('subtasks', '子任务列表', Icons.checklist_rtl_outlined),
  checkinCounter('checkin_counter', '打卡次数', Icons.pin_outlined),
  // 多媒体类
  images('images', '图片附件', Icons.image_outlined),
  voice('voice', '语音记录', Icons.mic_none_rounded);

  const ComponentType(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static ComponentType? fromId(String? id) {
    if (id == null) return null;
    for (final value in ComponentType.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

enum MoodLevel {
  veryLow(1, '很差', Icons.sentiment_very_dissatisfied_outlined),
  low(2, '较差', Icons.sentiment_dissatisfied_outlined),
  neutral(3, '一般', Icons.sentiment_neutral_outlined),
  good(4, '不错', Icons.sentiment_satisfied_outlined),
  veryGood(5, '很好', Icons.sentiment_very_satisfied_outlined);

  const MoodLevel(this.score, this.label, this.icon);

  final int score;
  final String label;
  final IconData icon;

  /// 越界 / 空值统一退化为「一般」，保证 UI 始终有可显示的等级。
  static MoodLevel fromScore(int? score) {
    if (score == null) return MoodLevel.neutral;
    for (final level in MoodLevel.values) {
      if (level.score == score) return level;
    }
    return MoodLevel.neutral;
  }
}

/// 愿望（wishes.status）状态字面值，统一收敛于此，禁止散落裸字符串。
abstract final class WishStatus {
  const WishStatus._();

  static const notStarted = '未开始';
  static const inProgress = '进行中';
  static const readyToRedeem = '待兑换';
  static const redeemed = '已兑换';
  static const completed = '已完成';

  /// 旧版历史值，已在 v12 迁移中归一，仅迁移逻辑需要引用。
  static const legacyPendingPoints = '待攒积分';

  /// 终态：不允许再被编辑/状态推导覆盖。
  static const terminal = <String>{redeemed, completed};

  static bool isTerminal(String? status) =>
      status == redeemed || status == completed;
}
