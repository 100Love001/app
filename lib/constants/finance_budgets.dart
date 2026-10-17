class FinanceBudgetCategory {
  const FinanceBudgetCategory({
    required this.category,
    required this.budgetLabel,
    required this.settingKey,
    required this.period,
  });

  final String category;
  final String budgetLabel;
  final String settingKey;
  final String period;
}

abstract final class FinanceBudgets {
  static const categories = <FinanceBudgetCategory>[
    FinanceBudgetCategory(
      category: '今日饭钱',
      budgetLabel: '饭钱',
      settingKey: 'daily_food_budget',
      period: '每天',
    ),
    FinanceBudgetCategory(
      category: '今季度衣服费用',
      budgetLabel: '衣服',
      settingKey: 'quarterly_clothing_budget',
      period: '今季度',
    ),
    FinanceBudgetCategory(
      category: '今季度日用品费用',
      budgetLabel: '日用品',
      settingKey: 'quarterly_necessities_budget',
      period: '今季度',
    ),
    FinanceBudgetCategory(
      category: '路费',
      budgetLabel: '路费',
      settingKey: 'quarterly_transport_budget',
      period: '今季度',
    ),
    FinanceBudgetCategory(
      category: '其他',
      budgetLabel: '其他',
      settingKey: 'quarterly_other_budget',
      period: '今季度',
    ),
  ];
}
