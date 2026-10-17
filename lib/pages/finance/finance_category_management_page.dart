import 'package:app/stores/finance/finance_category_repository.dart';
import 'package:app/utils/budget_period.dart';
import 'package:app/utils/dialog.dart';
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
    // 新建支出分类默认按季度结算，与初始分类保持一致。
    var periodType =
        category?['period_type'] as String? ?? BudgetPeriods.quarterly;
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? '新增$_type分类' : '编辑$_type分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(labelText: '分类名称'),
              ),
              if (_type == '支出') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: BudgetPeriods.types.contains(periodType)
                      ? periodType
                      : BudgetPeriods.quarterly,
                  decoration: const InputDecoration(
                    labelText: '结算周期（固定时间）',
                    helperText: '周期结束后：结余按比例兑积分，超支按比例扣积分',
                  ),
                  items: [
                    for (final type in BudgetPeriods.types)
                      DropdownMenuItem(
                        value: type,
                        child: Text(BudgetPeriods.labels[type]!),
                      ),
                    const DropdownMenuItem(value: 'none', child: Text('不结算')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => periodType = value);
                    }
                  },
                ),
              ],
            ],
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
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('请输入分类名称')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (!mounted || name == null) return;
    try {
      final repo = FinanceCategoryRepository.instance;
      if (category == null) {
        await repo.add(
          type: _type,
          name: name,
          periodType: _type == '支出' ? periodType : 'none',
        );
      } else {
        await repo.rename(
          id: category['id'] as int,
          newName: name,
          oldName: category['name'] as String,
          type: _type,
        );
        if (_type == '支出' &&
            periodType != (category['period_type'] as String?)) {
          await repo.updatePeriod(
            id: category['id'] as int,
            type: _type,
            periodType: periodType,
          );
        }
      }
      await _loadCategories();
    } catch (error) {
      _showError('保存分类失败：$error');
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text(
          '删除“${category['name']}”后，已存在的账单和历史结算仍保留该分类名称，'
          '但不再进行预算统计与积分结算。确定删除吗？',
        ),
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
      await FinanceCategoryRepository.instance.delete(category['id'] as int);
      await _loadCategories();
    } catch (error) {
      _showError('删除分类失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                      final periodType =
                          category['period_type'] as String? ?? 'none';
                      return ListTile(
                        leading: Icon(
                          _type == '支出'
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                        ),
                        title: Text(category['name'] as String),
                        subtitle: _type == '支出'
                            ? Text('结算周期：${BudgetPeriods.labelOf(periodType)}')
                            : null,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _editCategory(category: category);
                            } else {
                              _deleteCategory(category);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: '新增分类',
        onPressed: () => _editCategory(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
