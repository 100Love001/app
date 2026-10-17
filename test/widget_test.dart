import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text/routes/my_app.dart';

void main() {
  testWidgets('bottom navigation switches between five pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('早上好'), findsOneWidget);
    expect(find.text('今天的安排'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-tab-记录')));
    await tester.pumpAndSettle();

    expect(find.text('最近记录'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-tab-任务')));
    await tester.pumpAndSettle();

    expect(find.text('本周完成'), findsOneWidget);
    expect(find.text('今天的安排'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('navigation-tab-财务')));
    await tester.pumpAndSettle();

    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('最近收支'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-tab-我的')));
    await tester.pumpAndSettle();

    expect(find.text('你好，朋友'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('navigation-tab-首页')));
    await tester.pumpAndSettle();

    expect(find.text('今天的安排'), findsOneWidget);
  });
}
