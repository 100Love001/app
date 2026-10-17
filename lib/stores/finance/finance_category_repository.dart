import 'package:app/stores/database/add_database.dart';

class FinanceCategoryRepository {
  FinanceCategoryRepository._();
  static final FinanceCategoryRepository instance =
      FinanceCategoryRepository._();

  Future<List<Map<String, dynamic>>> loadAll() =>
      AppDatabase.instance.rawQuery(
        'SELECT * FROM finance_categories ORDER BY is_system DESC, name',
      );

  Future<int> add({required String type, required String name}) =>
      AppDatabase.instance.insert(
        'finance_categories',
        {'type': type, 'name': name},
      );

  Future<void> rename({
    required int id,
    required String newName,
    required String oldName,
    required String type,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      await transaction.update(
        'finance_categories',
        {'name': newName},
        where: 'id = ?',
        whereArgs: [id],
      );
      await transaction.update(
        'income_expenses',
        {'category': newName},
        where: 'type = ? AND category = ?',
        whereArgs: [type, oldName],
      );
    });
  }

  /// 仅删除分类本身。income_expenses.category 是无外键的文本名称，
  /// 删除分类后历史账单保留原分类名称（与删除确认弹窗的承诺一致）。
  Future<void> delete(int id) => AppDatabase.instance.delete(
    'finance_categories',
    where: 'id = ?',
    whereArgs: [id],
  );
}
