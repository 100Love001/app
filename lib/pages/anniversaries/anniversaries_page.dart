import 'dart:async';

import 'package:app/stores/anniversaries/anniversary_repository.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/date_range.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 纪念日列表视图：可内嵌到记录页纪念日分区，也可由独立页包装。
/// [autoAdd] 为 true 时进入后自动打开添加对话框，消费后回调
/// [onAutoAddConsumed] 通知宿主复位标记。
class AnniversariesView extends StatefulWidget {
  const AnniversariesView({
    super.key,
    this.autoAdd = false,
    this.onAutoAddConsumed,
  });

  final bool autoAdd;
  final VoidCallback? onAutoAddConsumed;

  @override
  State<AnniversariesView> createState() => _AnniversariesViewState();
}

class _AnniversariesViewState extends State<AnniversariesView> {
  List<Map<String, Object?>> _anniversaries = [];
  bool _loading = true;
  Object? _error;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _loadAnniversaries();
    // 从首页“添加纪念日”入口进入时（autoAdd），直接打开添加对话框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoAdd) {
        widget.onAutoAddConsumed?.call();
        unawaited(_editAnniversary());
      }
    });
  }

  /// 供宿主（记录页/独立包装页）刷新纪念日数据。
  void refresh() => unawaited(_loadAnniversaries());

  Future<void> _loadAnniversaries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AnniversaryRepository.instance.loadAll();
      if (!mounted) return;
      final items = rows.map((row) => Map<String, Object?>.from(row)).toList();
      items.sort((first, second) {
        final firstDate = DateTime.parse(first['event_date']! as String);
        final secondDate = DateTime.parse(second['event_date']! as String);
        final firstNext = computeNextAnniversaryDate(
          eventDate: firstDate,
          today: DateTime.now(),
          calendarType: first['calendar_type'] as int? ?? 0,
          repeatType: first['repeat_type'] as int? ?? 1,
          repeatCustomDays: first['repeat_custom_days'] as int? ?? 0,
        );
        final secondNext = computeNextAnniversaryDate(
          eventDate: secondDate,
          today: DateTime.now(),
          calendarType: second['calendar_type'] as int? ?? 0,
          repeatType: second['repeat_type'] as int? ?? 1,
          repeatCustomDays: second['repeat_custom_days'] as int? ?? 0,
        );
        return firstNext.compareTo(secondNext);
      });
      setState(() {
        _anniversaries = items;
        _loading = false;
        // 文件夹默认全部折叠，仅保留仍处于展开状态的有效文件夹。
        final validTags = {
          for (final item in items)
            (item['tag'] as String?)?.trim().isEmpty ?? true
                ? '未分类'
                : (item['tag'] as String).trim(),
        };
        _expandedFolders.removeWhere((tag) => !validTags.contains(tag));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _editAnniversary([Map<String, Object?>? anniversary]) async {
    final titleController = TextEditingController(
      text: anniversary?['title'] as String? ?? '',
    );
    final noteController = TextEditingController(
      text: anniversary?['note'] as String? ?? '',
    );
    final customDaysController = TextEditingController(
      text: anniversary == null
          ? ''
          : (anniversary['repeat_custom_days'] as int? ?? 0).toString(),
    );
    final initialDate = anniversary == null
        ? DateTime.now()
        : DateTime.parse(anniversary['event_date']! as String);
    var selectedDate = initialDate;
    var repeatType = anniversary == null
        ? 1
        : anniversary['repeat_type'] as int? ?? 1;

    final existingTags = <String>{};
    for (final item in _anniversaries) {
      final tag = ((item['tag'] as String?) ?? '').trim();
      if (tag.isNotEmpty) existingTags.add(tag);
    }
    final currentTag = (anniversary?['tag'] as String? ?? '').trim();
    String? selectedTag = currentTag.isEmpty ? null : currentTag;
    if (selectedTag != null && !existingTags.contains(selectedTag)) {
      existingTags.add(selectedTag);
    }
    final sortedTags = existingTags.toList()..sort();

    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(anniversary == null ? '添加纪念日' : '编辑纪念日'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    autofocus: true,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: '名称'),
                    validator: (value) =>
                        value?.trim().isEmpty == true ? '请输入纪念日名称' : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('日期'),
                    subtitle: Text(
                      DateFormat('yyyy年M月d日').format(selectedDate),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setDialogState(() => selectedDate = date);
                      }
                    },
                  ),
                  if (sortedTags.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: selectedTag != null && sortedTags.contains(selectedTag)
                          ? selectedTag
                          : null,
                      decoration: const InputDecoration(labelText: '标签'),
                      items: [
                        for (final tag in sortedTags)
                          DropdownMenuItem(value: tag, child: Text(tag)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => selectedTag = value),
                    )
                  else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('还没有标签，请先添加标签'),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final inputController = TextEditingController();
                        final newTag = await showDialog<String>(
                          context: dialogContext,
                          builder: (ctx) => AlertDialog(
                            title: const Text('新增标签'),
                            content: TextField(
                              controller: inputController,
                              autofocus: true,
                              maxLength: 24,
                              decoration: const InputDecoration(
                                labelText: '标签名称',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  final value = inputController.text.trim();
                                  if (value.isNotEmpty) {
                                    Navigator.pop(ctx, value);
                                  }
                                },
                                child: const Text('添加'),
                              ),
                            ],
                          ),
                        );
                        // 等退场动画结束后再释放，否则仍挂载的 TextField
                        // 下一帧重建时用到已 dispose 的控制器导致红屏。
                        await waitForDialogDismissal();
                        inputController.dispose();
                        if (newTag == null || newTag.isEmpty) return;
                        setDialogState(() {
                          if (!sortedTags.contains(newTag)) {
                            sortedTags.add(newTag);
                            sortedTags.sort();
                          }
                          selectedTag = newTag;
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加标签'),
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    maxLength: 120,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '备注（选填）'),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('不重复')),
                      ButtonSegment(value: 1, label: Text('每年')),
                      ButtonSegment(value: 2, label: Text('每月')),
                      ButtonSegment(value: 3, label: Text('每周')),
                      ButtonSegment(value: 4, label: Text('自定义')),
                    ],
                    selected: {repeatType},
                    onSelectionChanged: (value) =>
                        setDialogState(() => repeatType = value.first),
                  ),
                  if (repeatType == 4)
                    TextField(
                      controller: customDaysController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '自定义天数',
                        hintText: '每隔多少天重复',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    final title = titleController.text.trim();
    final note = noteController.text.trim();
    final tag = selectedTag ?? '';
    final customDays = int.tryParse(customDaysController.text.trim()) ?? 0;
    titleController.dispose();
    noteController.dispose();
    customDaysController.dispose();
    if (result != true) return;

    try {
      final values = <String, Object?>{
        'title': title,
        'event_date': TimeUtil.toDateKey(selectedDate),
        'note': note,
        'tag': tag,
        'calendar_type': 0,
        'repeat_type': repeatType,
        'repeat_custom_days': repeatType == 4 ? customDays : 0,
        'repeat_annually': repeatType == 1 ? 1 : 0,
        'update_time': DateTime.now().toIso8601String(),
        if (anniversary != null)
          'anniversary_id': anniversary['anniversary_id'],
      };
      await AnniversaryRepository.instance.save(values);
      await _loadAnniversaries();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存纪念日失败：$error')));
      }
    }
  }

  Future<void> _deleteAnniversary(Map<String, Object?> anniversary) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除纪念日'),
        content: Text('确定删除“${anniversary['title']}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    try {
      await AnniversaryRepository.instance.delete(
        anniversary['anniversary_id'] as int,
      );
      await _loadAnniversaries();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除纪念日失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('纪念日加载失败：$_error'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _loadAnniversaries,
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (_anniversaries.isEmpty)
          _buildEmptyState(context)
        else
          _buildAnniversaryList(context),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _loading ? null : () => _editAnniversary(),
            icon: const Icon(Icons.add),
            label: const Text('添加纪念日'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) => RefreshIndicator(
    onRefresh: _loadAnniversaries,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Text('记录值得纪念的日子'),
                const SizedBox(height: 6),
                Text(
                  '生日、纪念日或任何重要时刻',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildAnniversaryCard(Map<String, Object?> anniversary) {
    final eventDate = DateTime.parse(anniversary['event_date']! as String);
    final calendarType = anniversary['calendar_type'] as int? ?? 0;
    final repeatType = anniversary['repeat_type'] as int? ?? 1;
    final repeatCustomDays = anniversary['repeat_custom_days'] as int? ?? 0;
    final note = (anniversary['note'] as String? ?? '').trim();
    final today = DateTime.now();
    final nextDate = computeNextAnniversaryDate(
      eventDate: eventDate,
      today: today,
      calendarType: calendarType,
      repeatType: repeatType,
      repeatCustomDays: repeatCustomDays,
    );
    final daysRemaining = DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final colorScheme = Theme.of(context).colorScheme;

    final Color accentColor;
    if (daysRemaining <= 0) {
      accentColor = colorScheme.primary;
    } else if (daysRemaining <= 7) {
      accentColor = Colors.orange;
    } else if (daysRemaining <= 30) {
      accentColor = colorScheme.tertiary;
    } else {
      accentColor = colorScheme.primary.withValues(alpha: 0.5);
    }

    final repeatLabel = switch (repeatType) {
      0 => null,
      1 => '每年',
      2 => '每月',
      3 => '每周',
      4 => '每$repeatCustomDays天',
      _ => null,
    };
    final calendarLabel = calendarType == 1 ? '农历' : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _editAnniversary(anniversary),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(color: accentColor),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              anniversary['title']! as String,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildDaysBadge(daysRemaining, accentColor),
                          const SizedBox(width: 2),
                          PopupMenuButton<String>(
                            tooltip: '更多操作',
                            padding: EdgeInsets.zero,
                            onSelected: (action) {
                              if (action == 'edit') {
                                _editAnniversary(anniversary);
                              } else {
                                _deleteAnniversary(anniversary);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('yyyy年M月d日').format(eventDate),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          if (calendarLabel != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              calendarLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (repeatLabel != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.repeat_outlined,
                              size: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              repeatLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDaysBadge(int daysRemaining, Color accentColor) {
    final String label;
    if (daysRemaining == 0) {
      label = '今天';
    } else if (daysRemaining > 0) {
      label = '$daysRemaining天';
    } else {
      label = '已过${-daysRemaining}天';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<_TagFolder> _groupAnniversaries() {
    final folderMap = <String, List<Map<String, Object?>>>{};
    for (final anniversary in _anniversaries) {
      final tag = (anniversary['tag'] as String? ?? '').trim();
      final key = tag.isEmpty ? '未分类' : tag;
      folderMap.putIfAbsent(key, () => []).add(anniversary);
    }
    final folders = folderMap.entries.map((entry) {
      final items = entry.value;
      final nearestDate = _computeNextDate(items.first);
      return _TagFolder(
        tag: entry.key,
        anniversaries: items,
        nearestDate: nearestDate,
      );
    }).toList();
    folders.sort((a, b) => a.nearestDate.compareTo(b.nearestDate));
    return folders;
  }

  DateTime _computeNextDate(Map<String, Object?> anniversary) {
    final eventDate = DateTime.parse(anniversary['event_date']! as String);
    return computeNextAnniversaryDate(
      eventDate: eventDate,
      today: DateTime.now(),
      calendarType: anniversary['calendar_type'] as int? ?? 0,
      repeatType: anniversary['repeat_type'] as int? ?? 1,
      repeatCustomDays: anniversary['repeat_custom_days'] as int? ?? 0,
    );
  }

  Widget _buildAnniversaryList(BuildContext context) {
    final folders = _groupAnniversaries();
    return RefreshIndicator(
      onRefresh: _loadAnniversaries,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildFolderSection(context, folder),
          );
        },
      ),
    );
  }

  Widget _buildFolderSection(BuildContext context, _TagFolder folder) {
    final isExpanded = _expandedFolders.contains(folder.tag);
    final colorScheme = Theme.of(context).colorScheme;
    final count = folder.anniversaries.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedFolders.remove(folder.tag);
                } else {
                  // 手风琴：展开当前文件夹时收起其他同级文件夹。
                  _expandedFolders
                    ..clear()
                    ..add(folder.tag);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.5),
                    colorScheme.surfaceContainerLow,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.tag,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '$count 个纪念日',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                children: [
                  for (var i = 0; i < folder.anniversaries.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i < folder.anniversaries.length - 1 ? 8 : 0,
                      ),
                      child: _buildAnniversaryCard(folder.anniversaries[i]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TagFolder {
  const _TagFolder({
    required this.tag,
    required this.anniversaries,
    required this.nearestDate,
  });

  final String tag;
  final List<Map<String, Object?>> anniversaries;
  final DateTime nearestDate;
}
