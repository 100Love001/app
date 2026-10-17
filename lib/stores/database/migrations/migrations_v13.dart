import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

class MigrationV13 extends Migration {
  @override
  int get targetVersion => 13;

  @override
  Future<void> up(Database db) async {
    await db.execute(
      "ALTER TABLE anniversaries ADD COLUMN tag TEXT NOT NULL DEFAULT ''",
    );
  }
}
