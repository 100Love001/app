import 'dart:async';

import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/home/home_repository.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/date_range.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

/// 通知按钮（showsUserInterface=false 的 action）后台响应入口。
/// 插件会在独立的后台 isolate 中回调该函数，必须用 vm:entry-point 标注
/// 防止被 AOT 编译裁剪；新版引擎会自动注册全部插件，数据库可直接使用。
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.actionId != LocalNotificationService.claimActionId) return;
  unawaited(
    LocalNotificationService.instance.handleClaimActionInBackground(
      response.payload,
    ),
  );
}

class LocalNotificationService {
  LocalNotificationService._();

  static final instance = LocalNotificationService._();

  static const _financeReminderId = 1;

  /// 单个特殊任务最多占用的通知 ID 槽位数。
  static const _specialReminderSlots = 32;

  /// 单个习惯型日常任务最多占用的通知 ID 槽位数。
  static const _habitReminderSlots = 32;

  /// 通知点击后的路由回调，由 UI 层（MyApp）注入。
  /// payload 约定：tasks / finance / anniversaries。
  void Function(String payload)? onPayloadTap;
  String? _pendingPayload;

  /// 今日待办项（常驻通知轮播 + 快捷打卡）。kind 决定点“完成”时走
  /// 哪种领奖：review/habit → 日常任务领奖，special → 特殊任务完成。
  static const claimActionId = 'claim_task';

  /// 今日待办任务名称清单，供常驻通知轮播展示。
  List<String> _todayTaskNames = [];
  List<({int id, String kind})> _todayTaskItems = [];

  /// 积分目标进度文案（“我的-愿望”里设为目标后进入轮播）；null 表示未设置。
  String? _goalLine;
  int _carouselIndex = 0;
  Timer? _carouselTimer;
  String _lastSyncDateKey = '';

