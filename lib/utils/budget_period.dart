/// 支出分类的预算结算周期工具。
///
/// period_key 统一使用「周期起始日」的 yyyy-MM-dd 字符串，
/// 配合 period_type 即可唯一确定一个周期，便于存储与比较。
abstract final class BudgetPeriods {
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const quarterly = 'quarterly';

  /// 可结算周期（不含 none），同时也是界面展示顺序。
  static const types = [daily, weekly, monthly, quarterly];

  static const labels = <String, String>{
    daily: '每天',
    weekly: '每周',
    monthly: '每月',
    quarterly: '每季度',
  };

  static bool isSettled(String type) => type != 'none' && labels.containsKey(type);

  static String labelOf(String type) => labels[type] ?? '不结算';

  /// 返回 [date] 所在周期的起始日（时间部分归零）。
  /// 每周以周一为起点。
  static DateTime startOf(String type, DateTime date) {
    return switch (type) {
      daily => DateTime(date.year, date.month, date.day),
      weekly =>
        DateTime(date.year, date.month, date.day)
            .subtract(Duration(days: date.weekday - DateTime.monday)),
      monthly => DateTime(date.year, date.month),
      quarterly => DateTime(date.year, ((date.month - 1) ~/ 3) * 3 + 1),
      _ => DateTime(date.year, date.month, date.day),
    };
  }

  /// 返回 [start] 之后下一个周期的起始日（[start] 必须由 [startOf] 得到）。
  static DateTime nextStart(String type, DateTime start) {
    return switch (type) {
      daily => start.add(const Duration(days: 1)),
      weekly => start.add(const Duration(days: 7)),
      monthly => DateTime(start.year, start.month + 1),
      quarterly => DateTime(start.year, start.month + 3),
      _ => start.add(const Duration(days: 1)),
    };
  }

  /// 周期起始日 -> 存储用 period_key。
  static String keyOf(DateTime start) =>
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  /// 解析 period_key；非法日期返回 null。
  static DateTime? parseKey(String key) => DateTime.tryParse(key);
}
