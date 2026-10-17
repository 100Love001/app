import 'dart:io';

import 'package:app/constants/app_constants.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/tasks/task_component_repository.dart';
import 'package:app/stores/tasks/task_repository.dart';
import 'package:app/utils/num_cast.dart';
import 'package:app/utils/repeat_rule.dart';
import 'package:app/utils/task_component.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'task_trend_page.dart';

/// 动态任务编辑器入参：[type] 为初始任务类型，[existing] 为编辑时的原始行。
class TaskEditorArgs {
  const TaskEditorArgs({required this.type, this.existing});

  final TaskType type;
  final Map<String, dynamic>? existing;
}

/// 特殊任务提醒预设提前量（分钟），0 = 准时。
const _specialReminderPresets = [0, 15, 30, 60, 1440, 4320, 10080];

String _leadLabel(int minutes) {
  if (minutes == 0) return '准时';
  if (minutes % 1440 == 0) return '提前 ${minutes ~/ 1440} 天';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '提前 $mins 分钟';
  if (mins == 0) return '提前 $hours 小时';
  return '提前 $hours 小时$mins 分';
}

/// 任务编辑器：标题 + 任务类型固定，其余全部为可增删 / 排序的动态组件，
/// 组件配置与数据以 JSON 存入任务表 component_json 列。
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, required this.args});

  final TaskEditorArgs args;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late TaskType _type;
  late final TextEditingController _titleController;
  late TaskComponentDocument _doc;
  late final bool _isExisting;
  late final int? _taskId;

  List<Map<String, dynamic>> _specialTags = [];
  List<Map<String, dynamic>> _dailyTags = [];
  bool _saving = false;

  TaskType get _initialType => widget.args.type;

  @override
  void initState() {
    super.initState();
    final existing = widget.args.existing;
    _isExisting = existing != null;
    _type = _initialType;
    _titleController = TextEditingController(
      text: (existing?['name'] ?? existing?['title']) as String? ?? '',
    );
    _taskId =
        existing == null
            ? null
            : toInt(existing['task_id'] ?? existing['id']);
    _doc = _buildDocument(_type, existing);
    _loadTagsAndReminders(existing);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  TaskComponentDocument _buildDocument(
    TaskType type,
    Map<String, dynamic>? row,
  ) {
    final rawJson = row?['component_json'] as String?;
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      return TaskComponentDocument.decode(rawJson);
    }
    // 老数据（component_json 为空）：从列字段重建默认文档。
    final doc = TaskComponentDocument.defaultFor(type);
    if (row == null) return doc;
    String text(String key) => (row[key] as String?) ?? '';
    int? idOf(Object? value) => value == null ? null : toInt(value);

    doc.updateData(
      ComponentType.content,
      {ComponentDataKeys.text: text('content')},
    );
    if (doc.has(ComponentType.requirement)) {
      doc.updateData(
        ComponentType.requirement,
        {ComponentDataKeys.text: text('requirement')},
      );
    }
    if (doc.has(ComponentType.remark)) {
      doc.updateData(
        ComponentType.remark,
        {ComponentDataKeys.text: text('remark')},
      );
    }
    if (doc.has(ComponentType.tag)) {
      if (type == TaskType.longTerm) {
        doc.updateData(ComponentType.tag, {
          ComponentDataKeys.tagText: text('tag'),
        });
      } else {
        doc.updateData(ComponentType.tag, {
          ComponentDataKeys.tagId: idOf(row['task_tag_id']),
        });
      }
    }
    final rewardKey = type == TaskType.shortTerm
        ? 'reward_points'
        : type == TaskType.longTerm
        ? 'reward_points'
        : 'daily_points';
    if (doc.has(ComponentType.rewardPoints)) {
      doc.updateData(ComponentType.rewardPoints, {
        ComponentDataKeys.points: toInt(row[rewardKey]),
      });
    }
    if (doc.has(ComponentType.penaltyPoints)) {
      doc.updateData(ComponentType.penaltyPoints, {
        ComponentDataKeys.enabled: toInt(row['enable_penalty'] ?? 1) == 1,
        ComponentDataKeys.points: toInt(row['penalty_points']),
      });
    }
    if (type == TaskType.shortTerm) {
      doc.updateData(ComponentType.timeRange, {
        ComponentDataKeys.start: row['start_time'] as String?,
        ComponentDataKeys.end: row['end_time'] as String?,
      });
    } else if (type == TaskType.longTerm) {
      if (doc.has(ComponentType.deadline)) {
        doc.updateData(ComponentType.deadline, {
          ComponentDataKeys.end: row['deadline'] as String?,
        });
      }
      // 长期任务备注列映射内容组件。
      doc.updateData(ComponentType.content, {
        ComponentDataKeys.text: text('note'),
      });
    } else {
      doc.updateData(ComponentType.timeRange, {
        ComponentDataKeys.start: row['start_time'] as String?,
      });
      if (type == TaskType.habit) {
        doc.updateData(ComponentType.repeatRule, {
          ComponentDataKeys.repeatType: row['repeat_type'] as String? ?? 'daily',
          ComponentDataKeys.repeatValue: row['repeat_value'],
          ComponentDataKeys.reminderTimes: const [],
        });
      }
    }
    return doc;
  }

  Future<void> _loadTagsAndReminders(Map<String, dynamic>? existing) async {
    try {
      final repo = TaskRepository.instance;
      final results = await Future.wait([
        repo.loadSpecialTags(),
        repo.loadDailyTags(),
      ]);
      if (!mounted) return;
      setState(() {
        _specialTags = results[0];
        _dailyTags = results[1];
      });
      if (existing == null || _taskId == null) return;
      if (_type == TaskType.shortTerm) {
        final minutes = await repo.loadSpecialTaskReminders(_taskId);
        if (!mounted || minutes.isEmpty) return;
        setState(() {
          _doc.updateData(ComponentType.reminders, {
            ComponentDataKeys.reminderMinutes: minutes,
          });
        });
      } else if (_type == TaskType.habit) {
        final times = await repo.loadDailyTaskReminders(_taskId);
        if (!mounted || times.isEmpty) return;
        setState(() {
          final data = Map.of(_doc.dataOf(ComponentType.repeatRule));
          data[ComponentDataKeys.reminderTimes] = [
            for (final t in times)
              <String, dynamic>{'h': t.hour, 'm': t.minute},
          ];
          _doc.updateData(ComponentType.repeatRule, data);
        });
      }
    } catch (_) {
      // 标签/提醒读取失败不阻塞编辑。
    }
  }

  // ---------------- 组件增删 / 排序 ----------------

  Future<void> _pickComponent() async {
    final available = _availableTypes();
    if (available.isEmpty) return;
    final picked = await showModalBottomSheet<ComponentType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '添加组件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final type in available)
              ListTile(
                leading: Icon(type.icon),
                title: Text(type.label),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _doc.upsert(picked, _defaultData(picked));
    });
  }

  Map<String, dynamic> _defaultData(ComponentType type) => switch (type) {
    ComponentType.timeRange => {
      ComponentDataKeys.start: DateTime.now().toIso8601String(),
      ComponentDataKeys.end: DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    },
    ComponentType.deadline => {
      ComponentDataKeys.end: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        23,
        59,
      ).add(const Duration(days: 7)).toIso8601String(),
    },
    ComponentType.repeatRule => {
      ComponentDataKeys.repeatType: 'daily',
      ComponentDataKeys.repeatValue: null,
      ComponentDataKeys.reminderTimes: [
        {'h': AppConstants.reminderMorningHour, 'm': 0},
      ],
    },
    ComponentType.reminders => {
      ComponentDataKeys.reminderMinutes: [
        AppSettingsController.instance.defaultRemindMinutes,
      ],
    },
    ComponentType.rewardPoints => {ComponentDataKeys.points: 5},
    ComponentType.penaltyPoints => {
      ComponentDataKeys.enabled: false,
      ComponentDataKeys.points: 0,
    },
    ComponentType.progress => {ComponentDataKeys.value: 0},
    ComponentType.subtasks => {ComponentDataKeys.items: []},
    ComponentType.checkinCounter => {ComponentDataKeys.count: 0},
    _ => <String, dynamic>{},
  };

  /// 不同任务类型下可用的组件（与存储/通知能力对齐）。
  List<ComponentType> _availableTypes() {
    final hidden = switch (_type) {
      TaskType.shortTerm => {
        ComponentType.repeatRule,
        ComponentType.deadline,
      },
      TaskType.daily => {
        ComponentType.repeatRule,
        ComponentType.reminders,
        ComponentType.deadline,
      },
      TaskType.habit => {
        ComponentType.reminders,
        ComponentType.deadline,
        ComponentType.requirement,
      },
      TaskType.longTerm => {
        ComponentType.repeatRule,
        ComponentType.reminders,
        ComponentType.timeRange,
      },
      _ => <ComponentType>{},
    };
    return _doc.availableTypes.where((t) => !hidden.contains(t)).toList();
  }

  void _switchType(TaskType type) {
    if (_isExisting || type == _type) return;
    setState(() {
      _type = type;
      _doc = TaskComponentDocument.defaultFor(type);
    });
  }

  void setStateForRemove(ComponentType type) {
    setState(() => _doc.remove(type));
  }

  int? get taskId => _taskId;

  String get titleText => _titleController.text.trim();

  void _updateComponent(ComponentType type, Map<String, dynamic> data) {
    setState(() => _doc.updateData(type, data));
  }

  // ---------------- 保存 ----------------

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _snack('请输入任务标题');
      return;
    }
    // 积分校验。
    final rewardData = _doc.dataOf(ComponentType.rewardPoints);
    final penaltyData = _doc.dataOf(ComponentType.penaltyPoints);
    final reward = TaskComponentDocument.intValue(
      rewardData,
      ComponentDataKeys.points,
    );
    final penaltyEnabled =
        penaltyData[ComponentDataKeys.enabled] == true;
    final penalty = TaskComponentDocument.intValue(
      penaltyData,
      ComponentDataKeys.points,
    );
    if (reward < 0 || penalty < 0) {
      _snack('积分不能为负数');
      return;
    }

    final timeData = _doc.dataOf(ComponentType.timeRange);
    final deadlineData = _doc.dataOf(ComponentType.deadline);
    final start =
        TaskComponentDocument.dateTime(timeData, ComponentDataKeys.start) ??
        DateTime.now();
    final end =
        TaskComponentDocument.dateTime(timeData, ComponentDataKeys.end) ??
        start.add(const Duration(hours: 1));
    final deadline = TaskComponentDocument.dateTime(
      deadlineData,
      ComponentDataKeys.end,
    );

    RepeatRule? habitRule;
    List<({int hour, int minute})> habitReminders = const [];
    if (_type == TaskType.habit) {
      final ruleData = _doc.dataOf(ComponentType.repeatRule);
      if (ruleData.isEmpty) {
        _snack('习惯任务需要重复规则组件');
        return;
      }
      habitRule = RepeatRule.fromColumns(
        ruleData[ComponentDataKeys.repeatType] as String?,
        ruleData[ComponentDataKeys.repeatValue] as String?,
      );
      if (habitRule.type == RepeatType.weekly &&
          RepeatRule.intList(habitRule.value).isEmpty) {
        _snack('请至少选择一个星期');
        return;
      }
      if (habitRule.type == RepeatType.monthly &&
          RepeatRule.intList(habitRule.value).isEmpty) {
        _snack('请至少选择一个日期');
        return;
      }
      final rawTimes =
          ruleData[ComponentDataKeys.reminderTimes] as List? ?? const [];
      habitReminders = [
        for (final raw in rawTimes)
          if (raw is Map)
            (
              hour: TaskComponentDocument.intValue(
                Map<String, dynamic>.from(raw),
                'h',
                9,
              ),
              minute: TaskComponentDocument.intValue(
                Map<String, dynamic>.from(raw),
                'm',
                0,
              ),
            ),
      ];
      if (habitReminders.isEmpty) {
        _snack('请至少添加一个提醒时间点');
        return;
      }
    }

    final tagData = _doc.dataOf(ComponentType.tag);
    final content = TaskComponentDocument.text(
      _doc.dataOf(ComponentType.content),
    );
    final requirement = TaskComponentDocument.text(
      _doc.dataOf(ComponentType.requirement),
    );
    final remark = TaskComponentDocument.text(
      _doc.dataOf(ComponentType.remark),
    );
    final componentJson = _doc.encode();

    setState(() => _saving = true);
    try {
      final repo = TaskRepository.instance;
      switch (_type) {
        case TaskType.shortTerm:
          if (end.isBefore(start)) {
            _snack('结束时间不能早于开始时间');
            setState(() => _saving = false);
            return;
          }
          final reminderData = _doc.dataOf(ComponentType.reminders);
          final minutes =
              (reminderData[ComponentDataKeys.reminderMinutes] as List?)
                  ?.map((v) => toInt(v))
                  .toSet() ??
              <int>{
                AppSettingsController.instance.defaultRemindMinutes,
              };
          await repo.saveSpecialTask(
            {
              'name': title,
              'content': content,
              'requirement': requirement,
              'remark': remark,
              'start_time': start.toIso8601String(),
              'end_time': end.toIso8601String(),
              'task_tag_id': tagData[ComponentDataKeys.tagId],
              'reward_points': reward,
              'penalty_points': penaltyEnabled ? penalty : 0,
              'enable_penalty': penaltyEnabled ? 1 : 0,
              'component_json': componentJson,
            },
            id: _isExisting ? _taskId : null,
            remindMinutesBefore: minutes,
          );
        case TaskType.daily:
        case TaskType.habit:
          await repo.saveDailyTask(
            {
              'name': title,
              'content': content,
              'requirement': requirement,
              'remark': remark,
              'start_time': start.toIso8601String(),
              'task_tag_id': tagData[ComponentDataKeys.tagId],
              'daily_points': reward,
              'penalty_points': penaltyEnabled ? penalty : 0,
              'enable_penalty': penaltyEnabled ? 1 : 0,
              'component_json': componentJson,
              'task_mode': _type == TaskType.habit ? 'habit' : 'review',
              'repeat_type': _type == TaskType.habit
                  ? habitRule!.dbValue
                  : 'daily',
              'repeat_value': _type == TaskType.habit
                  ? habitRule!.value
                  : null,
              if (_isExisting &&
                  toInt(widget.args.existing?['review_stage']) == 0)
                'next_review_time': start.toIso8601String(),
            },
            id: _isExisting ? _taskId : null,
            reminders:
                _type == TaskType.habit ? habitReminders : const [],
          );
        case TaskType.longTerm:
          await repo.saveLongTermTask(
            {
              'title': title,
              'note': content,
              'tag': (tagData[ComponentDataKeys.tagText] as String?)?.trim(),
              'deadline': deadline?.toIso8601String(),
              'reward_points': reward,
              'penalty_points': penaltyEnabled ? penalty : 0,
              'enable_penalty': penaltyEnabled ? 1 : 0,
              'component_json': componentJson,
              'update_time': DateTime.now().toIso8601String(),
            },
            id: _isExisting ? _taskId : null,
          );
        case TaskType.wish:
        case TaskType.hope:
          return;
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _snack('保存任务失败：$error');
        setState(() => _saving = false);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final editableTypes = [
      TaskType.shortTerm,
      TaskType.daily,
      TaskType.habit,
      TaskType.longTerm,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isExisting ? '编辑任务' : '添加任务'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 固定组件①：任务标题（必填）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _titleController,
                style: Theme.of(context).textTheme.titleMedium,
                decoration: const InputDecoration(
                  labelText: '任务标题 *',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.title),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 固定组件②：任务类型选择器
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务类型',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final type in editableTypes)
                        ChoiceChip(
                          label: Text(type.label),
                          selected: _type == type,
                          onSelected: _isExisting
                              ? null
                              : (_) => _switchType(type),
                        ),
                    ],
                  ),
                  if (_isExisting)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '已有任务不能切换类型',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 动态组件列表（可拖拽排序、单独删除）
          if (_doc.components.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无额外组件，点击下方按钮添加',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              key: ValueKey('components_$_type'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _doc.components.length,
              onReorderItem: (oldIndex, newIndex) => setState(
                () => _doc.reorder(oldIndex, newIndex),
              ),
              itemBuilder: (context, index) {
                final component = _doc.components[index];
                return Padding(
                  key: ValueKey('component_${component.type.id}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ComponentCard(
                    component: component,
                    editor: this,
                    index: index,
                    specialTags: _specialTags,
                    dailyTags: _dailyTags,
                  ),
                );
              },
            ),
          OutlinedButton.icon(
            onPressed: _pickComponent,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('添加组件'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存任务'),
          ),
        ),
      ),
    );
  }
}

