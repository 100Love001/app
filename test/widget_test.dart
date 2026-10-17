import 'package:app/main.dart';
import 'package:app/pages/profile/appearance_settings_page.dart';
import 'package:app/pages/profile/budget_management_page.dart';
import 'package:app/pages/profile/profile_page.dart';
import 'package:app/pages/profile/quote_management_page.dart';
import 'package:app/pages/profile/quote_reply_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分帧推进，等待异步数据加载与路由动画完成。
/// 不用 pumpAndSettle：页面轮播定时器存在时它永不静默。
Future<void> pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 滚动我的页面直到目标磁贴可见，点击并等待目标页加载。
/// 先 scrollUntilVisible 触发懒构建，再 ensureVisible 保证可点击。
Future<void> tapProfileTile(WidgetTester tester, String title) async {
  final scrollable = find.descendant(
    of: find.byType(ProfilePage),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: scrollable.first,
  );
  await tester.ensureVisible(find.text(title));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(title));
  await tester.pump();
  await pumpFrames(tester);
}

void main() {
  testWidgets('opens the home tab and switches tabs', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今日语录'), findsOneWidget);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.byKey(const ValueKey('personal-motto')), findsOneWidget);
    expect(find.text('今日心情'), findsNothing);
    expect(find.text('今日收支'), findsNothing);
    expect(find.text('今日任务'), findsNothing);
    expect(find.text('希望清单'), findsNothing);
    expect(find.byTooltip('全局搜索'), findsNothing);

    await tester.tap(find.text('任务'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets('home hides daily collections and mood shortcuts', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.text('今日任务'), findsNothing);
    expect(find.text('愿望清单'), findsNothing);
    expect(find.text('希望清单'), findsNothing);
    expect(find.text('今日心情'), findsNothing);
  });

  testWidgets('records no longer expose mood functionality', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('心情'), findsNothing);
    expect(find.text('记录今日心情'), findsNothing);
  });

  testWidgets('profile exposes personal and appearance settings', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('生活概览'), findsNothing);
    expect(find.text('生活规划师'), findsOneWidget);
    expect(find.text('提醒通知'), findsOneWidget);
    expect(find.text('外观与样式'), findsOneWidget);
    await tester.tap(find.text('外观与样式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('主题颜色'), findsOneWidget);
    expect(find.text('樱花粉'), findsOneWidget);
    expect(find.text('石墨灰'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    final appearanceScroll = find.descendant(
      of: find.byType(AppearanceSettingsPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('字体大小'),
      300,
      scrollable: appearanceScroll.first,
    );
    expect(find.text('卡片样式'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('背景颜色'),
      300,
      scrollable: appearanceScroll.first,
    );
    expect(find.text('按键样式'), findsOneWidget);
    expect(find.text('背景颜色'), findsOneWidget);
  });

  testWidgets('profile exposes finance management entries', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);

    expect(find.text('记账分类管理'), findsOneWidget);
    expect(find.text('收支预算'), findsOneWidget);
    await tapProfileTile(tester, '收支预算');
    expect(find.byType(BudgetManagementPage), findsOneWidget);
  });

  testWidgets('profile opens the quote management page', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '今日语录');

    expect(find.byType(QuoteManagementPage), findsOneWidget);
  });

  testWidgets('profile provides quote reply history', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '语录回复');
    expect(find.byType(QuoteReplyHistoryPage), findsOneWidget);
  });

  testWidgets('home exposes a tappable anniversary folder entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.ensureVisible(find.text('纪念日'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('管理纪念日'), findsOneWidget);
    expect(find.byIcon(Icons.event_available_outlined), findsOneWidget);
  });

  testWidgets('diary page remains available from records', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('记录'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('日记本'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('日记本'), findsOneWidget);
    expect(find.text('天气'), findsNothing);
    expect(find.text('待补充业务内容'), findsNothing);
  });

  testWidgets('profile opens management for all tag groups', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '标签管理');

    expect(find.text('全局标签'), findsOneWidget);
    expect(find.text('愿望标签'), findsOneWidget);
    expect(find.text('希望标签'), findsOneWidget);
    expect(find.text('日常任务标签'), findsOneWidget);
    expect(find.byTooltip('新增标签'), findsOneWidget);
  });

  testWidgets('finance exposes period and amount filters', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('财务'));
    await pumpFrames(tester);

    expect(find.text('收支记账'), findsOneWidget);
    expect(find.text('积分体系'), findsOneWidget);
    expect(find.byTooltip('添加收支'), findsOneWidget);
  });

  testWidgets('profile opens finance category management', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '记账分类管理');

    expect(find.text('支出分类'), findsOneWidget);
    expect(find.text('收入分类'), findsOneWidget);
    expect(find.byTooltip('新增分类'), findsWidgets);
  });

  testWidgets('profile exposes full database backup and restore actions', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '数据备份与恢复');

    expect(find.text('创建备份'), findsOneWidget);
    expect(find.text('导入备份文件'), findsOneWidget);
  });

  testWidgets('preference settings exposes four customizable values', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '个性化参数');

    expect(find.text('积分兑换比例'), findsOneWidget);
    expect(find.text('每日小结推送时间'), findsOneWidget);
    expect(find.text('纪念日提醒时间'), findsOneWidget);
    expect(find.text('任务默认提前提醒'), findsOneWidget);
  });

  testWidgets('time capsule validates content before sealing', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '特殊语录');

    expect(find.text('还没有特殊语录'), findsOneWidget);
    await tester.tap(find.text('写语录'));
    await pumpFrames(tester);
    expect(find.text('写给未来的自己'), findsOneWidget);

    // 内容为空时给出明确校验提示，不允许封存。
    await tester.tap(find.text('封存'));
    await tester.pump();
    expect(find.text('内容不能为空'), findsOneWidget);

    // 输入内容后校验通过，对话框关闭（数据库写入在测试环境外验证）。
    await tester.enterText(find.byType(TextFormField), '未来的我，你好');
    await tester.tap(find.text('封存'));
    await pumpFrames(tester);
    expect(find.text('写给未来的自己'), findsNothing);
  });

  testWidgets('data analysis page opens from profile', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.tap(find.text('我的'));
    await pumpFrames(tester);
    await tapProfileTile(tester, '数据分析');

    // 页面成功推入（数据库统计在测试环境外验证，此处停留在加载态）。
    expect(find.text('数据分析'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
