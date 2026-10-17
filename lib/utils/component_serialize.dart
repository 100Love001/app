import 'dart:convert';

import 'package:app/constants/app_constants.dart';

String serializeTaskComponents(List<Map<String, Object?>> components) =>
    jsonEncode({'version': 1, 'components': components});

List<Map<String, Object?>> deserializeTaskComponents(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic> ||
      decoded['components'] is! List<dynamic>) {
    throw const FormatException('任务组件配置格式无效');
  }
  final components = decoded['components'] as List<dynamic>;
  return components.map((component) {
    if (component is! Map<String, dynamic>) {
      throw const FormatException('任务组件必须是对象');
    }
    final type = component['type'];
    if (type is! String || ComponentType.fromId(type) == null) {
      throw const FormatException('任务组件类型无效');
    }
    return Map<String, Object?>.from(component);
  }).toList();
}

List<Map<String, Object?>> defaultTaskComponents(TaskType type) {
  final components = switch (type) {
    TaskType.daily => [
      ComponentType.deadline,
      ComponentType.repeatRule,
      ComponentType.rewardPoints,
      ComponentType.penaltyPoints,
      ComponentType.mood,
      ComponentType.weight,
      ComponentType.remark,
    ],
    TaskType.longTerm => [
      ComponentType.deadline,
      ComponentType.progress,
      ComponentType.subtasks,
      ComponentType.rewardPoints,
      ComponentType.penaltyPoints,
      ComponentType.weight,
      ComponentType.remark,
    ],
    TaskType.shortTerm => [
      ComponentType.timeRange,
      ComponentType.rewardPoints,
      ComponentType.penaltyPoints,
      ComponentType.remark,
    ],
    TaskType.habit => [
      ComponentType.repeatRule,
      ComponentType.mood,
      ComponentType.weight,
      ComponentType.checkinCounter,
      ComponentType.remark,
    ],
    TaskType.wish || TaskType.hope => [
      ComponentType.deadline,
      ComponentType.progress,
      ComponentType.remark,
    ],
  };
  return [
    for (final component in components)
      {'type': component.id, 'enabled': true, 'value': null},
  ];
}
