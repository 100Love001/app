import 'package:app/stores/database/add_database.dart';

class FinanceCategoryRepository {
  FinanceCategoryRepository._();
  static final FinanceCategoryRepository instance =
      FinanceCategoryRepository._();

  Future<List<Map<String, dynamic>>> loadAll() =>
      AppDatabase.instance.rawQuery(
        'SELECT * FROM finance_categories ORDER BY type, is_system DESC, id',
      );

  Future<List<Map<String, dynamic>>> loadExpenseCategories() =>
      AppDatabase.instance.rawQuery(
        '''
        SELECT * FROM finance_categories
        WHERE type = '支出'
        ORDER BY is_system DESC, id
        ''',
      );

  Future<int> add({
    required String type,
    required String name,
    String periodType = 'none',
  }) =>
      AppDatabase.instance.insert('finance_categories', {
        'type': type,
        'name': name,
        'period_type': type == '支出' ? periodType : 'none',
      });

  /// 修改分类结算周期（收入分类恒为 none）。
  Future<void> updatePeriod({
    required int id,
    required String type,
    required String periodType,
  }) =>
      AppDatabase.instance.update(
        'finance_categories',
        {'period_type': type == '支出' ? periodType : 'none'},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 设置周期预算。
  Future<void> updateBudget({required int id, required double budget}) =>
      AppDatabase.instance.update(
        'finance_categories',
        {'budget': budget},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 设置积分兑换比例：[balanceRate]=结余每元兑换积分，
  /// [overageRate]=超支每元扣除积分（均为非负整数，0=该方向不参与积分）。
  Future<void> updateRates({
    required int id,
    required int balanceRate,
    required int overageRate,
  }) =>
      AppDatabase.instance.update(
        'finance_categories',
        {'balance_rate': balanceRate, 'overage_rate': overageRate},
        where: 'id = ?',
        whereArgs: [id],
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
  /// category_settlements 是按名称留存的历史结算，同样保留。
  Future<void> delete(int id) => AppDatabase.instance.delete(
    'finance_categories',
    where: 'id = ?',
    whereArgs: [id],
  );
}
