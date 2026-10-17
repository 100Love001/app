import 'package:app/pages/finance/finance_category_management_page.dart';
import 'package:app/pages/profile/budget_management_page.dart';
import 'package:app/pages/profile/points_rate_management_page.dart';
import 'package:flutter/material.dart';

/// 账单体系：围绕「记账分类管理」组织的三个二级页面。
/// 分类本身可增删改；支出预算与积分兑换比例均按分类逐个配置。
class BillingSystemPage extends StatelessWidget {
  const BillingSystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    void open(Widget page) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => page),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('账单体系')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Group(
            children: [
              _Tile(
                icon: Icons.category_outlined,
                color: colorScheme.primary,
                title: '记账分类管理',
                subtitle: '新增、删除、重命名收支分类，设置结算周期',
                onTap: () => open(const FinanceCategoryManagementPage()),
              ),
              const Divider(height: 1, indent: 68),
              _Tile(
                icon: Icons.account_balance_wallet_outlined,
                color: colorScheme.secondary,
                title: '支出预算',
                subtitle: '按分类设置每天/周/月/季度的预算金额',
                onTap: () => open(const BudgetManagementPage()),
              ),
              const Divider(height: 1, indent: 68),
              _Tile(
                icon: Icons.currency_exchange_rounded,
                color: colorScheme.tertiary,
                title: '积分兑换比例',
                subtitle: '按分类设置周期结余奖励与超支扣除比例',
                onTap: () => open(const PointsRateManagementPage()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              '说明：每个支出分类都有固定结算周期。周期结束后，结余按兑换比例转为积分，'
              '超支则按比例扣除积分；未配置预算和比例的分类不参与结算。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 22,
      ),
      onTap: onTap,
    );
  }
}