/// 单个动态组件的卡片容器 + 按类型分发的表单体。
class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.component,
    required this.editor,
    required this.index,
    required this.specialTags,
    required this.dailyTags,
  });

  final TaskComponent component;
  final _TaskEditorPageState editor;
  final int index;
  final List<Map<String, dynamic>> specialTags;
  final List<Map<String, dynamic>> dailyTags;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ),
              Icon(component.type.icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  component.type.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '移除组件',
                icon: const Icon(Icons.close, size: 19),
                onPressed: () =>
                    editor.setStateForRemove(component.type),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _ComponentBody(
              component: component,
              editor: editor,
              specialTags: specialTags,
              dailyTags: dailyTags,
            ),
          ),
        ],
      ),
    );
  }
}

/// 组件表单体：持有各组件自己的输入控制器。
class _ComponentBody extends StatefulWidget {
  const _ComponentBody({
    required this.component,
    required this.editor,
    required this.specialTags,
    required this.dailyTags,
  });

  final TaskComponent component;
  final _TaskEditorPageState editor;
  final List<Map<String, dynamic>> specialTags;
  final List<Map<String, dynamic>> dailyTags;

  @override
  State<_ComponentBody> createState() => _ComponentBodyState();
}

class _ComponentBodyState extends State<_ComponentBody> {
  late final Map<ComponentType, TextEditingController> _controllers = {};
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  _TaskEditorPageState get editor => widget.editor;
  TaskComponent get component => widget.component;
  Map<String, dynamic> get data => component.data;

