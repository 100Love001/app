import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// v18：新增特殊语录（时光信箱）表 time_capsules。
class MigrationV18 extends Migration {
  @override
  int get targetVersion => 18;

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE time_capsules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        unlock_date TEXT NOT NULL,
        opened INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL DEFAULT (datetime('now','localtime'))
      )
    ''');
  }
}
