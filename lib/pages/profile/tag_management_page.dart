import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/dialog.dart';
import 'package:flutter/material.dart';

class _TagGroup {
  const _TagGroup({
    required this.title,
    required this.table,
    required this.idColumn,
    required this.nameColumn,
    this.referenceTable,
    this.referenceColumn,
  });

  final String title;
  final String table;
  final String idColumn;
  final String nameColumn;
  final String? referenceTable;
  final String? referenceColumn;
}

const _tagGroups = [
  _TagGroup(
    title: '全局标签',
    table: 'tags',
    idColumn: 'tag_id',
    nameColumn: 'tag_name',
  ),
  _TagGroup(
    title: '愿望标签',
    table: 'wish_tags',
    idColumn: 'id',
    nameColumn: 'name',
    referenceTable: 'wishes',
    referenceColumn: 'tag_id',
  ),
  _TagGroup(
    title: '希望标签',
    table: 'hope_tags',
    idColumn: 'id',
    nameColumn: 'name',
    referenceTable: 'hopes',
    referenceColumn: 'tag_id',
  ),
  _TagGroup(
    title: '特殊任务标签',
    table: 'special_task_tags',
    idColumn: 'id',
    nameColumn: 'name',
    referenceTable: 'special_tasks',
    referenceColumn: 'task_tag_id',
  ),
  _TagGroup(
    title: '日常任务标签',
    table: 'daily_task_tags',
    idColumn: 'id',
    nameColumn: 'name',
    referenceTable: 'daily_tasks',
    referenceColumn: 'task_tag_id',
  ),
  _TagGroup(
    title: '心情标签',
    table: 'mood_tag',
    idColumn: 'id',
    nameColumn: 'name',
    referenceTable: 'mood_record',
    referenceColumn: 'tag_id',
  ),
];

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({super.key});

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  int _selectedGroup = 0;
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _tags = [];

  _TagGroup get _group => _tagGroups[_selectedGroup];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final group = _group;
      final db = await AppDatabase.instance.database;
      final tags = await db.query(group.table, orderBy: group.nameColumn);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _editTag({Map<String, dynamic>? tag}) async {
    final group = _group;
    final controller = TextEditingController(
      text: tag?[group.nameColumn] as String? ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tag == null ? '新增${group.title}' : '编辑${group.title}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final db = await AppDatabase.instance.database;
      if (tag == null) {
        await db.insert(group.table, {group.nameColumn: name.trim()});
      } else {
        await db.update(
          group.table,
          {group.nameColumn: name.trim()},
          where: '${group.idColumn} = ?',
          whereArgs: [tag[group.idColumn]],
        );
      }
      await _loadTags();
    } catch (error) {
      _showMessage('${tag == null ? '新增' : '更新'}标签失败：$error');
    }
  }

  Future<void> _deleteTag(Map<String, dynamic> tag) async {
    final group = _group;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除“${tag[group.nameColumn]}”吗？'),
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
    if (confirmed != true) return;
    try {
      final db = await AppDatabase.instance.database;
      await db.transaction((transaction) async {
        final referenceTable = group.referenceTable;
        final referenceColumn = group.referenceColumn;
        if (referenceTable != null && referenceColumn != null) {
          final references = await transaction.query(
            referenceTable,
            columns: [referenceColumn],
            where: '$referenceColumn = ?',
            whereArgs: [tag[group.idColumn]],
            limit: 1,
          );
          if (referenceTable == 'mood_record') {
            final statistics = await transaction.query(
              'mood_month_stat',
              columns: ['id'],
              where: 'tag_id = ?',
              whereArgs: [tag[group.idColumn]],
              limit: 1,
            );
            if (references.isNotEmpty || statistics.isNotEmpty) {
              throw StateError('该标签已有心情记录使用，不能删除');
            }
          }
          if (references.isNotEmpty) {
            await transaction.update(
              referenceTable,
              {referenceColumn: null},
              where: '$referenceColumn = ?',
              whereArgs: [tag[group.idColumn]],
            );
          }
        }
        await transaction.delete(
          group.table,
          where: '${group.idColumn} = ?',
          whereArgs: [tag[group.idColumn]],
        );
      });
      await _loadTags();
    } catch (error) {
      _showMessage('删除标签失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('标签管理'),
      actions: [
        IconButton(
          tooltip: '新增标签',
          onPressed: _loading ? null : () => _editTag(),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: Column(
      children: [
        SizedBox(
          height: 54,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: [
              for (var index = 0; index < _tagGroups.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_tagGroups[index].title),
                    selected: _selectedGroup == index,
                    onSelected: (_) {
                      setState(() => _selectedGroup = index);
                      _loadTags();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('读取标签失败：$_error'),
                      TextButton(onPressed: _loadTags, child: const Text('重试')),
                    ],
                  ),
                )
              : _tags.isEmpty
              ? Center(child: Text('还没有${_group.title}，点击右上角添加'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _tags.length,
                  itemBuilder: (context, index) {
                    final tag = _tags[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.sell_outlined),
                        title: Text(tag[_group.nameColumn] as String),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: '编辑标签',
                              onPressed: () => _editTag(tag: tag),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '删除标签',
                              onPressed: () => _deleteTag(tag),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
