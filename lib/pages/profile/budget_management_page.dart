import 'dart:async';

import 'package:app/stores/finance/finance_category_repository.dart';
import 'package:app/utils/budget_period.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/material.dart';

/// 支出预算：为「记账分类管理」中的每个支出分类设置周期预算。
/// 周期结束时，结余按兑换比例兑积分、超支按比例扣积分（见 PointsService）。
class BudgetManagementPage extends StatefulWidget {
  const BudgetManagementPage({super.key});

  @override
  State<BudgetManagementPage> createState() => _BudgetManagementPageState();
}

class _BudgetManagementPageState extends State<BudgetManagementPage> {
  List<Map<String, dynamic>> _categories = [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCategories());
  }

  Future<void> _loadCategories() async {
    try {
      final rows =
          await FinanceCategoryRepository.instance.loadExpenseCategories();
      if (!mounted) return;
      setState(() {
        _error = null;
        _categories = rows;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _editBudget(Map<String, dynamic> category) async {
    final controller = TextEditingController(
      text: toDouble(category['budget']).toStringAsFixed(2),
    );
    final periodLabel =
        BudgetPeriods.labelOf(category['period_type'] as String? ?? 'none');
    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('设置${category['name']}预算'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '$periodLabel预算金额',
            prefixText: '¥ ',
            helperText: '结算周期：$periodLabel（在记账分类管理中修改）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || !value.isFinite || value < 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('请输入有效的非负金额')),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 等待退场动画结束再释放，避免输入框仍在树上时崩溃。
    await waitForDialogDismissal();
    controller.dispose();
    if (amount == null || !mounted) return;
    try {
      await FinanceCategoryRepository.instance.updateBudget(
        id: category['id'] as int,
        budget: amount,
      );
      await _loadCategories();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存预算失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('支出预算')),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('预算读取失败：$_error'),
                  TextButton(
                    onPressed: _loadCategories,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : _categories.isEmpty
          ? const Center(child: Text('暂无支出分类，请先在记账分类管理中添加'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                for (final category in _categories)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.payments_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(category['name'] as String),
                      subtitle: Text(
                        '${BudgetPeriods.labelOf(category['period_type'] as String? ?? 'none')}预算 '
                        '¥${toDouble(category['budget']).toStringAsFixed(2)}',
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 19),
                      onTap: () => _editBudget(category),
                    ),
                  ),
              ],
            ),
    );
  }
}
