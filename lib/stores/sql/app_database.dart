import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:text/stores/sql/table_sql.dart';

class AppDatabase {
  AppDatabase._();

  static const databaseName = 'daily_life.db';
  static const databaseVersion = 1;

  static Future<Database>? _databaseFuture;
  static bool _ffiInitialized = false;

  static Future<Database> get instance => _databaseFuture ??= _openDatabase();

  static Future<Database> openInMemory() async {
    final factory = _databaseFactory;
    return factory.openDatabase(':memory:', options: _databaseOptions);
  }

  static Future<Database> _openDatabase() async {
    return _databaseFactory.openDatabase(
      await _databasePath(),
      options: _databaseOptions,
    );
  }

  static Future<String> _databasePath() async {
    if (Platform.isWindows || Platform.isLinux) {
      final baseDirectory = Platform.isWindows
          ? Platform.environment['APPDATA'] ??
                Platform.environment['LOCALAPPDATA']
          : Platform.environment['HOME'];
      if (baseDirectory == null || baseDirectory.isEmpty) {
        throw StateError('No user data directory is available for SQLite.');
      }

      final databaseDirectory = Directory(
        Platform.isWindows
            ? path.join(baseDirectory, 'text', 'database')
            : path.join(baseDirectory, '.local', 'share', 'text', 'database'),
      );
      await databaseDirectory.create(recursive: true);
      return path.join(databaseDirectory.path, databaseName);
    }

    return path.join(await sqflite.getDatabasesPath(), databaseName);
  }

  static DatabaseFactory get _databaseFactory {
    if (Platform.isWindows || Platform.isLinux) {
      if (!_ffiInitialized) {
        ffi.sqfliteFfiInit();
        _ffiInitialized = true;
      }
      return ffi.databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  static OpenDatabaseOptions get _databaseOptions => OpenDatabaseOptions(
    version: databaseVersion,
    onConfigure: (database) async {
      await database.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (database, version) async {
      for (final statement in TableSql.allTableSql) {
        await database.execute(statement);
      }
    },
  );
}
