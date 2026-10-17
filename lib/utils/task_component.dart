import 'dart:convert';

import 'package:app/constants/app_constants.dart';

/// 动态组件实例：[type] 决定渲染哪种表单组件，
/// [data] 保存该组件的全部表单数据（随任务 component_json 列持久化）。
class TaskComponent {
  const TaskComponent({required this.type, this.data = const {}});

  final ComponentType type;
  final Map<String, dynamic> data;

  TaskComponent copyWith({ComponentType? type, Map<String, dynamic>? data}) =>
      TaskComponent(type: type ?? this.type, data: data ?? this.data);

  Map<String, dynamic> toJson() => {'type': type.id, 'data': data};

  /// 单条解析容错：损坏/未知类型返回 null，由文档层跳过。
  static TaskComponent? fromJsonSafe(dynamic raw) {
    if (raw is! Map) return null;
    final type = ComponentType.fromId(raw['type'] as String?);
    if (type == null) return null;
    final dataRaw = raw['data'];
    final data = <String, dynamic>{};
    if (dataRaw is Map) {
      dataRaw.forEach((key, value) {
        if (key is String) data[key] = value;
      });
    }
    return TaskComponent(type: type, data: data);
  }
}

/// 组件 data 字段键名集中处，禁止散落裸字符串。
abstract final class ComponentDataKeys {
  const ComponentDataKeys._();

  static const text = 'text';
  static const start = 'start'; // ISO8601
  static const end = 'end';
  static const repeatType = 'repeat_type';
  static const repeatValue = 'repeat_value';
  static const reminderMinutes = 'minutes'; // 特殊任务：提前分钟数列表
  static const reminderTimes = 'times'; // 习惯任务：[{h:9,m:0}]
  static const tagId = 'tag_id'; // 特殊/日常：标签表 id
  static const tagText = 'tag_text'; // 长期：自由文本标签
  static const points = 'points';
  static const enabled = 'enabled';
  static const value = 'value'; // 进度百分比
  static const items = 'items'; // 子任务 [{text,done}]
  static const count = 'count'; // 打卡次数
  static const files = 'files'; // 图片/语音 [{name,path}]
}

/// 任务的组件文档：有序组件列表 + 类型安全的增删改与 JSON 互转。
/// 解析失败时退化为空文档（老任务由仓储层用列数据重建默认文档）。
class TaskComponentDocument {
  TaskComponentDocument([List<TaskComponent>? components])
    : components = components ?? <TaskComponent>[];

  final List<TaskComponent> components;

  bool has(ComponentType type) => indexOf(type) >= 0;

  int indexOf(ComponentType type) =>
      components.indexWhere((item) => item.type == type);

  Map<String, dynamic> dataOf(ComponentType type) {
    final index = indexOf(type);
    return index < 0 ? const {} : components[index].data;
  }

  void upsert(ComponentType type, [Map<String, dynamic> data = const {}]) {
    final index = indexOf(type);
    if (index < 0) {
      components.add(TaskComponent(type: type, data: Map.of(data)));
    } else {
      components[index] = TaskComponent(type: type, data: Map.of(data));
    }
  }

  /// 更新已存在组件的数据；不存在时忽略。
  void updateData(ComponentType type, Map<String, dynamic> data) {
    final index = indexOf(type);
    if (index >= 0) {
      components[index] = TaskComponent(type: type, data: Map.of(data));
    }
  }

  void remove(ComponentType type) {
    components.removeWhere((item) => item.type == type);
  }

  /// Flutter 3.41+ 的 onReorderItem 回调给出的 newIndex 已按移除项修正，
  /// 直接插入即可。
  void reorder(int oldIndex, int newIndex) {
    if (newIndex < 0 ||
        newIndex >= components.length ||
        oldIndex < 0 ||
        oldIndex >= components.length) {
      return;
    }
    final item = components.removeAt(oldIndex);
    components.insert(newIndex, item);
  }

  /// 尚未添加的组件（每种组件在一个任务内最多一个实例）。
  List<ComponentType> get availableTypes =>
      ComponentType.values.where((type) => !has(type)).toList();

  String encode() => jsonEncode(
    components.map((component) => component.toJson()).toList(),
  );

