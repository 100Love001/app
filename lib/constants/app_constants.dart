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

  /// “今日任务”常驻轮播通知 ID（单一固定 ID，内容原地更新）。
  static const todayOverviewNotificationId = 2;

  /// 每日小结推送通知 ID（单一固定 ID，内容原地更新）。
  static const dailySummaryNotificationId = 3;

  /// 常驻通知轮播切换间隔。
  static const todayOverviewCarouselInterval = Duration(seconds: 12);
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
