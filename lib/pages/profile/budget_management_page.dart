import 'dart:async';

import 'package:app/constants/finance_budgets.dart';
import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/time.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class BudgetManagementPage extends StatefulWidget {
  const BudgetManagementPage({super.key});

  @override
  State<BudgetManagementPage> createState() => _BudgetManagementPageState();
}

class _BudgetManagementPageState extends State<BudgetManagementPage> {
  final Map<String, double> _budgets = {};
  Object? _budgetError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBudgets());
  }

  Future<void> _loadBudgets() async {
    try {
      final keys = FinanceBudgets.categories
          .map((category) => category.settingKey)
          .toList();
      final rows = await AppDatabase.instance.database.then(
        (db) => db.query(
          'app_settings',
          columns: ['key', 'value'],
          where: 'key IN (${List.filled(keys.length, '?').join(', ')})',
          whereArgs: keys,
        ),
      );
      if (!mounted) return;
      setState(() {
        _budgetError = null;
        _budgets
          ..clear()
          ..addEntries(
            rows.map(
              (row) => MapEntry(
                row['key']! as String,
                double.tryParse(row['value']! as String) ?? 0,
              ),
            ),
          );
      });
    } catch (error) {
      if (mounted) setState(() => _budgetError = error);
    }
  }

  Future<void> _editBudget(FinanceBudgetCategory category) async {
    final controller = TextEditingController(
      text: (_budgets[category.settingKey] ?? 0).toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('设置${category.period}${category.budgetLabel}预算'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '预算金额',
            prefixText: '¥ ',
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
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('请输入有效的非负金额')));
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    try {
      final db = await AppDatabase.instance.database;
      await db.transaction((transaction) async {
        await transaction.insert('app_settings', {
          'key': category.settingKey,
          'value': amount.toStringAsFixed(2),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (category.settingKey == 'daily_food_budget') {
          final tomorrow = DateTime.now().add(const Duration(days: 1));
          await transaction.insert('budget_history', {
            'budget_date': TimeUtil.toDateKey(tomorrow),
            'budget_amount': amount,
            'update_time': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      if (!mounted) return;
      setState(() => _budgets[category.settingKey] = amount);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存预算失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('收支预算')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_budgetError != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.error_outline, color: colorScheme.error),
                title: const Text('收支预算读取失败'),
                subtitle: Text('$_budgetError'),
                trailing: IconButton(
                  tooltip: '重试',
                  onPressed: _loadBudgets,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          for (var index = 0; index < FinanceBudgets.categories.length; index++)
            Card(
              child: Builder(
                builder: (context) {
                  final category = FinanceBudgets.categories[index];
                  final amount = _budgets[category.settingKey] ?? 0;
                  return ListTile(
                    leading: Icon(
                      category.settingKey == 'daily_food_budget'
                          ? Icons.restaurant_outlined
                          : Icons.payments_outlined,
                      color: colorScheme.primary,
                    ),
                    title: Text('${category.period}${category.budgetLabel}预算'),
                    subtitle: Text('预算 ¥${amount.toStringAsFixed(2)}'),
                    trailing: const Icon(Icons.edit_outlined, size: 19),
                    onTap: () => _editBudget(category),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
