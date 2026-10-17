import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';
import 'migrations_v12.dart';
import 'migrations_v13.dart';
import 'migrations_v14.dart';
import 'migrations_v15.dart';
import 'migrations_v16.dart';
import 'migrations_v17.dart';
import 'migrations_v18.dart';
import 'migrations_v19.dart';
import 'migrations_v2_v4.dart';
import 'migrations_v5_v6.dart';
import 'migrations_v7_v11.dart';

final List<Migration> allMigrations = [
  MigrationV2(),
  MigrationV3(),
  MigrationV4(),
  MigrationV5(),
  MigrationV6(),
  MigrationV7(),
  MigrationV8(),
  MigrationV9(),
  MigrationV10(),
  MigrationV11(),
  MigrationV12(),
  MigrationV13(),
  MigrationV14(),
  MigrationV15(),
  MigrationV16(),
  MigrationV17(),
  MigrationV18(),
  MigrationV19(),
];

Future<void> runMigrations(Database db, int oldVersion, int newVersion) async {
  for (final migration in allMigrations) {
    if (migration.targetVersion > oldVersion &&
        migration.targetVersion <= newVersion) {
      await migration.up(db);
    }
  }
}
