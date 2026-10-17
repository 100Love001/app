import 'package:app/stores/finance/finance_category_repository.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/material.dart';

class FinanceCategoryManagementPage extends StatefulWidget {
  const FinanceCategoryManagementPage({super.key});

  @override
  State<FinanceCategoryManagementPage> createState() =>
      _FinanceCategoryManagementPageState();
}

class _FinanceCategoryManagementPageState
    extends State<FinanceCategoryManagementPage> {
  String _type = '支出';
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await FinanceCategoryRepository.instance.loadAll();
      if (!mounted) return;
      setState(() {
        _categories = rows;
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

  Future<void> _editCategory({Map<String, dynamic>? category}) async {
    final controller = TextEditingController(
      text: category?['name'] as String? ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(category == null ? '新增$_type分类' : '编辑$_type分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('请输入分类名称')));
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (!mounted || name == null) return;
    try {
      if (category == null) {
        await FinanceCategoryRepository.instance.add(
          type: _type,
          name: name,
        );
      } else {
        await FinanceCategoryRepository.instance.rename(
          id: category['id'] as int,
          newName: name,
          oldName: category['name'] as String,
          type: _type,
        );
      }
      await _loadCategories();
    } catch (error) {
      _showError('保存分类失败：$error');
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    if (toInt(category['is_system']) == 1) {
      _showError('系统预算分类不能删除');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('删除“${category['name']}”后，已存在的账单仍保留该分类名称。确定删除吗？'),
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
    if (confirmed != true || !mounted) return;
    try {
      await FinanceCategoryRepository.instance.delete(
        category['id'] as int,
      );
      await _loadCategories();
    } catch (error) {
      _showError('删除分类失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories
        .where((category) => category['type'] == _type)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账分类管理'),
        actions: [
          IconButton(
            tooltip: '新增分类',
            onPressed: () => _editCategory(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '支出', label: Text('支出分类')),
                ButtonSegment(value: '收入', label: Text('收入分类')),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
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
                        Text('分类加载失败：$_error'),
                        TextButton(
                          onPressed: _loadCategories,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : categories.isEmpty
                ? const Center(child: Text('暂无分类，点击右上角添加'))
                : ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final isSystem =
                          toInt(category['is_system']) == 1;
                      return ListTile(
                        leading: Icon(
                          _type == '支出'
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                        ),
                        title: Text(category['name'] as String),
                        subtitle: isSystem ? const Text('预算关联分类') : null,
                        trailing: isSystem
                            ? const Icon(Icons.lock_outline, size: 20)
                            : PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _editCategory(category: category);
                                  } else {
                                    _deleteCategory(category);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('重命名'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增分类',
        onPressed: () => _editCategory(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
