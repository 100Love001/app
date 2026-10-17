import 'dart:async';

import 'package:intl/intl.dart';

/// 时间工具类：统一处理系统时间获取、格式化
class TimeUtil {
  /// 获取【一次性】当前时间字符串（只获取一次，不会自动刷新）
  /// 格式示例：2026-09-25 14:30:20
  static String getCurrentTime() {
    final now = DateTime.now();
    // intl包格式化时间
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
  }

  /// 获取【实时时间流】每秒自动发射最新时间，用于页面时钟实时刷新
  /// 返回Stream，UI层监听，实现动态时钟
  static Stream<String> watchTimeStream() {
    // 定时器，每1秒执行一次
    return Stream.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    });
  }

  /// 自定义格式获取时间，可传格式模板
  /// 例如：DateFormat('HH:mm') → 14:30
  static String formatDateTime(
    DateTime dateTime, {
    String pattern = 'yyyy-MM-dd HH:mm',
  }) {
    return DateFormat(pattern).format(dateTime);
  }

  /// 格式化为 yyyy-MM-dd（用于数据库存储）
  static String toDateKey(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd').format(dateTime);
  }

  /// 格式化为 yyyy年MM月dd日（用于中文显示）
  static String toChineseDate(DateTime dateTime) {
    return DateFormat('yyyy年MM月dd日').format(dateTime);
  }

  /// 格式化为 yyyy年MM月dd日 EEEE（用于中文显示带星期）
  static String toChineseDateWithWeekday(DateTime dateTime) {
    return DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN').format(dateTime);
  }

  /// 格式化日期范围显示
  static String formatDateRange(DateTime start, DateTime end) {
    return '${toDateKey(start)} 至 ${toDateKey(end)}';
  }
}