  TextEditingController controllerFor(
    ComponentType type,
    String key, {
    String initial = '',
  }) {
    return _controllers.putIfAbsent(
      type,
      () => TextEditingController(text: (data[key] ?? initial).toString()),
    );
  }

  void mutate(void Function(Map<String, dynamic> data) builder) {
    final next = Map.of(data);
    builder(next);
    editor._updateComponent(component.type, next);
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return null;
    final t = time ?? TimeOfDay.fromDateTime(initial);
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Widget _dateTile({
    required String label,
    required String key,
    DateTime? fallback,
    String? emptyHint,
  }) {
    final value = TaskComponentDocument.dateTime(data, key) ?? fallback;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      subtitle: Text(value == null ? (emptyHint ?? '未设置') : _dateFormat.format(value)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final picked = await _pickDateTime(value ?? DateTime.now());
        if (picked != null) {
          mutate((d) => d[key] = picked.toIso8601String());
        }
      },
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (component.type) {
      case ComponentType.timeRange:
        return Column(
          children: [
            _dateTile(
              label: editor._type == TaskType.shortTerm ? '开始时间' : '开始日期',
              key: ComponentDataKeys.start,
            ),
            if (editor._type == TaskType.shortTerm)
              _dateTile(label: '结束时间', key: ComponentDataKeys.end),
          ],
        );
      case ComponentType.deadline:
        return _dateTile(label: '截止时间', key: ComponentDataKeys.end);
      case ComponentType.tag:
        return editor._type == TaskType.longTerm
            ? TextField(
                controller: controllerFor(component.type, 'tag_text'),
                decoration: const InputDecoration(
                  labelText: '标签（自由文本）',
                  isDense: true,
                ),
                onChanged: (value) =>
                    mutate((d) => d[ComponentDataKeys.tagText] = value),
              )
            : DropdownButtonFormField<int?>(
                initialValue: data[ComponentDataKeys.tagId] as int?,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '任务标签',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('未分类')),
                  for (final tag
                      in (editor._type == TaskType.shortTerm
                          ? widget.specialTags
                          : widget.dailyTags))
                    DropdownMenuItem<int?>(
                      value: tag['id'] as int,
                      child: Text('${tag['name']}'),
                    ),
                ],
                onChanged: (value) =>
                    mutate((d) => d[ComponentDataKeys.tagId] = value),
              );
      case ComponentType.content:
      case ComponentType.requirement:
      case ComponentType.remark:
        final labels = {
          ComponentType.content: '任务内容',
          ComponentType.requirement: '完成要求 / 验收标准',
          ComponentType.remark: '文字备注',
        };
        return TextField(
          controller: controllerFor(
            component.type,
            ComponentDataKeys.text,
          ),
          minLines: component.type == ComponentType.content ? 2 : 1,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: labels[component.type],
            isDense: true,
          ),
          onChanged: (value) =>
              mutate((d) => d[ComponentDataKeys.text] = value),
        );
      case ComponentType.rewardPoints:
        return TextField(
          controller: controllerFor(
            component.type,
            ComponentDataKeys.points,
            initial: '0',
          ),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '完成奖励积分',
            suffixText: '分',
            isDense: true,
          ),
          onChanged: (value) => mutate(
            (d) =>
                d[ComponentDataKeys.points] =
                    int.tryParse(value.trim()) ?? 0,
          ),
        );
      case ComponentType.penaltyPoints:
        final enabled = data[ComponentDataKeys.enabled] == true;
        final pointsController = controllerFor(
          component.type,
          ComponentDataKeys.points,
          initial: '0',
        );
        return Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开启逾期自动扣分'),
              subtitle: const Text('到期未完成按周期自动扣除，补完成自动返还'),
              value: enabled,
              onChanged: (value) =>
                  mutate((d) => d[ComponentDataKeys.enabled] = value),
            ),
            if (enabled)
              TextField(
                controller: pointsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每次逾期扣除积分',
                  suffixText: '分',
                  isDense: true,
                ),
                onChanged: (value) => mutate(
                  (d) =>
                      d[ComponentDataKeys.points] =
                          int.tryParse(value.trim()) ?? 0,
                ),
              ),
          ],
        );
      case ComponentType.repeatRule:
        return _RepeatRuleBody(parent: this);
      case ComponentType.reminders:
        return _SpecialReminderBody(parent: this);
      case ComponentType.weight:
      case ComponentType.mood:
        return _RecordComponentBody(parent: this);
      case ComponentType.progress:
        final value = TaskComponentDocument.intValue(
          data,
          ComponentDataKeys.value,
        ).clamp(0, 100);
        return Row(
          children: [
            Expanded(
              child: Slider(
                value: value.toDouble(),
                max: 100,
                divisions: 100,
                label: '$value%',
                onChanged: (v) => mutate(
                  (d) => d[ComponentDataKeys.value] = v.round(),
                ),
              ),
            ),
            SizedBox(width: 48, child: Text('$value%')),
          ],
        );
      case ComponentType.subtasks:
        return _SubtasksBody(parent: this);
      case ComponentType.checkinCounter:
        final count = TaskComponentDocument.intValue(
          data,
          ComponentDataKeys.count,
        );
        return Row(
          children: [
            IconButton(
              tooltip: '减少',
              onPressed: count <= 0
                  ? null
                  : () => mutate(
                      (d) => d[ComponentDataKeys.count] = count - 1,
                    ),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: Text(
                '已打卡 $count 次',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: '增加',
              onPressed: () =>
                  mutate((d) => d[ComponentDataKeys.count] = count + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        );
      case ComponentType.images:
      case ComponentType.voice:
        return _AttachmentBody(parent: this);
    }
  }
}

/// 习惯任务重复规则 + 多个提醒时刻。
class _RepeatRuleBody extends StatelessWidget {
  const _RepeatRuleBody({required this.parent});

  final _ComponentBodyState parent;

  @override
  Widget build(BuildContext context) {
    final data = parent.data;
    var repeatType = RepeatRule.fromColumns(
      data[ComponentDataKeys.repeatType] as String?,
      data[ComponentDataKeys.repeatValue] as String?,
    ).type;
    final weekdays = RepeatRule.intList(data[ComponentDataKeys.repeatValue]?.toString())
        .toSet();
    final monthDays = weekdays; // 同值列表，下面按类型分别取。
    final times = [
      for (final raw in (data[ComponentDataKeys.reminderTimes] as List? ?? const []))
        if (raw is Map)
          TimeOfDay(
            hour: TaskComponentDocument.intValue(
              Map<String, dynamic>.from(raw),
              'h',
              9,
            ),
            minute: TaskComponentDocument.intValue(
              Map<String, dynamic>.from(raw),
              'm',
              0,
            ),
          ),
    ];

    void persist({
      RepeatType? type,
      Set<int>? weekdays,
      Set<int>? monthDays,
      int? interval,
      List<TimeOfDay>? times,
    }) {
      final nextType = type ?? repeatType;
      String? value;
      final source =
          nextType == RepeatType.weekly
              ? (weekdays ?? RepeatRule.intList(data[ComponentDataKeys.repeatValue]?.toString()).toSet())
              : nextType == RepeatType.monthly
              ? (monthDays ?? RepeatRule.intList(data[ComponentDataKeys.repeatValue]?.toString()).toSet())
              : null;
      if (nextType == RepeatType.weekly || nextType == RepeatType.monthly) {
        value = RepeatRule.encode(source?.toList() ?? const []);
      } else if (nextType == RepeatType.interval) {
        value = '${interval ?? TaskComponentDocument.intValue(
          data,
          ComponentDataKeys.repeatValue,
          1,
        )}';
      }
      parent.mutate((d) {
        d[ComponentDataKeys.repeatType] = nextType.name;
        d[ComponentDataKeys.repeatValue] = value;
        d[ComponentDataKeys.reminderTimes] = [
          for (final t in (times ?? parentTimeList(data)))
            <String, dynamic>{'h': t.hour, 'm': t.minute},
        ];
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const [
              (RepeatType.daily, '每天'),
              (RepeatType.weekly, '每周'),
              (RepeatType.monthly, '每月'),
              (RepeatType.interval, '间隔天数'),
            ])
              ChoiceChip(
                label: Text(entry.$2),
                selected: repeatType == entry.$1,
                onSelected: (_) => persist(type: entry.$1),
              ),
          ],
        ),
        if (repeatType == RepeatType.weekly)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  FilterChip(
                    label: Text(const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1]),
                    selected: weekdays.contains(weekday),
                    onSelected: (checked) {
                      final next = Set<int>.of(weekdays);
                      checked ? next.add(weekday) : next.remove(weekday);
                      persist(weekdays: next);
                    },
                  ),
              ],
            ),
          ),
        if (repeatType == RepeatType.monthly)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              children: [
                for (var day = 1; day <= 31; day++)
                  FilterChip(
                    label: Text('$day'),
                    selected: monthDays.contains(day),
                    onSelected: (checked) {
                      final next = Set<int>.of(monthDays);
                      checked ? next.add(day) : next.remove(day);
                      persist(monthDays: next);
                    },
                  ),
              ],
            ),
          ),
        if (repeatType == RepeatType.interval)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextFormField(
              initialValue:
                  '${TaskComponentDocument.intValue(data, ComponentDataKeys.repeatValue, 2)}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每隔多少天打卡一次',
                suffixText: '天',
                isDense: true,
              ),
              onFieldSubmitted: (text) {
                final days = int.tryParse(text.trim());
                if (days != null && days >= 1) persist(interval: days);
              },
            ),
          ),
        const SizedBox(height: 8),
        Text('提醒时间点', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < times.length; i++)
              Chip(
                label: Text(times[i].format(context)),
                onDeleted: times.length <= 1
                    ? null
                    : () {
                        final next = List<TimeOfDay>.of(times)..removeAt(i);
                        persist(times: next);
                      },
              ),
            ActionChip(
              avatar: const Icon(Icons.add_alarm, size: 18),
              label: const Text('添加时间'),
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
                if (picked == null) return;
                final exists = times.any(
                  (t) => t.hour == picked.hour && t.minute == picked.minute,
                );
                if (!exists) persist(times: [...times, picked]);
              },
            ),
          ],
        ),
      ],
    );
  }

  List<TimeOfDay> parentTimeList(Map<String, dynamic> data) => [
    for (final raw in (data[ComponentDataKeys.reminderTimes] as List? ?? const []))
      if (raw is Map)
        TimeOfDay(
          hour: TaskComponentDocument.intValue(
            Map<String, dynamic>.from(raw),
            'h',
            9,
          ),
          minute: TaskComponentDocument.intValue(
            Map<String, dynamic>.from(raw),
            'm',
            0,
          ),
        ),
  ];
}

