import 'package:app/pages/finance/finance_page.dart';
import 'package:app/pages/home/home_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:app/pages/records/records_page.dart';
import 'package:app/pages/tasks/tasks_page.dart';
import 'package:flutter/material.dart';

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _tabs = [
  _TabItem(label: '首页', icon: Icons.home_outlined, selectedIcon: Icons.home),
  _TabItem(
    label: '记录',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  _TabItem(
    label: '任务',
    icon: Icons.check_circle_outline,
    selectedIcon: Icons.check_circle,
  ),
  _TabItem(
    label: '财务',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  _TabItem(label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
];

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final GlobalKey<RecordsPageState> _recordsKey = GlobalKey<RecordsPageState>();
  final GlobalKey<TasksPageState> _tasksKey = GlobalKey<TasksPageState>();
  final GlobalKey<FinancePageState> _financeKey = GlobalKey<FinancePageState>();
  final GlobalKey<ProfilePageState> _profileKey = GlobalKey<ProfilePageState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomePage(key: _homeKey),
          RecordsPage(key: _recordsKey),
          TasksPage(key: _tasksKey),
          FinancePage(key: _financeKey),
          ProfilePage(
            key: _profileKey,
            onPersonalDataChanged: _refreshAllPages,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (index == 0) _homeKey.currentState?.refresh();
    if (index == 1) _recordsKey.currentState?.refresh();
    if (index == 2) _tasksKey.currentState?.refresh();
    if (index == 3) _financeKey.currentState?.refresh();
    if (index == 4) _profileKey.currentState?.refresh();
    setState(() => _selectedIndex = index);
  }

  /// 供通知跳转等外部入口切换 Tab（会顺带刷新目标页数据）。
  void selectTab(int index) => _selectTab(index);

  /// 恢复备份 / 清空数据后刷新所有常驻 Tab，丢弃恢复前的内存数据。
  void _refreshAllPages() {
    _homeKey.currentState?.refresh();
    _recordsKey.currentState?.refresh();
    _tasksKey.currentState?.refresh();
    _financeKey.currentState?.refresh();
    _profileKey.currentState?.refresh();
  }
}
