import 'package:flutter/material.dart';

const _backgroundColor = Color(0xFFF8F7FB);
const _accentColor = Color(0xFF9B8AE8);
const _mutedTextColor = Color(0xFF9795A3);
const _primaryTextColor = Color(0xFF292735);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '日常',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          surface: _backgroundColor,
        ),
        fontFamily: 'Roboto',
      ),
      home: const MainNavigationPage(),
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    _HomePage(),
    _RecordsPage(),
    _TasksPage(),
    _FinancePage(),
    _ProfilePage(),
  ];

  static const _tabs = <_NavigationTab>[
    _NavigationTab(label: '首页', icon: Icons.home_outlined),
    _NavigationTab(label: '记录', icon: Icons.description_outlined),
    _NavigationTab(label: '任务', icon: Icons.task_alt_outlined),
    _NavigationTab(label: '财务', icon: Icons.account_balance_wallet_outlined),
    _NavigationTab(label: '我的', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _BottomNavigationBar(
        tabs: _tabs,
        selectedIndex: _selectedIndex,
        onSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class _NavigationTab {
  const _NavigationTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavigationTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF0EFF4))),
        ),
        child: Row(
          children: [
            for (var index = 0; index < tabs.length; index++)
              Expanded(
                child: _NavigationItem(
                  tab: tabs[index],
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavigationTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _accentColor : _mutedTextColor;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        key: ValueKey('navigation-tab-${tab.label}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 42,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? _accentColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(tab.icon, size: 22, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '早上好',
      subtitle: '把今天过成喜欢的样子',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightCard(
            eyebrow: '今日心情',
            title: '慢慢来，也很好',
            detail: '给自己一点空间，享受当下。',
            icon: Icons.wb_sunny_outlined,
            color: const Color(0xFFFFF0D9),
            iconColor: const Color(0xFFE2A44E),
          ),
          const SizedBox(height: 24),
          const _SectionHeading(title: '今天的安排', action: '查看全部'),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.check_circle_outline,
            title: '完成每日计划',
            detail: '保持专注，一步一步来',
            tint: Color(0xFFEDE9FC),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.edit_note_outlined,
            title: '记下一个好点子',
            detail: '随时记录灵感和想法',
            tint: Color(0xFFE6F3EF),
          ),
          const SizedBox(height: 24),
          const _SectionHeading(title: '小小进度', action: '本周'),
          const SizedBox(height: 12),
          const _ProgressCard(),
        ],
      ),
    );
  }
}

class _RecordsPage extends StatelessWidget {
  const _RecordsPage();

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '记录',
      subtitle: '收藏生活里的每一个瞬间',
      action: const _CircleAction(icon: Icons.add),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SearchCard(),
          const SizedBox(height: 24),
          const _SectionHeading(title: '最近记录', action: '全部'),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.menu_book_outlined,
            title: '周末的咖啡时光',
            detail: '今天 · 生活随记',
            tint: Color(0xFFFFEEE4),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.lightbulb_outline,
            title: '关于新项目的灵感',
            detail: '昨天 · 灵感笔记',
            tint: Color(0xFFEDE9FC),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.favorite_border,
            title: '最近读到的一句话',
            detail: '10月14日 · 收藏',
            tint: Color(0xFFFBEAF0),
          ),
        ],
      ),
    );
  }
}

class _TasksPage extends StatelessWidget {
  const _TasksPage();

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '任务',
      subtitle: '专注当下，完成一件小事',
      action: const _CircleAction(icon: Icons.add),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HighlightCard(
            eyebrow: '本周完成',
            title: '12 / 16 项任务',
            detail: '状态不错，继续保持！',
            icon: Icons.task_alt,
            color: Color(0xFFEDE9FC),
            iconColor: _accentColor,
          ),
          const SizedBox(height: 24),
          const _SectionHeading(title: '今天', action: '3 项'),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.radio_button_unchecked,
            title: '整理本周的工作计划',
            detail: '上午 · 工作',
            tint: Color(0xFFEDE9FC),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.radio_button_unchecked,
            title: '读书 20 分钟',
            detail: '下午 · 习惯',
            tint: Color(0xFFE6F3EF),
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.check_circle,
            title: '喝一杯温水',
            detail: '已完成 · 健康',
            tint: Color(0xFFFFF0D9),
            completed: true,
          ),
        ],
      ),
    );
  }
}

