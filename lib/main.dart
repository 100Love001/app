import 'dart:async';

import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/local_backup_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'routes/my_app.dart';

export 'routes/my_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  try {
    await AppDatabase.instance.database;
    unawaited(LocalBackupService.instance.checkYearlyAutoBackup());
  } catch (e, stack) {
    debugPrint('数据库初始化失败: $e\n$stack');
    runApp(_DatabaseErrorApp(error: e));
    return;
  }

  runApp(const MyApp());
}

class _DatabaseErrorApp extends StatelessWidget {
  const _DatabaseErrorApp({required this.error});
  final Object error;

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
                  '数据库初始化失败',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '应用无法启动，请重试或联系技术支持。\n\n错误信息：$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