  /// 将“提前分钟数”格式化为通知文案，如 0 → 现在开始，
  /// 15 → 将在 15 分钟后开始，1440 → 将在 1 天后开始。
  static String _leadTimeText(int minutesBefore) {
    if (minutesBefore <= 0) return '现在开始';
    if (minutesBefore % 1440 == 0) {
      final days = minutesBefore ~/ 1440;
      return days == 1 ? '将在 1 天后开始' : '将在 $days 天后开始';
    }
    final hours = minutesBefore ~/ 60;
    final mins = minutesBefore % 60;
    if (hours == 0) return '将在 $mins 分钟后开始';
    if (mins == 0) return '将在 $hours 小时后开始';
    return '将在 $hours 小时 $mins 分钟后开始';
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _scheduleQueue = Future<void>.value();

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      timezone.setLocalLocation(
        timezone.getLocation(localTimezone.identifier),
      );
    } catch (_) {
      // 某些设备/模拟器返回的时区名（如 "GMT"）不在 tz 数据库中，
      // 按系统偏移量选择 Etc/GMT 时区（tz 库为 POSIX 反号约定：
      // UTC+8 对应 Etc/GMT-8），避免通知时间整体偏移。
      final offset = DateTime.now().timeZoneOffset;
      var name = 'Etc/UTC';
      final hours = offset.inMinutes ~/ 60;
      final minutes = offset.inMinutes % 60;
      if (minutes == 0 && hours >= -12 && hours <= 14 && hours != 0) {
        name = 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
      }
      try {
        timezone.setLocalLocation(timezone.getLocation(name));
      } catch (_) {
        // 仍失败时回退 UTC，避免通知初始化整体失败。
        timezone.setLocalLocation(timezone.getLocation('Etc/UTC'));
      }
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (response) {
        // 快捷打卡按钮：actionId 命中时后台领奖，不打开界面。
        if (response.actionId == claimActionId) {
          unawaited(_handleClaimFromNotification(response.payload));
          return;
        }
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final handler = onPayloadTap;
        if (handler != null) {
          handler(payload);
        } else {
          // UI 尚未注入回调（冷启动早期），暂存等待消费。
          _pendingPayload = payload;
        }
      },
    );
  }

  /// 后台 isolate 中的快捷打卡入口：后台 isolate 的单例是全新状态，
  /// 需先加载设置（否则 notificationsEnabled 默认值 false 会导致
  /// syncSchedule 误清空全部通知），再执行领奖与排程刷新。
  Future<void> handleClaimActionInBackground(String? payload) async {
    try {
      await initialize();
      await AppSettingsController.instance.load();
      await _handleClaimFromNotification(payload);
    } catch (error, stackTrace) {
      debugPrint('通知快捷打卡失败（已忽略）: $error\n$stackTrace');
    }
  }

  /// 通知“完成”按钮的后台领奖：按 payload 中的 id+kind 调用对应领奖
  /// 逻辑（复用 PointsService 的事务校验），成功后重新同步排程以刷新
  /// 常驻通知清单。失败（已领过/不在复习窗口等）静默忽略并刷新。
  Future<void> _handleClaimFromNotification(String? payload) async {
    try {
      final parts = (payload ?? '').split('|');
      if (parts.length < 3) return;
      final taskId = int.tryParse(parts[1]);
      if (taskId == null) return;
      final kind = parts[2];
      final now = DateTime.now();
      switch (kind) {
        case 'review':
          await PointsService.claimDailyTaskReward(taskId: taskId, date: now);
        case 'habit':
          await PointsService.claimHabitTaskReward(taskId: taskId, date: now);
        case 'special':
          await PointsService.completeSpecialTask(taskId);
        case 'long':
          await PointsService.completeLongTermTask(taskId);
      }
      // 刷新今日待办（移除已领项）与排程。
      await syncSchedule();
    } catch (error, stackTrace) {
      debugPrint('通知快捷打卡失败（已忽略）: $error\n$stackTrace');
    }
  }

  /// 应用冷启动被通知拉起时返回其 payload；同时冲刷暂存的待处理 payload。
  Future<String?> getLaunchPayload() async {
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      _pendingPayload = null;
      return details!.notificationResponse?.payload;
    }
    final pending = _pendingPayload;
    _pendingPayload = null;
    return pending;
  }

  Future<void> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      throw StateError('当前平台不支持本地通知');
    }
    final granted = await android.requestNotificationsPermission();
    if (granted != true) {
      throw StateError('通知权限未开启，请在系统设置中允许生活手账发送通知');
    }
  }

  Future<void> syncSchedule() {
    return _runScheduleUpdate();
  }

  /// 立即展示一条业务通知（如逾期扣分提示）。
  /// 通知功能未开启或插件未初始化时静默忽略，不影响业务流程。
  Future<void> showInfo({
    required String title,
    required String body,
    String payload = 'tasks',
  }) async {
    try {
      if (!AppSettingsController.instance.notificationsEnabled) return;
      await initialize();
      _transientNotificationId =
          (_transientNotificationId + 1) % 100000;
      await _plugin.show(
        id: AppConstants.transientNotificationIdBase +
            _transientNotificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_reminders',
            '生活提醒',
            channelDescription: '任务、纪念日和日常记账提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // 通知失败不阻断扣分/返还主流程。
    }
  }

  int _transientNotificationId = 0;

  Future<void> _runScheduleUpdate() async {
    final previous = _scheduleQueue;
    final completed = Completer<void>();
    _scheduleQueue = completed.future;
    try {
      await previous;
      await _syncSchedule();
    } finally {
      completed.complete();
    }
  }

  Future<void> _syncSchedule() async {
    await initialize();
    if (!AppSettingsController.instance.notificationsEnabled) {
      _stopCarousel();
      await _plugin.cancelAll();
      return;
    }

    final db = await AppDatabase.instance.database;
    final anniversaries = await db.query(
      'anniversaries',
      columns: [
        'anniversary_id',
        'title',
        'event_date',
        'calendar_type',
        'repeat_type',
        'repeat_custom_days',
      ],
    );
    final specialTasks = await db.query(
      'special_tasks',
      columns: ['id', 'name', 'start_time', 'status_tag'],
      where: "status_tag != '已完成' AND is_deleted = 0",
    );
    // B2：每个特殊任务可有多个提前提醒（子表配置）。
    final specialReminders =
        await TaskRepository.instance.loadAllSpecialTaskReminders();
    final todayKey = TimeUtil.toDateKey(DateTime.now());
    final dailyTasks = await db.rawQuery(
      '''
      SELECT dt.id, dt.name, dt.next_review_time, dt.start_time,
             dt.task_mode, dt.repeat_type, dt.repeat_value,
             EXISTS (
               SELECT 1 FROM daily_task_reward_logs log
               WHERE log.task_id = dt.id AND log.reward_date = ?
             ) AS claimed_today
      FROM daily_tasks dt
      WHERE dt.status_tag = '进行中' AND dt.is_deleted = 0
      ''',
      [todayKey],
    );
    // B1：习惯型任务的多个提醒时刻。
    final dailyReminders =
        await TaskRepository.instance.loadAllDailyTaskReminders();
    // 长期任务：截止当天进今日待办，并在截止时刻推送一次到期提醒。
    final longTasks = await db.rawQuery(
      '''
      SELECT task_id, title, deadline
      FROM tasks
      WHERE task_type = 'long' AND status != '已完成'
        AND deadline IS NOT NULL
      ''',
    );
    final now = DateTime.now();
    var dueTodayCount = 0;
    final todayPending = <String>[];
    final todayItems = <({int id, String kind})>[];
    await _plugin.cancelAll();

    // 纪念日：按重复规则算出下一次发生日期，在当天早上推送提醒。
    final todayStart = DateTime(now.year, now.month, now.day);
    for (final item in anniversaries) {
      final eventDate = DateTime.tryParse('${item['event_date']}');
      if (eventDate == null) continue;
      final nextDate = computeNextAnniversaryDate(
        eventDate: eventDate,
        today: now,
        calendarType: item['calendar_type'] as int? ?? 0,
        repeatType: item['repeat_type'] as int? ?? 1,
        repeatCustomDays: item['repeat_custom_days'] as int? ?? 0,
      );
      // 不重复且日期已过的纪念日不再提醒。
      if (nextDate.isBefore(todayStart)) continue;
      final isToday =
          nextDate.year == now.year &&
          nextDate.month == now.month &&
          nextDate.day == now.day;
      DateTime reminderAt;
      if (isToday) {
        // 与复习任务一致的补排策略：提醒时间未到排设定时刻，
        // 正午前补排 12 点，之后不再打扰（用户已在用 App，页面上能看到）。
        final morning = DateTime(
          now.year,
          now.month,
          now.day,
          AppSettingsController.instance.anniversaryReminderHour,
        );
        final catchup = DateTime(
          now.year,
          now.month,
          now.day,
          AppConstants.reviewReminderCatchupHour,
        );
        if (morning.isAfter(now)) {
          reminderAt = morning;
        } else if (catchup.isAfter(now)) {
          reminderAt = catchup;
        } else {
          continue;
        }
      } else {
        reminderAt = DateTime(
          nextDate.year,
          nextDate.month,
          nextDate.day,
          AppSettingsController.instance.anniversaryReminderHour,
        );
      }
      await _schedule(
        id: AppConstants.anniversaryNotificationIdOffset +
            (item['anniversary_id'] as int),
        title: '纪念日提醒',
        body: '今天是：${item['title']}',
        at: reminderAt,
        payload: 'anniversaries',
      );
    }

    // 特殊语录（时光信箱）：解锁日为今天时推送“特殊礼物”通知，
    // 补排策略与纪念日一致（设定时刻未到排设定时刻，正午前补 12 点）。
    final capsuleRows = await db.query(
      'time_capsules',
      columns: ['id'],
      where: 'unlock_date = ?',
      whereArgs: [todayKey],
    );
    for (final capsule in capsuleRows) {
      final morning = DateTime(
        now.year,
        now.month,
        now.day,
        AppSettingsController.instance.anniversaryReminderHour,
      );
      final catchup = DateTime(
        now.year,
        now.month,
        now.day,
        AppConstants.reviewReminderCatchupHour,
      );
      DateTime? remindAt;
      if (morning.isAfter(now)) {
        remindAt = morning;
      } else if (catchup.isAfter(now)) {
        remindAt = catchup;
      }
      if (remindAt == null) continue;
      await _schedule(
        id: AppConstants.timeCapsuleNotificationIdOffset +
            (capsule['id'] as int),
        title: '特殊礼物',
        body: '今天收到了一份特殊礼物，打开看看吧',
        at: remindAt,
        payload: 'home',
      );
    }

    for (final task in specialTasks) {
      final start = DateTime.tryParse('${task['start_time']}');
      if (start == null) continue;
      final taskId = task['id'] as int;
      // 今天开始的特殊任务纳入今日待办常驻通知。
      if (start.year == now.year &&
          start.month == now.month &&
          start.day == now.day) {
        todayPending.add('${task['name']}');
        todayItems.add((id: taskId, kind: 'special'));
      }
      // 未配置提醒（旧数据/异常数据）时按个性化参数中的默认提前量兜底。
      final remindMinutes = specialReminders[taskId] ??
          [AppSettingsController.instance.defaultRemindMinutes];
      for (var index = 0; index < remindMinutes.length; index++) {
        final minutes = remindMinutes[index];
        final reminder = start.subtract(Duration(minutes: minutes));
        if (!reminder.isAfter(now)) continue;
        await _schedule(
          // 每个任务预留 _specialReminderSlots 个通知位，
          // 避免同一任务多条提醒的 ID 冲突。
          id: AppConstants.specialTaskNotificationIdOffset +
              taskId * _specialReminderSlots +
              index,
          title: minutes == 0 ? '特殊任务现在开始' : '特殊任务即将开始',
          body: '${task['name']} ${_leadTimeText(minutes)}',
          at: reminder,
          payload: 'tasks',
        );
      }
    }

    for (final task in dailyTasks) {
      final claimedToday = (task['claimed_today'] as int?) == 1;
      final taskId = task['id'] as int;
      final isHabit = task['task_mode'] == 'habit';

      if (isHabit) {
        // 习惯型：今天是打卡日且未领奖时，按用户配置的多个时刻各排一条。
        if (claimedToday) continue;
        final start = DateTime.tryParse('${task['start_time']}');
        if (start == null) continue;
        final rule = RepeatRule.fromColumns(
          task['repeat_type'] as String?,
          task['repeat_value'] as String?,
        );
        if (!rule.isDueOn(now, start)) continue;
        dueTodayCount++;
        todayPending.add('${task['name']}');
        todayItems.add((id: taskId, kind: 'habit'));
        final times = dailyReminders[taskId] ??
            const [
              (hour: AppConstants.reminderMorningHour, minute: 0),
            ];
        for (var index = 0; index < times.length; index++) {
          final time = times[index];
          final at = DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          );
          if (!at.isAfter(now)) continue;
          await _schedule(
            id: AppConstants.habitTaskNotificationIdOffset +
                taskId * _habitReminderSlots +
                index,
            title: '习惯打卡提醒',
            body: '今天记得打卡：${task['name']}（${rule.displayText}）',
            at: at,
            payload: 'tasks',
          );
        }
        continue;
      }

      // 复习型（原有艾宾浩斯逻辑）。
      final review = DateTime.tryParse('${task['next_review_time']}');
      if (review == null) continue;
      final reviewDay = DateTime(review.year, review.month, review.day);
      // 过去的复习日不再补排通知（任务列表仍允许补领）；未来复习日排 9:00。
      if (reviewDay.isBefore(todayStart)) continue;

      DateTime reminderAt;
      if (reviewDay.isAfter(todayStart)) {
        reminderAt = DateTime(
          review.year,
          review.month,
          review.day,
          AppConstants.reminderMorningHour,
        );
      } else {
        // 当天复习日：9:00 未到则正常排；9:00 已过但还没到正午，补排一次
        // 12:00 的提醒。固定时刻保证重复同步不会产生多条通知，正午之后
        // 同步则当天不再补排（用户已在使用 App，列表中能看到任务）。
        if (!claimedToday) {
          dueTodayCount++;
          todayPending.add('${task['name']}');
          todayItems.add((id: taskId, kind: 'review'));
        }
        final morning = DateTime(
          review.year,
          review.month,
          review.day,
          AppConstants.reminderMorningHour,
        );
        final catchup = DateTime(
          review.year,
          review.month,
          review.day,
          AppConstants.reviewReminderCatchupHour,
        );
        if (morning.isAfter(now)) {
          reminderAt = morning;
        } else if (catchup.isAfter(now)) {
          reminderAt = catchup;
        } else {
          continue;
        }
      }
      await _schedule(
        id: AppConstants.dailyTaskNotificationIdOffset + taskId,
        title: '今日任务提醒',
        body: '今天记得完成：${task['name']}',
        at: reminderAt,
        payload: 'tasks',
      );
    }

    for (final task in longTasks) {
      final deadline = DateTime.tryParse('${task['deadline']}');
      if (deadline == null) continue;
      final taskId = task['task_id'] as int;
      final deadlineDay = DateTime(
        deadline.year,
        deadline.month,
        deadline.day,
      );
      if (deadlineDay == todayStart) {
        todayPending.add('${task['title']}（今日截止）');
        todayItems.add((id: taskId, kind: 'long'));
      }
      // 截止时刻未到：排一条到期提醒；已过则不补打扰（页面标红 + 扣分提示）。
      if (deadline.isAfter(now)) {
        await _schedule(
          id: AppConstants.longTaskNotificationIdOffset + taskId,
          title: '长期任务到期',
          body: '今天截止：${task['title']}',
          at: deadline,
          payload: 'tasks',
        );
      }
    }

    var financeReminder = DateTime(
      now.year,
      now.month,
      now.day,
      AppConstants.reminderEveningHour,
    );
    if (!financeReminder.isAfter(now)) {
      financeReminder = financeReminder.add(const Duration(days: 1));
    }
    await _schedule(
      id: _financeReminderId,
      title: dueTodayCount == 0 ? '记账提醒' : '日常任务与记账提醒',
      body: dueTodayCount == 0
          ? '花一点时间记录今天的收支吧'
          : '别忘了完成 $dueTodayCount 项日常任务并记录今天的收支',
      at: financeReminder,
      repeatsDaily: true,
      payload: 'finance',
    );

    await _scheduleDailySummary(db, now, todayKey);

    // 积分目标进度并入常驻通知轮播（原首页目标卡迁移至此）。
    String? goalLine;
    try {
      final goal = await const HomeRepository().loadWishGoal();
      if (goal != null) {
        final percent = (goal.ratio * 100).round();
        goalLine = goal.remaining == 0
            ? '目标「${goal.name}」已攒满，去兑换吧'
            : '目标「${goal.name}」$percent% · 还差 ${goal.remaining} 分';
      }
    } catch (_) {
      // 目标读取失败不影响待办轮播。
      goalLine = null;
    }

    // 常驻通知展示今日待办与积分目标：有内容则轮播刷新，无内容则撤下。
    _todayTaskNames = todayPending;
    _todayTaskItems = todayItems;
    _goalLine = goalLine;
    _carouselIndex = 0;
    _lastSyncDateKey = todayKey;
    await _restartCarousel();
  }

  /// 排一条 21:00 的当日小结推送：完成 X 项 · 入账 Y 分 · 连续打卡 Z 天。
  /// 非重复定时，内容在每次同步时用当下统计重新生成，保证数据新鲜；
  /// 用户当天活跃（打开 App/领奖触发同步）才会产出当天的小结，不活跃不打扰。
  Future<void> _scheduleDailySummary(
    dynamic db,
    DateTime now,
    String todayKey,
  ) async {
    var summaryAt = DateTime(
      now.year,
      now.month,
      now.day,
      AppSettingsController.instance.dailySummaryHour,
    );
    // 21 点已过则排到明天，避免今晚再补一条（用户已在用 App）。
    if (!summaryAt.isAfter(now)) {
      summaryAt = summaryAt.add(const Duration(days: 1));
    }

    // 今日完成项数：日常领奖记录 + 今天标记完成的特殊任务。
    final rewardRows = await db.rawQuery(
      'SELECT COUNT(DISTINCT task_id) AS c FROM daily_task_reward_logs '
      'WHERE reward_date = ?',
      [todayKey],
    );
    final dailyDone = (rewardRows.first['c'] as int?) ?? 0;
    final specialRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM special_tasks "
      "WHERE is_deleted = 0 AND completed_at IS NOT NULL "
      "AND substr(completed_at, 1, 10) = ?",
      [todayKey],
    );
    final specialDone = (specialRows.first['c'] as int?) ?? 0;
    final doneCount = dailyDone + specialDone;

    // 今日入账积分（仅正向变动）。
    final pointRows = await db.rawQuery(
      'SELECT COALESCE(SUM(point_value), 0) AS s FROM points '
      'WHERE point_value > 0 AND substr(create_time, 1, 10) = ?',
      [todayKey],
    );
    final income = (pointRows.first['s'] as num?)?.toInt() ?? 0;

    // 连续打卡天数：以今天为终点向前回推存在领奖记录的连续天数。
    final streak = await _computeCheckinStreak(db, now);

    await _schedule(
      id: AppConstants.dailySummaryNotificationId,
      title: '今日小结',
      body: '完成 $doneCount 项 · 入账 $income 分 · 连续打卡 $streak 天',
      at: summaryAt,
      payload: 'home',
    );
  }

  /// 从今天（含）向前数，daily_task_reward_logs 连续有记录的连续自然日数。
  Future<int> _computeCheckinStreak(dynamic db, DateTime now) async {
    var streak = 0;
    var day = DateTime(now.year, now.month, now.day);
    while (true) {
      final key = TimeUtil.toDateKey(day);
      final rows = await db.rawQuery(
        'SELECT 1 FROM daily_task_reward_logs WHERE reward_date = ? LIMIT 1',
        [key],
      );
      if (rows.isEmpty) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
      // 防御性上限，避免脏数据导致长循环。
      if (streak > 3650) break;
    }
    return streak;
  }

  void _stopCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = null;
    _todayTaskNames = [];
    _goalLine = null;
  }

  /// 轮播内容 = 今日待办 + 末尾的积分目标行（如有）。
  List<String> get _carouselLines => [
    ..._todayTaskNames,
    ?_goalLine,
  ];

  Future<void> _restartCarousel() async {
    _carouselTimer?.cancel();
    _carouselTimer = null;
    if (_carouselLines.isEmpty) {
      await _plugin.cancel(id: AppConstants.todayOverviewNotificationId);
      return;
    }
    await _showTodayOverview();
    // App 运行期间定时轮换高亮项，形成轮播效果；
    // 进程被杀后通知保留最后展示的内容，下次启动重新轮播。
    _carouselTimer = Timer.periodic(
      AppConstants.todayOverviewCarouselInterval,
      (_) => unawaited(_onCarouselTick()),
    );
  }

  Future<void> _onCarouselTick() async {
    // 跨天（应用一直挂着）时整体重排，刷新为当天任务与纪念日。
    if (TimeUtil.toDateKey(DateTime.now()) != _lastSyncDateKey) {
      await syncSchedule();
      return;
    }
    final lines = _carouselLines;
    if (lines.isEmpty) return;
    _carouselIndex = (_carouselIndex + 1) % lines.length;
    await _showTodayOverview();
  }

  Future<void> _showTodayOverview() async {
    final lines = _carouselLines;
    if (lines.isEmpty) {
      await _plugin.cancel(id: AppConstants.todayOverviewNotificationId);
      return;
    }
    final names = _todayTaskNames;
    final index = _carouselIndex % lines.length;
    final current = lines[index];
    final isGoalLine = index >= names.length;
    // 当前高亮项对应的任务 id+类型，作为“完成”按钮的上下文；
    // 目标行没有打卡动作，不挂按钮。
    final currentItem = !isGoalLine && index < _todayTaskItems.length
        ? _todayTaskItems[index]
        : null;
    final title = names.isEmpty ? '积分目标' : '今日任务 ${names.length} 项待完成';
    await _plugin.show(
      id: AppConstants.todayOverviewNotificationId,
      title: title,
      body: current,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'today_overview',
          '今日任务',
          channelDescription: '常驻展示今日待办任务与积分目标，点击查看',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          visibility: NotificationVisibility.public,
          actions: [
            if (currentItem != null)
              AndroidNotificationAction(
                claimActionId,
                '完成「$current」',
                showsUserInterface: false,
                cancelNotification: false,
              ),
          ],
          styleInformation: InboxStyleInformation(
            [
              for (var i = 0; i < lines.length; i++)
                i == index ? '👉 ${lines[i]}' : '• ${lines[i]}',
            ],
            contentTitle: title,
          ),
        ),
      ),
      // payload 带上当前项 id+kind，点“完成”按钮据此后台领奖；
      // 目标行点击跳记录页查看愿望清单。
      payload: currentItem != null
          ? 'tasks|${currentItem.id}|${currentItem.kind}'
          : isGoalLine
          ? 'records'
          : 'tasks',
    );
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    bool repeatsDaily = false,
    String? payload,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: timezone.TZDateTime.from(at, timezone.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'personal_reminders',
          '生活提醒',
          channelDescription: '任务、纪念日和日常记账提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.public,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeatsDaily ? DateTimeComponents.time : null,
      payload: payload,
    );
  }
}
