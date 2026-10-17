import 'package:app/stores/database/add_database.dart';

class AnniversaryRepository {
  AnniversaryRepository._();
  static final AnniversaryRepository instance = AnniversaryRepository._();

  Future<List<Map<String, Object?>>> loadAll() =>
      AppDatabase.instance.rawQuery(
        'SELECT * FROM anniversaries ORDER BY event_date',
      );

  Future<int> save(Map<String, Object?> values) async {
    final db = await AppDatabase.instance.database;
    final id = values['anniversary_id'] as int?;
    if (id == null) {
      return db.insert('anniversaries', values);
    }
    await db.update(
      'anniversaries',
      values,
      where: 'anniversary_id = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<int> delete(int anniversaryId) => AppDatabase.instance.delete(
    'anniversaries',
    where: 'anniversary_id = ?',
    whereArgs: [anniversaryId],
  );
}
