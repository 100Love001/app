import 'dart:async';

import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/local_backup_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'routes/my_app.dart';

export 'routes/my_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 立即渲染首帧：数据库与本地化初始化放到启动门控里异步执行，
  // 不再同步阻塞 runApp，避免长时间停留在系统启动屏。
  runApp(const AppBootstrap());
}

/// 启动门控：初始化完成前渲染应用内加载页，完成后进入主界面。
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.bootstrapFuture});

  /// 测试可注入的初始化任务；为 null 时执行真实初始化。
  final Future<void>? bootstrapFuture;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<void> _future = widget.bootstrapFuture ?? _bootstrap();

  static Future<void> _bootstrap() async {
    await Future.wait([
      initializeDateFormatting('zh_CN'),
      AppDatabase.instance.database,
    ]);
    // 年度自动备份为后台任务，不阻塞进入主界面。
    unawaited(LocalBackupService.instance.checkYearlyAutoBackup());
  }

  void _retry() {
    setState(() {
      _future = widget.bootstrapFuture ?? _bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DatabaseErrorApp(error: snapshot.error!, onRetry: _retry);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapLoadingApp();
        }
        return const MyApp();
      },
    );
  }
}

/// 启动加载页：与应用默认主题色一致，深浅色跟随系统。
class _BootstrapLoadingApp extends StatelessWidget {
  const _BootstrapLoadingApp();

  static const _seedColor = Color(0xFF5267D8);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '生活手账',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _DatabaseErrorApp extends StatelessWidget {
  const _DatabaseErrorApp({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  '初始化失败',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '应用无法启动，请重试或联系技术支持。\n\n错误信息：$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
