import 'package:flutter/material.dart';
import 'package:text/routes/my_app.dart';
import 'package:text/stores/sql/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance;
  runApp(const MyApp());
}
