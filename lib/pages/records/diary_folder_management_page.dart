import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/folder_path.dart';
import 'package:flutter/material.dart';

class DiaryFolderManagementPage extends StatefulWidget {
  const DiaryFolderManagementPage({
    super.key,
    required this.bookType,
  });

  /// C2：cognition=认知本，diary=日记本。
  final String bookType;

  String get bookName => bookType == 'diary' ? '日记本' : '认知本';

  @override
  State<DiaryFolderManagementPage> createState() =>
      _DiaryFolderManagementPageState();
}

class _DiaryFolderManagementPageState extends State<DiaryFolderManagementPage> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _folders = [];

  List<Map<String, dynamic>> get _orderedFolders {
    final ordered = <Map<String, dynamic>>[];
    final visited = <int>{};
    void appendChildren(int? parentId) {
      for (final folder in _folders) {
        if (folder['parent_id'] != parentId) continue;
        final id = folder['folder_id'] as int;
        if (!visited.add(id)) continue;
        ordered.add(folder);
        appendChildren(id);
      }
    }

    appendChildren(null);
    for (final folder in _folders) {
      final id = folder['folder_id'] as int;
      if (visited.add(id)) {
        ordered.add(folder);
        appendChildren(id);
      }
    }
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await AppDatabase.instance.rawQuery('''
        SELECT folders.folder_id, folders.parent_id, folders.folder_name,
          (SELECT COUNT(*) FROM diaries
            WHERE diaries.folder_id = folders.folder_id
              AND diaries.book_type = folders.book_type) AS diary_count
        FROM folders
        WHERE folders.book_type = ?
        ORDER BY folders.sort, folders.folder_name
      ''', [widget.bookType]);
      if (!mounted) return;
      setState(() {
        _folders = folders;
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

  String _folderPath(int folderId) => FolderPathUtil.buildPath(folderId, _folders);

  int _depth(Map<String, dynamic> folder) => FolderPathUtil.depth(folder, _folders);

  Future<void> _editFolder({
    Map<String, dynamic>? folder,
    int? parentId,
  }) async {
    final controller = TextEditingController(
      text: folder?['folder_name'] as String? ?? '',
    );
    int? selectedParentId = folder?['parent_id'] as int? ?? parentId;
    final options = _orderedFolders
        .where((item) => item['folder_id'] != folder?['folder_id'])
        .toList();
    final value = await showDialog<(String, int?)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(folder == null ? '新建文件夹' : '重命名文件夹'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '文件夹名称'),
              ),
              DropdownButtonFormField<int?>(
                initialValue: selectedParentId,
                decoration: const InputDecoration(labelText: '上级文件夹'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('顶层文件夹'),
                  ),
                  for (final option in options)
                    DropdownMenuItem<int?>(
                      value: option['folder_id'] as int,
                      child: Text(_folderPath(option['folder_id'] as int)),
                    ),
                ],
                onChanged: (value) =>
                    setDialogState(() => selectedParentId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(const SnackBar(content: Text('请输入文件夹名称')));
                  return;
                }
                Navigator.pop(dialogContext, (name, selectedParentId));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (!mounted || value == null) return;
    if (folder != null &&
        value.$2 != null &&
        _isDescendant(value.$2!, folder['folder_id'] as int)) {
      _showError('不能将文件夹移动到自己的子文件夹中');
      return;
    }

    try {
      final db = await AppDatabase.instance.database;
      final isRoot = value.$2 == null;
      final duplicate = await db.query(
        'folders',
        columns: ['folder_id'],
        where: isRoot
            ? 'folder_name = ? AND parent_id IS NULL AND book_type = ? AND folder_id != ?'
            : 'folder_name = ? AND parent_id = ? AND book_type = ? AND folder_id != ?',
        whereArgs: isRoot
            ? [value.$1, widget.bookType, folder?['folder_id'] ?? -1]
            : [
                value.$1,
                value.$2,
                widget.bookType,
                folder?['folder_id'] ?? -1,
              ],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('同一上级文件夹中已有同名文件夹');
      }
      if (folder == null) {
        await db.insert('folders', {
          if (!isRoot) 'parent_id': value.$2,
          'folder_name': value.$1,
          'book_type': widget.bookType,
          'sort': _folders.length,
        });
      } else {
        await db.update(
          'folders',
          {
            if (!isRoot) 'parent_id': value.$2,
            'folder_name': value.$1,
            'update_time': DateTime.now().toIso8601String(),
          },
          where: 'folder_id = ?',
          whereArgs: [folder['folder_id']],
        );
      }
      await _loadFolders();
    } catch (error) {
      _showError('保存文件夹失败：$error');
    }
  }

  bool _isDescendant(int candidateId, int folderId) {
    final byId = {for (final item in _folders) item['folder_id']: item};
    var current = byId[candidateId];
    while (current != null) {
      if (current['folder_id'] == folderId) return true;
      final parentId = current['parent_id'] as int?;
      current = parentId == null ? null : byId[parentId];
    }
    return false;
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('递归删除文件夹？'),
        content: Text(
          '删除“${folder['folder_name']}”会同时删除其所有子文件夹、其中的日记，以及日记回复和附件。此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除全部'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppDatabase.instance.delete(
        'folders',
        where: 'folder_id = ?',
        whereArgs: [folder['folder_id']],
      );
      await _loadFolders();
    } catch (error) {
      _showError('删除文件夹失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.bookName}文件夹'),
        actions: [
          IconButton(
            tooltip: '新建顶层文件夹',
            onPressed: () => _editFolder(),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('文件夹加载失败：$_error'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _loadFolders,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : _folders.isEmpty
          ? const Center(child: Text('还没有文件夹，点击右上角创建'))
          : ListView.builder(
              itemCount: _orderedFolders.length,
              itemBuilder: (context, index) {
                final folder = _orderedFolders[index];
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left: 16 + _depth(folder) * 20,
                    right: 8,
                  ),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder['folder_name'] as String),
                  subtitle: Text(
                    '${folder['diary_count']} 篇日记 · ${_folderPath(folder['folder_id'] as int)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'add') {
                        _editFolder(parentId: folder['folder_id'] as int);
                      } else if (action == 'rename') {
                        _editFolder(folder: folder);
                      } else {
                        _deleteFolder(folder);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'add', child: Text('新建子文件夹')),
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('递归删除')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: _folders.isEmpty
          ? null
          : FloatingActionButton(
              heroTag: null,
              tooltip: '新建顶层文件夹',
              onPressed: () => _editFolder(),
              child: const Icon(Icons.create_new_folder_outlined),
            ),
    );
  }
}
