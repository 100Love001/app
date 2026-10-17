import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MigrationV16 extends Migration {
  @override
  int get targetVersion => 16;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      'ALTER TABLE hope_progress_logs RENAME TO hope_progress_logs_old',
    );
    await db.execute('''
      CREATE TABLE hope_progress_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hope_id INTEGER NOT NULL,
        progress_date TEXT NOT NULL,
        amount INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (hope_id) REFERENCES hopes(hope_id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'INSERT INTO hope_progress_logs (id, hope_id, progress_date, amount) '
      'SELECT id, hope_id, progress_date, amount FROM hope_progress_logs_old',
    );
    await db.execute('DROP TABLE hope_progress_logs_old');
  }
}
