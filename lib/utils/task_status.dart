/// 特殊任务展示状态计算：存储的 status_tag 可能滞后（如到期后仍是
/// 「进行中」），任务页与首页统一用本函数按时间实时计算，保证两处
/// 「进行中」口径一致。
String computeSpecialStatus(Map<String, dynamic> task) {
  final storedStatus = task['status_tag'] as String? ?? '未开始';
  if (storedStatus == '已完成') return storedStatus;
  if (storedStatus == '未完成') return '已结束';
  final start = DateTime.tryParse('${task['start_time']}');
  final end = DateTime.tryParse('${task['end_time']}');
  if (start == null || end == null) return storedStatus;
  final now = DateTime.now();
  if (now.isBefore(start)) return '未开始';
  if (now.isAfter(end)) return '已结束';
  return '进行中';
}
