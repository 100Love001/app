import 'package:app/stores/database/data/init_data.dart';
import 'package:app/stores/database/data/sql.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String column,
  String alterSql,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.any((info) => info['name'] == column)) return;
  await db.execute(alterSql);
}

Future<void> _ensureQuoteSchema(Database db) async {
  await db.execute(TableSql.createQuotes);
  final quoteColumns = await db.rawQuery('PRAGMA table_info(quotes)');
  final quoteColumnNames = quoteColumns
      .map((column) => column['name'] as String)
      .toSet();
  await _addColumnIfMissing(
    db, 'quotes', 'quote_id',
    'ALTER TABLE quotes ADD COLUMN quote_id INTEGER',
  );
  await _addColumnIfMissing(
    db, 'quotes', 'content',
    "ALTER TABLE quotes ADD COLUMN content TEXT NOT NULL DEFAULT ''",
  );
  await _addColumnIfMissing(
    db, 'quotes', 'author',
    'ALTER TABLE quotes ADD COLUMN author TEXT',
  );
  await _addColumnIfMissing(
    db, 'quotes', 'like_count',
    'ALTER TABLE quotes ADD COLUMN like_count INTEGER NOT NULL DEFAULT 0',
  );
  await _addColumnIfMissing(
    db, 'quotes', 'create_time',
    'ALTER TABLE quotes ADD COLUMN create_time TEXT',
  );
  await db.execute(
    "UPDATE quotes SET create_time = datetime('now','localtime') "
    'WHERE create_time IS NULL',
  );
  final quoteTextColumn = [
    'quote', 'text', 'sentence',
  ].where(quoteColumnNames.contains).firstOrNull;
  if (quoteTextColumn != null && !quoteColumnNames.contains('content')) {
    await db.execute(
      "UPDATE quotes SET content = $quoteTextColumn WHERE content = ''",
    );
  }
  final quoteLikesColumn = [
    'likes', 'likes_count', 'like_value',
  ].where(quoteColumnNames.contains).firstOrNull;
  if (quoteLikesColumn != null) {
    await db.execute(
      'UPDATE quotes SET like_count = MAX('
      'COALESCE(like_count, 0), COALESCE($quoteLikesColumn, 0))',
    );
  }
  if (!quoteColumnNames.contains('quote_id')) {
    final sourceId = quoteColumnNames.contains('id') ? 'id' : 'rowid';
    await db.execute(
      'UPDATE quotes SET quote_id = $sourceId WHERE quote_id IS NULL',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS quotes_assign_quote_id
      AFTER INSERT ON quotes
      WHEN NEW.quote_id IS NULL
      BEGIN
        UPDATE quotes SET quote_id = NEW.rowid WHERE rowid = NEW.rowid;
      END
    ''');
  }
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS quotes_quote_id_index '
    'ON quotes(quote_id)',
  );

  await db.execute(TableSql.createQuoteReplies);
  final replyColumns = await db.rawQuery('PRAGMA table_info(quote_replies)');
  final replyColumnNames = replyColumns
      .map((column) => column['name'] as String)
      .toSet();
  await _addColumnIfMissing(
    db, 'quote_replies', 'reply_id',
    'ALTER TABLE quote_replies ADD COLUMN reply_id INTEGER',
  );
  await _addColumnIfMissing(
    db, 'quote_replies', 'quote_id',
    'ALTER TABLE quote_replies ADD COLUMN quote_id INTEGER',
  );
  await _addColumnIfMissing(
    db, 'quote_replies', 'content',
    "ALTER TABLE quote_replies ADD COLUMN content TEXT NOT NULL DEFAULT ''",
  );
  await _addColumnIfMissing(
    db, 'quote_replies', 'create_time',
    'ALTER TABLE quote_replies ADD COLUMN create_time TEXT',
  );
  await db.execute(
    "UPDATE quote_replies SET create_time = datetime('now','localtime') "
    'WHERE create_time IS NULL',
  );
  final replyTextColumn = [
    'reply', 'reply_text', 'text',
  ].where(replyColumnNames.contains).firstOrNull;
  if (replyTextColumn != null && !replyColumnNames.contains('content')) {
    await db.execute(
      "UPDATE quote_replies SET content = $replyTextColumn WHERE content = ''",
    );
  }
  if (!replyColumnNames.contains('reply_id')) {
    await db.execute(
      'UPDATE quote_replies SET reply_id = rowid WHERE reply_id IS NULL',
    );
  }
}

class MigrationV7 extends Migration {
  @override
  int get targetVersion => 7;

  @override
  Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db, 'wishes', 'redeemed_at',
      'ALTER TABLE wishes ADD COLUMN redeemed_at TEXT',
    );
    await _addColumnIfMissing(
      db, 'hopes', 'redeemed_at',
      'ALTER TABLE hopes ADD COLUMN redeemed_at TEXT',
    );
    await _addColumnIfMissing(
      db, 'special_tasks', 'completed_at',
      'ALTER TABLE special_tasks ADD COLUMN completed_at TEXT',
    );
    await _ensureQuoteSchema(db);
    await InitDbData.insertQuoteSeedData(db);
    await db.execute('''
      UPDATE hopes SET status = '未进行' WHERE status IN ('待完成', '未开始')
    ''');
    await db.execute('''
      UPDATE hopes SET
        status = '已兑换',
        redeemed_at = COALESCE(
          (SELECT substr(create_time, 1, 10) FROM points
            WHERE source_type = 'hope'
              AND source_id = hopes.hope_id
              AND operation_type = '希望完成奖励'
            ORDER BY create_time DESC LIMIT 1),
          (SELECT MAX(progress_date) FROM hope_progress_logs
            WHERE hope_progress_logs.hope_id = hopes.hope_id),
          date('now','localtime')
        )
      WHERE status = '已完成'
    ''');
    await db.execute('''
      UPDATE wishes SET status = '待兑换'
      WHERE status = '已完成' AND current_points >= required_points
    ''');
    await db.execute('''
      UPDATE special_tasks
      SET completed_at = COALESCE(
        (SELECT create_time FROM points
          WHERE source_type = 'special_task'
            AND source_id = special_tasks.id
          ORDER BY create_time DESC LIMIT 1),
        end_time
      )
      WHERE status_tag = '已完成' AND completed_at IS NULL
    ''');
    await db.execute('''
      INSERT OR REPLACE INTO app_settings (key, value)
      VALUES ('personal_motto', '专注当下，慢慢成为想成为的人')
    ''');
  }
}

class MigrationV8 extends Migration {
  @override
  int get targetVersion => 8;

  @override
  Future<void> up(Database db) async {
    await _ensureQuoteSchema(db);
    await InitDbData.insertQuoteSeedData(db);
  }
}

class MigrationV9 extends Migration {
  @override
  int get targetVersion => 9;

  @override
  Future<void> up(Database db) async {
    await db.execute(TableSql.createAnniversaries);
  }
}

class MigrationV10 extends Migration {
  @override
  int get targetVersion => 10;

  @override
  Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db, 'special_tasks', 'is_deleted',
      'ALTER TABLE special_tasks ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db, 'daily_tasks', 'is_deleted',
      'ALTER TABLE daily_tasks ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
    );
  }
}

class MigrationV11 extends Migration {
  @override
  int get targetVersion => 11;

  @override
  Future<void> up(Database db) async {
    await db.execute(TableSql.createFinanceCategories);
    await db.execute(TableSql.createBudgetHistory);
    await InitDbData.insertFinanceCategorySeedData(db);
  }
}
