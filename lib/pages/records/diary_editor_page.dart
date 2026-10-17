import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:app/utils/folder_path.dart';

/// 日记编辑/查看结果：
/// - [deleted] 为 true 表示用户选择删除；
/// - 否则 [title]/[content]/[contentFormat]/[folderId] 为待保存的值。
class DiaryEditResult {
  const DiaryEditResult({
    this.deleted = false,
    this.title,
    this.content,
    this.contentFormat,
    this.folderId,
  });

  final bool deleted;
  final String? title;
  final String? content;
  final String? contentFormat;
  final int? folderId;
}

/// C1：日记/认知本独立全屏编辑页。
///
/// - 新建或编辑时显示标题、文件夹与富文本工具栏；
/// - 查看模式（[viewMode]）下工具栏隐藏、正文只读，可切换到编辑或删除。
class DiaryEditorPage extends StatefulWidget {
  const DiaryEditorPage({
    super.key,
    required this.bookType,
    required this.folders,
    this.diary,
  });

  /// cognition=认知本，diary=日记本。
  final String bookType;

  /// 仅包含当前本子的文件夹列表。
  final List<Map<String, dynamic>> folders;

  /// 编辑已有内容时传入；新建时为 null。
  final Map<String, dynamic>? diary;

  String get bookName => bookType == 'diary' ? '日记' : '认知';

  @override
  State<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends State<DiaryEditorPage> {
  late final TextEditingController _titleController;
  late QuillController _controller;
  late FocusNode _focusNode;
  late ScrollController _scrollController;
  late int _selectedFolderId;
  bool _viewMode = false;

  @override
  void initState() {
    super.initState();
    final diary = widget.diary;
    _titleController = TextEditingController(
      text: (diary?['title'] as String?) ?? '',
    );
    _selectedFolderId =
        (diary?['folder_id'] as int?) ??
        (widget.folders.isNotEmpty
            ? widget.folders.first['folder_id'] as int
            : 0);
    _viewMode = diary != null;
    _focusNode = FocusNode();
    _scrollController = ScrollController();
    _controller = _buildController(diary);
  }

  QuillController _buildController(Map<String, dynamic>? diary) {
    final content = diary?['content'] as String?;
    final format = (diary?['content_format'] as String?) ?? 'plaintext';
    Document document;
    if (format == 'delta' && content != null && content.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          document = Document.fromJson(decoded);
        } else {
          document = Document()..insert(0, content);
        }
      } catch (_) {
        document = Document()..insert(0, content);
      }
    } else {
      document = Document()..insert(0, content ?? '');
    }
    return QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: _viewMode,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      _viewMode = false;
      _controller.readOnly = false;
    });
    Future.microtask(() => _focusNode.requestFocus());
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }
    if (_selectedFolderId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建一个文件夹')),
      );
      return;
    }
    final content = jsonEncode(_controller.document.toDelta().toJson());
    Navigator.pop(
      context,
      DiaryEditResult(
        title: title,
        content: content,
        contentFormat: 'delta',
        folderId: _selectedFolderId,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除${widget.bookName}内容'),
        content: Text('确定删除“${_titleController.text.trim()}”吗？'),
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
    if (confirmed == true && mounted) {
      Navigator.pop(context, const DiaryEditResult(deleted: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderedFolders = _orderedFolders();
    final editing = !_viewMode;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewMode
              ? '查看${widget.bookName}'
              : '${widget.diary == null ? '新建' : '编辑'}${widget.bookName}',
        ),
        actions: [
          if (_viewMode && widget.diary != null) ...[
            IconButton(
              tooltip: '编辑',
              onPressed: _toggleEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          if (editing)
            IconButton(
              tooltip: '保存',
              onPressed: _save,
              icon: const Icon(Icons.check),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  enabled: editing,
                  maxLength: 80,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _selectedFolderId == 0 ? null : _selectedFolderId,
                  decoration: InputDecoration(
                    labelText: '${widget.bookName}文件夹',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final folder in orderedFolders)
                      DropdownMenuItem<int>(
                        value: folder['folder_id'] as int,
                        child: Text(
                          FolderPathUtil.buildPath(
                            folder['folder_id'] as int,
                            widget.folders,
                          ),
                        ),
                      ),
                  ],
                  onChanged: editing
                      ? (value) {
                          if (value != null) {
                            setState(() => _selectedFolderId = value);
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (editing)
            QuillSimpleToolbar(
              controller: _controller,
              config: const QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: true,
                showBoldButton: true,
                showItalicButton: true,
                showUnderLineButton: true,
                showStrikeThrough: false,
                showInlineCode: false,
                showColorButton: true,
                showBackgroundColorButton: true,
                showClearFormat: true,
                showHeaderStyle: false,
                showListNumbers: false,
                showListBullets: false,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: false,
                showIndent: false,
                showLink: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
              ),
            ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: QuillEditor(
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                config: QuillEditorConfig(
                  expands: true,
                  autoFocus: editing && widget.diary == null,
                  placeholder: '在此输入${widget.bookName}内容…',
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _orderedFolders() {
    final ordered = <Map<String, dynamic>>[];
    final visited = <int>{};
    void appendChildren(int? parentId) {
      for (final folder in widget.folders) {
        if (folder['parent_id'] != parentId) continue;
        final id = folder['folder_id'] as int;
        if (!visited.add(id)) continue;
        ordered.add(folder);
        appendChildren(id);
      }
    }

    appendChildren(null);
    for (final folder in widget.folders) {
      final id = folder['folder_id'] as int;
      if (visited.add(id)) {
        ordered.add(folder);
        appendChildren(id);
      }
    }
    return ordered;
  }
}
