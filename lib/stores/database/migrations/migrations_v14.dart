import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

class MigrationV14 extends Migration {
  @override
  int get targetVersion => 14;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      'ALTER TABLE anniversaries ADD COLUMN calendar_type INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE anniversaries ADD COLUMN repeat_type INTEGER NOT NULL DEFAULT 1',
    );
    await db.execute(
      'ALTER TABLE anniversaries ADD COLUMN repeat_custom_days INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'UPDATE anniversaries SET repeat_type = CASE '
      'WHEN repeat_annually = 1 THEN 1 '
      'ELSE 0 END',
    );
  }
}
