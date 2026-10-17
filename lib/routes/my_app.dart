import 'dart:async';

import 'package:app/constants/style/app_style.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/stores/notifications/local_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../pages/main_page.dart';
import '../pages/search/search_page.dart';
import '../pages/records/records_page.dart';
import '../pages/profile/tag_management_page.dart';
import '../pages/anniversaries/anniversaries_page.dart';
import 'app_routes.dart';
import 'placeholder_page.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettingsController _settings = AppSettingsController.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<MainPageState> _mainPageKey = GlobalKey<MainPageState>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettingsAndNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setupNotificationNavigation());
    });
  }

  Future<void> _loadSettingsAndNotifications() async {
    try {
      await _settings.load();
      if (_settings.loadError != null) return;
      await LocalNotificationService.instance.syncSchedule();
    } catch (error, stackTrace) {
      // 通知排程失败不影响应用主体功能，仅记录日志，
      // 避免弹出红色错误横幅让用户误以为应用打不开。
      debugPrint('通知初始化失败（已忽略）: $error\n$stackTrace');
    }
  }

  /// 注入通知点击回调，并处理“应用被通知拉起”的冷启动跳转。
  Future<void> _setupNotificationNavigation() async {
    try {
      final service = LocalNotificationService.instance;
      await service.initialize();
      service.onPayloadTap = _handleNotificationPayload;
      final launchPayload = await service.getLaunchPayload();
      if (launchPayload != null) {
        _handleNotificationPayload(launchPayload);
      }
    } catch (error, stackTrace) {
      debugPrint('通知跳转初始化失败（已忽略）: $error\n$stackTrace');
    }
  }

  /// 通知点击路由：tasks → 任务页，finance → 财务页，
  /// anniversaries → 纪念日页，home → 首页（每日小结）。
  /// 常驻通知的 payload 可能带任务上下文（tasks|id|kind），仅取首段路由。
  void _handleNotificationPayload(String payload) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final route = payload.split('|').first;
    switch (route) {
      case 'tasks':
        navigator.popUntil((route) => route.isFirst);
        _mainPageKey.currentState?.selectTab(2);
      case 'finance':
        navigator.popUntil((route) => route.isFirst);
        _mainPageKey.currentState?.selectTab(1);
      case 'home':
        navigator.popUntil((route) => route.isFirst);
        _mainPageKey.currentState?.selectTab(0);
      case 'records':
        navigator.popUntil((route) => route.isFirst);
        _mainPageKey.currentState?.selectTab(3);
      case 'anniversaries':
        navigator.popUntil((route) => route.isFirst);
        navigator.pushNamed(AppRoutes.anniversaries);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, child) => MaterialApp(
        title: '生活手账',
        navigatorKey: _navigatorKey,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          // C1：富文本工具栏的提示文案需要 quill 自己的本地化委托，
          // 缺失会导致工具栏按钮构建抛 MissingFlutterQuillLocalizationException。
          FlutterQuillLocalizations.delegate,
        ],
        theme: AppTheme.lightThemeFor(
          _settings.seedColor,
          fontScale: _settings.fontScale,
          cardRadius: _settings.cardRadius,
          buttonRadius: _settings.buttonRadius,
          backgroundColor: _settings.backgroundColor,
        ),
        darkTheme: AppTheme.darkThemeFor(
          _settings.seedColor,
          fontScale: _settings.fontScale,
          cardRadius: _settings.cardRadius,
          buttonRadius: _settings.buttonRadius,
          backgroundColor: _settings.backgroundColor,
        ),
        themeMode: _settings.themeMode,
        initialRoute: AppRoutes.home,
        routes: {
          AppRoutes.home: (context) => MainPage(key: _mainPageKey),
          AppRoutes.records: (context) => const RecordsPage(),
          AppRoutes.search: (context) => const SearchPage(),
          AppRoutes.tags: (context) => const TagManagementPage(),
          AppRoutes.anniversaries: (context) => const AnniversariesPage(),
          AppRoutes.diary: (context) => const RecordsPage(openDiaries: true),
        },
        onUnknownRoute: (settings) => MaterialPageRoute<void>(
          builder: (context) => const PlaceholderPage(title: '页面不存在'),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
