import 'package:app/stores/database/migrations/migration.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MigrationV15 extends Migration {
  @override
  int get targetVersion => 15;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      'ALTER TABLE daily_tasks ADD COLUMN penalty_points INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE special_tasks ADD COLUMN penalty_points INTEGER NOT NULL DEFAULT 0',
    );
  }
}