/// 特殊任务多档提前提醒。
class _SpecialReminderBody extends StatelessWidget {
  const _SpecialReminderBody({required this.parent});

  final _ComponentBodyState parent;

  @override
  Widget build(BuildContext context) {
    final data = parent.data;
    final selected =
        ((data[ComponentDataKeys.reminderMinutes] as List?) ?? const [])
            .map((v) => int.tryParse('$v'))
            .whereType<int>()
            .toSet();
    void persist(Set<int> minutes) {
      parent.mutate(
        (d) => d[ComponentDataKeys.reminderMinutes] = minutes.toList(),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final minutes in _specialReminderPresets)
          FilterChip(
            label: Text(_leadLabel(minutes)),
            selected: selected.contains(minutes),
            onSelected: (checked) {
              final next = Set<int>.of(selected);
              checked ? next.add(minutes) : next.remove(minutes);
              persist(next);
            },
          ),
        for (final minutes in selected.where(
          (m) => !_specialReminderPresets.contains(m),
        ))
          Chip(
            label: Text(_leadLabel(minutes)),
            onDeleted: () => persist(Set<int>.of(selected)..remove(minutes)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('自定义'),
          onPressed: () async {
            final controller = TextEditingController();
            final minutes = await showDialog<int>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('自定义提前分钟数'),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(suffixText: '分钟'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      int.tryParse(controller.text.trim()),
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
            controller.dispose();
            if (minutes != null && minutes >= 0) {
              persist(Set<int>.of(selected)..add(minutes));
            }
          },
        ),
      ],
    );
  }
}

/// 子任务清单（数据存 JSON）。
class _SubtasksBody extends StatefulWidget {
  const _SubtasksBody({required this.parent});

