/// B1：自定义习惯型日常任务的重复规则。
///
/// - [daily]：每天；
/// - [weekly]：每周指定星期（ISO，周一=1 … 周日=7），[value] 形如 `1,3,5`；
/// - [monthly]：每月指定日期（1-31），[value] 形如 `1,15`；
/// - [interval]：自开始日起每 N 天一次，[value] 为正整数字符串。
enum RepeatType { daily, weekly, monthly, interval }

class RepeatRule {
  const RepeatRule({required this.type, this.value});

  final RepeatType type;
  final String? value;

  static RepeatRule fromColumns(String? type, String? value) {
    final parsed = switch (type) {
      'weekly' => RepeatType.weekly,
      'monthly' => RepeatType.monthly,
      'interval' => RepeatType.interval,
      _ => RepeatType.daily,
    };
    final rule = RepeatRule(type: parsed, value: value?.trim());
    // 配置损坏（空值/非法数字）时退化为每天，保证任务仍可打卡。
    if (!rule.isValid) return const RepeatRule(type: RepeatType.daily);
    return rule;
  }

  static List<int> intList(String? raw) => (raw?.split(',') ?? const [])
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toSet()
      .toList()
    ..sort();

  static String encode(List<int> values) {
    final ordered = values.toSet().toList()..sort();
    return ordered.join(',');
  }

  bool get isValid {
    switch (type) {
      case RepeatType.daily:
        return true;
      case RepeatType.weekly:
        final values = intList(value);
        return values.isNotEmpty && values.every((v) => v >= 1 && v <= 7);
      case RepeatType.monthly:
        final values = intList(value);
        return values.isNotEmpty && values.every((v) => v >= 1 && v <= 31);
      case RepeatType.interval:
        final days = int.tryParse((value ?? '').trim());
        return days != null && days >= 1;
    }
  }

  /// [day] 是否为打卡日（仅判断日期，时刻由提醒点决定）。
  /// 开始日之前永远不是打卡日。
  bool isDueOn(DateTime day, DateTime startDay) {
    final target = DateTime(day.year, day.month, day.day);
    final start = DateTime(startDay.year, startDay.month, startDay.day);
    if (target.isBefore(start)) return false;
    switch (type) {
      case RepeatType.daily:
        return true;
      case RepeatType.weekly:
        return intList(value).contains(target.weekday);
      case RepeatType.monthly:
        return intList(value).contains(target.day);
      case RepeatType.interval:
        final days = int.tryParse((value ?? '').trim()) ?? 1;
        return target.difference(start).inDays % days == 0;
    }
  }

  String get dbValue {
    switch (type) {
      case RepeatType.daily:
        return 'daily';
      case RepeatType.weekly:
        return 'weekly';
      case RepeatType.monthly:
        return 'monthly';
      case RepeatType.interval:
        return 'interval';
    }
  }

  String get displayText {
    switch (type) {
      case RepeatType.daily:
        return '每天';
      case RepeatType.weekly:
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final days = intList(value)..sort();
        return '每周 ${days.map((d) => '周${names[d - 1]}').join('、')}';
      case RepeatType.monthly:
        final days = intList(value)..sort();
        return '每月 ${days.map((d) => '$d 号').join('、')}';
      case RepeatType.interval:
        final days = int.tryParse((value ?? '').trim()) ?? 1;
        return '每 $days 天';
    }
  }
}
