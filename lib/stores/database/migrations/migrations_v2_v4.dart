import 'package:app/stores/database/data/init_data.dart';
import 'package:app/stores/database/data/sql.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

class MigrationV2 extends Migration {
  @override
  int get targetVersion => 2;

  @override
  Future<void> up(Database db) async {
    for (final sql in TableSql.moodTableSql) {
      await db.execute(sql);
    }
    await InitDbData.insertMoodSeedData(db);
  }
}

class MigrationV3 extends Migration {
  @override
  int get targetVersion => 3;

  @override
  Future<void> up(Database db) async {
    for (final sql in [
      TableSql.createSpecialTaskTags,
      TableSql.createDailyTaskTags,
      TableSql.createSpecialTasks,
      TableSql.createDailyTasks,
    ]) {
      await db.execute(sql);
    }
    await InitDbData.insertTaskSeedData(db);
  }
}

class MigrationV4 extends Migration {
  @override
  int get targetVersion => 4;

  @override
  Future<void> up(Database db) async {
    for (final sql in [
      'ALTER TABLE wishes ADD COLUMN content TEXT',
      'ALTER TABLE wishes ADD COLUMN desire INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE wishes ADD COLUMN tag_id INTEGER',
      'ALTER TABLE hopes ADD COLUMN content TEXT',
      'ALTER TABLE hopes ADD COLUMN desire INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE hopes ADD COLUMN tag_id INTEGER',
      TableSql.createWishTags,
      TableSql.createHopeTags,
      TableSql.createDesireLogs,
    ]) {
      await db.execute(sql);
    }
    await InitDbData.insertCollectionSeedData(db);
  }
}