class _FinancePage extends StatelessWidget {
  const _FinancePage();

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '财务',
      subtitle: '轻松看见每一笔收支',
      action: const _CircleAction(icon: Icons.add),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFA998ED), Color(0xFF8273D1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月结余',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                SizedBox(height: 8),
                Text(
                  '¥ 3,280.00',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 22),
                Row(
                  children: [
                    _MoneySummary(label: '收入', amount: '¥ 8,600'),
                    SizedBox(width: 32),
                    _MoneySummary(label: '支出', amount: '¥ 5,320'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeading(title: '最近收支', action: '明细'),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.local_cafe_outlined,
            title: '咖啡',
            detail: '今天 09:32 · 餐饮',
            tint: Color(0xFFFFEEE4),
            trailing: '- ¥ 28.00',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.account_balance_wallet_outlined,
            title: '月度工资',
            detail: '10月15日 · 收入',
            tint: Color(0xFFE6F3EF),
            trailing: '+ ¥ 8,600.00',
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: '我的',
      subtitle: '照顾好自己，也是一件大事',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 29,
                  backgroundColor: Color(0xFFEDE9FC),
                  child: Icon(Icons.person_outline, color: _accentColor, size: 30),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '你好，朋友',
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '记录每一天的成长',
                        style: TextStyle(color: _mutedTextColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: _mutedTextColor),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _ProfileMenuCard(
            items: [
              _ProfileMenuItem(icon: Icons.bar_chart_outlined, label: '我的总结'),
              _ProfileMenuItem(icon: Icons.bookmark_border, label: '我的收藏'),
              _ProfileMenuItem(icon: Icons.notifications_none, label: '消息通知'),
            ],
          ),
          const SizedBox(height: 16),
          const _ProfileMenuCard(
            items: [
              _ProfileMenuItem(icon: Icons.settings_outlined, label: '设置'),
              _ProfileMenuItem(icon: Icons.help_outline, label: '帮助与反馈'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        key: PageStorageKey(title),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _primaryTextColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ?action,
                  ],
                ),
                const SizedBox(height: 24),
                child,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _primaryTextColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          action,
          style: const TextStyle(color: _mutedTextColor, fontSize: 12),
        ),
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: _primaryTextColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: const TextStyle(color: _mutedTextColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 38, color: iconColor),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tint,
    this.trailing,
    this.completed = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color tint;
  final String? trailing;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(
              icon,
              size: 21,
              color: completed ? const Color(0xFF74B99A) : _accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: completed ? _mutedTextColor : _primaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(color: _mutedTextColor, fontSize: 11),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: _primaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '每日记录',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '5 / 7 天',
                style: TextStyle(color: _mutedTextColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const LinearProgressIndicator(
              value: 5 / 7,
              minHeight: 7,
              backgroundColor: Color(0xFFF0EEF7),
              color: _accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, color: _mutedTextColor, size: 20),
          SizedBox(width: 10),
          Text(
            '搜索你的记录',
            style: TextStyle(color: _mutedTextColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _accentColor, size: 22),
    );
  }
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          amount,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProfileMenuItem {
  const _ProfileMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({required this.items});

  final List<_ProfileMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              const Divider(height: 1, color: Color(0xFFF2F1F5)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  Icon(items[index].icon, color: _accentColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      items[index].label,
                      style: const TextStyle(
                        color: _primaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _mutedTextColor),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
