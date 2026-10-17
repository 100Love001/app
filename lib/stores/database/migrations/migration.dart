import 'package:sqflite_sqlcipher/sqflite.dart';

abstract class Migration {
  int get targetVersion;
  Future<void> up(Database db);
}