  static TaskComponentDocument decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return TaskComponentDocument();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return TaskComponentDocument();
      final result = <TaskComponent>[];
      for (final item in decoded) {
        final component = TaskComponent.fromJsonSafe(item);
        if (component != null) result.add(component);
      }
      return TaskComponentDocument(result);
    } catch (_) {
      return TaskComponentDocument();
    }
  }

  // ---------------- 类型安全的取值辅助 ----------------

  static String text(Map<String, dynamic> data) =>
      (data[ComponentDataKeys.text] as String?) ?? '';

  static DateTime? dateTime(Map<String, dynamic> data, String key) =>
      DateTime.tryParse('${data[key]}');

  static int intValue(Map<String, dynamic> data, String key, [int fallback = 0]) {
    final raw = data[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? fallback;
  }

  static List<Map<String, dynamic>> fileItems(Map<String, dynamic> data) {
    final raw = data[ComponentDataKeys.files];
    if (raw is! List) return <Map<String, dynamic>>[];
    return [
      for (final item in raw)
        if (item is Map)
          <String, dynamic>{'name': '${item['name'] ?? ''}', 'path': '${item['path'] ?? ''}'},
    ];
  }

  static List<Map<String, dynamic>> subtaskItems(Map<String, dynamic> data) {
    final raw = data[ComponentDataKeys.items];
    if (raw is! List) return <Map<String, dynamic>>[];
    return [
      for (final item in raw)
        if (item is Map)
          <String, dynamic>{
            'text': '${item['text'] ?? ''}',
            'done': item['done'] == true,
          },
    ];
  }

  /// 按任务大类生成默认组件集（新建任务时使用）。
  factory TaskComponentDocument.defaultFor(TaskType type) {
    switch (type) {
      case TaskType.shortTerm:
        return TaskComponentDocument([
          TaskComponent(
            type: ComponentType.timeRange,
            data: _defaultTimeRange(withEnd: true),
          ),
          const TaskComponent(type: ComponentType.reminders, data: {
            ComponentDataKeys.reminderMinutes: [15],
          }),
          const TaskComponent(type: ComponentType.tag),
          const TaskComponent(type: ComponentType.content),
          const TaskComponent(type: ComponentType.requirement),
          const TaskComponent(type: ComponentType.remark),
          TaskComponent(
            type: ComponentType.rewardPoints,
            data: {ComponentDataKeys.points: 10},
          ),
          TaskComponent(
            type: ComponentType.penaltyPoints,
            data: {ComponentDataKeys.enabled: true, ComponentDataKeys.points: 0},
          ),
        ]);
      case TaskType.daily:
        return TaskComponentDocument([
          TaskComponent(
            type: ComponentType.timeRange,
            data: _defaultTimeRange(withEnd: false),
          ),
          const TaskComponent(type: ComponentType.tag),
          const TaskComponent(type: ComponentType.content),
          const TaskComponent(type: ComponentType.requirement),
          const TaskComponent(type: ComponentType.remark),
          TaskComponent(
            type: ComponentType.rewardPoints,
            data: {ComponentDataKeys.points: 1},
          ),
          TaskComponent(
            type: ComponentType.penaltyPoints,
            data: {ComponentDataKeys.enabled: true, ComponentDataKeys.points: 0},
          ),
        ]);
      case TaskType.habit:
        return TaskComponentDocument([
          TaskComponent(
            type: ComponentType.timeRange,
            data: _defaultTimeRange(withEnd: false),
          ),
          TaskComponent(
            type: ComponentType.repeatRule,
            data: {
              ComponentDataKeys.repeatType: 'daily',
              ComponentDataKeys.repeatValue: null,
              ComponentDataKeys.reminderTimes: [
                {'h': AppConstants.reminderMorningHour, 'm': 0},
              ],
            },
          ),
          const TaskComponent(type: ComponentType.tag),
          const TaskComponent(type: ComponentType.content),
          const TaskComponent(type: ComponentType.remark),
          TaskComponent(
            type: ComponentType.rewardPoints,
            data: {ComponentDataKeys.points: 1},
          ),
          TaskComponent(
            type: ComponentType.penaltyPoints,
            data: {ComponentDataKeys.enabled: true, ComponentDataKeys.points: 0},
          ),
        ]);
      case TaskType.longTerm:
        final now = DateTime.now();
        final deadline = DateTime(now.year, now.month, now.day, 23, 59)
            .add(const Duration(days: 7));
        return TaskComponentDocument([
          TaskComponent(
            type: ComponentType.deadline,
            data: {ComponentDataKeys.end: deadline.toIso8601String()},
          ),
          const TaskComponent(type: ComponentType.tag),
          const TaskComponent(type: ComponentType.content),
          const TaskComponent(type: ComponentType.remark),
          TaskComponent(
            type: ComponentType.rewardPoints,
            data: {ComponentDataKeys.points: 10},
          ),
          TaskComponent(
            type: ComponentType.penaltyPoints,
            data: {ComponentDataKeys.enabled: true, ComponentDataKeys.points: 0},
          ),
        ]);
      case TaskType.wish:
      case TaskType.hope:
        return TaskComponentDocument();
    }
  }

  static Map<String, dynamic> _defaultTimeRange({required bool withEnd}) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    return {
      ComponentDataKeys.start: start.toIso8601String(),
      if (withEnd)
        ComponentDataKeys.end: start
            .add(const Duration(hours: 1))
            .toIso8601String(),
    };
  }
}
