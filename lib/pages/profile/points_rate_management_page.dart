import 'dart:async';

import 'package:app/stores/finance/finance_category_repository.dart';
import 'package:app/utils/budget_period.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/material.dart';

/// 积分兑换比例：为每个支出分类设置周期结算时的两个比例（单位：积分/元）：
/// - 结余奖励：周期结束有结余时，每元结余兑换的积分（向下取整）；
/// - 超支扣除：周期结束超支时，每元超支扣除的积分（向上取整）。
/// 任一比例为 0 表示该方向不参与积分；两个都为 0 的分类不结算。
class PointsRateManagementPage extends StatefulWidget {
  const PointsRateManagementPage({super.key});

  @override
  State<PointsRateManagementPage> createState() =>
      _PointsRateManagementPageState();
}

class _PointsRateManagementPageState
    extends State<PointsRateManagementPage> {
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

  Future<void> _editRates(Map<String, dynamic> category) async {
    final balanceController = TextEditingController(
      text: '${toInt(category['balance_rate'])}',
    );
    final overageController = TextEditingController(
      text: '${toInt(category['overage_rate'])}',
    );
    final formKey = GlobalKey<FormState>();
    final periodLabel =
        BudgetPeriods.labelOf(category['period_type'] as String? ?? 'none');
    final values = await showDialog<(int, int)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${category['name']} · 积分兑换比例'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('结算周期：$periodLabel'),
              const SizedBox(height: 12),
              TextFormField(
                controller: balanceController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '结余奖励比例',
                  suffixText: '积分 / 元',
                  helperText: '周期结束有结余时，每元兑换多少积分',
                ),
                validator: (text) => _validateRate(text),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: overageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '超支扣除比例',
                  suffixText: '积分 / 元',
                  helperText: '周期结束超支时，每元扣除多少积分',
                ),
                validator: (text) => _validateRate(text),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(dialogContext, (
                int.parse(balanceController.text.trim()),
                int.parse(overageController.text.trim()),
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    balanceController.dispose();
    overageController.dispose();
    if (values == null || !mounted) return;
    try {
      await FinanceCategoryRepository.instance.updateRates(
        id: category['id'] as int,
        balanceRate: values.$1,
        overageRate: values.$2,
      );
      await _loadCategories();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存比例失败：$error')));
      }
    }
  }

  String? _validateRate(String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null || value < 0 || value > 100) {
      return '请输入 0-100 的整数（0=不参与）';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('积分兑换比例')),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('比例读取失败：$_error'),
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
                        Icons.currency_exchange_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(category['name'] as String),
                      subtitle: Text(
                        '${BudgetPeriods.labelOf(category['period_type'] as String? ?? 'none')}：'
                        '结余 +${toInt(category['balance_rate'])} / 元'
                        ' · 超支 -${toInt(category['overage_rate'])} / 元',
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 19),
                      onTap: () => _editRates(category),
                    ),
                  ),
              ],
            ),
    );
  }
}
