import 'dart:math';

import 'package:app/stores/database/add_database.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/foundation.dart';

class QuoteRepository extends ChangeNotifier {
  QuoteRepository._();

  static final instance = QuoteRepository._();

  Future<Map<String, dynamic>> randomQuote() async {
    final countRows = await AppDatabase.instance.rawQuery(
      'SELECT COUNT(*) AS count FROM quotes',
    );
    final total = toInt(countRows.first['count']);
    if (total == 0) throw StateError('今日语录库为空');

    final offset = Random().nextInt(total);
    final rows = await AppDatabase.instance.rawQuery(
      'SELECT * FROM quotes LIMIT 1 OFFSET ?',
      [offset],
    );
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> replies(int quoteId) =>
      AppDatabase.instance.rawQuery(
        'SELECT * FROM quote_replies WHERE quote_id = ? '
        'ORDER BY create_time DESC, reply_id DESC',
        [quoteId],
      );

  Future<List<Map<String, dynamic>>> allReplies() =>
      AppDatabase.instance.rawQuery('''
        SELECT quote_replies.reply_id, quote_replies.content,
          quote_replies.create_time, quotes.content AS quote_content,
          quotes.author AS quote_author
        FROM quote_replies
        LEFT JOIN quotes ON quotes.quote_id = quote_replies.quote_id
        ORDER BY quote_replies.create_time DESC, quote_replies.reply_id DESC
      ''');

  Future<List<Map<String, dynamic>>> repliesForQuoteContent(
    String quoteContent,
  ) => AppDatabase.instance.rawQuery(
    '''
      SELECT quote_replies.reply_id, quote_replies.content,
        quote_replies.create_time
      FROM quote_replies
      JOIN quotes ON quotes.quote_id = quote_replies.quote_id
      WHERE quotes.content = ?
      ORDER BY quote_replies.create_time DESC, quote_replies.reply_id DESC
    ''',
    [quoteContent],
  );

  Future<Map<String, dynamic>> like(int quoteId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((transaction) async {
      final changed = await transaction.rawUpdate(
        'UPDATE quotes SET like_count = like_count + 1 WHERE quote_id = ?',
        [quoteId],
      );
      if (changed != 1) throw StateError('语录不存在');
      final rows = await transaction.query(
        'quotes',
        where: 'quote_id = ?',
        whereArgs: [quoteId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('语录更新后无法读取');
      return rows.first;
    });
  }

  Future<void> addReply(int quoteId, String content) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('回复内容不能为空');
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final quote = await transaction.query(
        'quotes',
        columns: ['quote_id'],
        where: 'quote_id = ?',
        whereArgs: [quoteId],
        limit: 1,
      );
      if (quote.isEmpty) throw StateError('语录不存在');
      await transaction.insert('quote_replies', {
        'quote_id': quoteId,
        'content': text,
        'create_time': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> addReplyForQuoteContent(
    String quoteContent,
    String content,
  ) async {
    final text = content.trim();
    if (text.isEmpty) throw ArgumentError('回复内容不能为空');
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final quotes = await transaction.rawQuery(
        'SELECT quote_id FROM quotes WHERE content = ? LIMIT 1',
        [quoteContent],
      );
      if (quotes.isEmpty) throw StateError('语录不存在');
      await transaction.insert('quote_replies', {
        'quote_id': toInt(quotes.first['quote_id']),
        'content': text,
        'create_time': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Map<String, dynamic>>> allQuotes() =>
      AppDatabase.instance.rawQuery(
        'SELECT * FROM quotes ORDER BY create_time DESC, quote_id DESC',
      );

  Future<void> saveQuote({
    int? quoteId,
    required String content,
    String? author,
  }) async {
    final text = content.trim();
    final byline = author?.trim() ?? '';
    if (text.isEmpty) throw ArgumentError('语录内容不能为空');
    final db = await AppDatabase.instance.database;
    if (quoteId == null) {
      await db.insert('quotes', {'content': text, 'author': byline});
    } else {
      final changed = await db.update(
        'quotes',
        {'content': text, 'author': byline},
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );
      if (changed != 1) throw StateError('语录不存在');
    }
    notifyListeners();
  }

  Future<void> deleteQuote(int quoteId) async {
    final db = await AppDatabase.instance.database;
    final changed = await db.delete(
      'quotes',
      where: 'quote_id = ?',
      whereArgs: [quoteId],
    );
    if (changed != 1) throw StateError('语录不存在');
    notifyListeners();
  }
}
