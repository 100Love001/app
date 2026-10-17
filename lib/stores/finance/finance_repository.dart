import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/database/points_service.dart';

class FinanceRepository {
  FinanceRepository._();
  static final FinanceRepository instance = FinanceRepository._();

  Future<List<Map<String, dynamic>>> loadRecords() =>
      AppDatabase.instance.rawQuery('''
        SELECT record_id, type, category, amount, remark, points_deducted,
               record_date, create_time
        FROM income_expenses ORDER BY record_date DESC, record_id DESC
      ''');

  Future<List<Map<String, dynamic>>> loadCategories() async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'finance_categories',
      orderBy: 'type, is_system DESC, name',
    );
  }

  Future<List<Map<String, dynamic>>> loadPointRecords() =>
      AppDatabase.instance.rawQuery(
        // 历史数据 create_time 可能是 'YYYY-MM-DD HH:MM:SS' 或 ISO8601 带 T，
        // 空格(0x20) 与 T(0x54) 直接排序会错位，这里归一后再排。
        // source_name 按 source_type+source_id 实时反查，对象改名后
        // 历史流水也能显示新名称。
        '''
        SELECT p.*, ${PointsService.sourceNameColumn} AS source_name
        FROM points p
        ORDER BY REPLACE(p.create_time, 'T', ' ') DESC, p.points_id DESC
        ''',
      );

  Future<List<Map<String, dynamic>>> loadBudgetLimits(List<String> keys) async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (${List.filled(keys.length, '?').join(', ')})',
      whereArgs: keys,
    );
  }

  Future<List<Map<String, dynamic>>> loadMonthlyBudgetHistory({
    required String startDate,
    required String endDate,
  }) =>
      AppDatabase.instance.rawQuery('''
        SELECT budget_date, budget_amount
        FROM budget_history
        WHERE budget_date >= ? AND budget_date < ?
        ORDER BY budget_date DESC
      ''', [startDate, endDate]);

  Future<void> saveRecord(Map<String, dynamic> values, {int? id}) async {
    if (id == null) {
      await AppDatabase.instance.insert('income_expenses', values);
    } else {
      await AppDatabase.instance.update(
        'income_expenses',
        values,
        where: 'record_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int> deleteRecord(int id) => AppDatabase.instance.delete(
    'income_expenses',
    where: 'record_id = ?',
    whereArgs: [id],
  );

  Future<void> recordBudgetSnapshot({
    required String dateKey,
    required double amount,
    required String nowIso,
  }) =>
      AppDatabase.instance.rawExecute(
        'INSERT OR IGNORE INTO budget_history (budget_date, budget_amount, update_time) VALUES (?, ?, ?)',
        [dateKey, amount, nowIso],
      );

  Future<List<Map<String, dynamic>>> loadFoodExchangeLastDate() =>
      AppDatabase.instance.rawQuery(
        'SELECT MAX(exchange_date) AS last_date FROM food_point_exchanges',
      );

  Future<double> loadDailyFoodBudget() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['daily_food_budget'],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    return double.tryParse(rows.first['value'] as String) ?? 0.0;
  }
}