  final _ComponentBodyState parent;

  @override
  State<_SubtasksBody> createState() => _SubtasksBodyState();
}

class _SubtasksBodyState extends State<_SubtasksBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parent;
    final items = TaskComponentDocument.subtaskItems(parent.data);
    void persist(List<Map<String, dynamic>> next) {
      parent.mutate((d) => d[ComponentDataKeys.items] = next);
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            children: [
              Checkbox(
                value: items[i]['done'] as bool,
                onChanged: (checked) {
                  final next = TaskComponentDocument.subtaskItems(parent.data);
                  next[i]['done'] = checked == true;
                  persist(next);
                },
              ),
              Expanded(
                child: Text(
                  items[i]['text'] as String,
                  style: TextStyle(
                    decoration: items[i]['done'] == true
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  final next = TaskComponentDocument.subtaskItems(parent.data)
                    ..removeAt(i);
                  persist(next);
                },
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '新增子任务后回车',
                ),
                onSubmitted: (value) {
                  if (value.trim().isEmpty) return;
                  final next = TaskComponentDocument.subtaskItems(parent.data)
                    ..add({'text': value.trim(), 'done': false});
                  persist(next);
                  _controller.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                final next = TaskComponentDocument.subtaskItems(parent.data)
                  ..add({'text': _controller.text.trim(), 'done': false});
                persist(next);
                _controller.clear();
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 图片 / 语音附件（复制到应用文档目录，路径存 JSON）。
class _AttachmentBody extends StatelessWidget {
  const _AttachmentBody({required this.parent});

  final _ComponentBodyState parent;

  Future<void> _pickFiles(bool images) async {
    final result = await FilePicker.platform.pickFiles(
      type: images ? FileType.image : FileType.audio,
      allowMultiple: images,
    );
    if (result == null || result.files.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(directory.path, 'task_attachments'));
    await folder.create(recursive: true);
    final files = TaskComponentDocument.fileItems(parent.data);
    for (final picked in result.files) {
      final sourcePath = picked.path;
      if (sourcePath == null) continue;
      final ext = p.extension(picked.name).isEmpty ? '' : p.extension(picked.name);
      final target = p.join(
        folder.path,
        '${DateTime.now().microsecondsSinceEpoch}_${files.length}$ext',
      );
      try {
        await File(sourcePath).copy(target);
        files.add({'name': picked.name, 'path': target});
      } catch (_) {
        // 单个文件复制失败跳过，不影响其余附件。
      }
    }
    parent.mutate((d) => d[ComponentDataKeys.files] = files);
  }

  @override
  Widget build(BuildContext context) {
    final isImage = parent.component.type == ComponentType.images;
    final files = TaskComponentDocument.fileItems(parent.data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < files.length; i++)
              Chip(
                avatar: Icon(isImage ? Icons.image_outlined : Icons.audiotrack),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    files[i]['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onDeleted: () {
                  final next = TaskComponentDocument.fileItems(parent.data)
                    ..removeAt(i);
                  parent.mutate((d) => d[ComponentDataKeys.files] = next);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (isImage)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in files)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(file['path'] as String),
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 100,
                      height: 100,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _pickFiles(isImage),
          icon: Icon(isImage ? Icons.add_photo_alternate_outlined : Icons.mic_none),
          label: Text(isImage ? '添加图片' : '添加语音文件'),
        ),
      ],
    );
  }
}

/// 体重 / 心情组件：入口按钮（多条记录与曲线图在趋势页管理）。
class _RecordComponentBody extends StatefulWidget {
  const _RecordComponentBody({required this.parent});

  final _ComponentBodyState parent;

  @override
  State<_RecordComponentBody> createState() => _RecordComponentBodyState();
}

class _RecordComponentBodyState extends State<_RecordComponentBody> {
  int _weightCount = 0;
  int _moodCount = 0;

  _TaskEditorPageState get editor => widget.parent.editor;
  bool get isWeight =>
      widget.parent.component.type == ComponentType.weight;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final id = editor.taskId;
    if (id == null) return;
    try {
      final repo = TaskComponentRepository.instance;
      final kind = editor._type.storageKind;
      if (isWeight) {
        final records = await repo.loadWeights(taskKind: kind, taskId: id);
        if (mounted) setState(() => _weightCount = records.length);
      } else {
        final records = await repo.loadMoods(taskKind: kind, taskId: id);
        if (mounted) setState(() => _moodCount = records.length);
      }
    } catch (_) {
      // 计数失败不影响编辑。
    }
  }

  Future<void> _openTrend() async {
    final id = editor.taskId;
    if (id == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskTrendPage(
          taskKind: editor._type.storageKind,
          taskId: id,
          taskTitle: editor.titleText,
          metric: isWeight ? TrendMetric.weight : TrendMetric.mood,
        ),
      ),
    );
    await _refreshCount();
  }

  @override
  Widget build(BuildContext context) {
    final count = isWeight ? _weightCount : _moodCount;
    final saved = editor.taskId != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            saved ? '已记录 $count 条' : '保存任务后可录入多条记录并查看曲线图',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: saved ? _openTrend : null,
          icon: const Icon(Icons.show_chart),
          label: Text(isWeight ? '体重记录' : '心情记录'),
        ),
      ],
    );
  }
}
