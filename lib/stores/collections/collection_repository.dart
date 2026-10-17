import 'package:app/constants/app_constants.dart';
import 'package:app/stores/database/add_database.dart';

class CollectionRepository {
  CollectionRepository._();
  static final CollectionRepository instance = CollectionRepository._();

  Future<List<Map<String, dynamic>>> loadWishes() =>
      AppDatabase.instance.rawQuery('''
        SELECT wishes.*, wish_tags.name AS tag_name
        FROM wishes LEFT JOIN wish_tags ON wishes.tag_id = wish_tags.id
        ORDER BY desire DESC, wish_id DESC
      ''');

  Future<List<Map<String, dynamic>>> loadHopes() =>
      AppDatabase.instance.rawQuery('''
        SELECT hopes.*, hope_tags.name AS tag_name
        FROM hopes LEFT JOIN hope_tags ON hopes.tag_id = hope_tags.id
        ORDER BY desire DESC, hope_id DESC
      ''');

  /// C3：问题清单。待解决在前、已解决沉底，组内按录入时间倒序。
  Future<List<Map<String, dynamic>>> loadProblems() =>
      AppDatabase.instance.rawQuery('''
        SELECT * FROM problems
        ORDER BY CASE status WHEN '待解决' THEN 0 ELSE 1 END,
                 sort, problem_id DESC
      ''');

  Future<int> saveProblem(Map<String, dynamic> values, {int? id}) async {
    final db = await AppDatabase.instance.database;
    if (id == null) {
      return db.insert('problems', {
        ...values,
        'status': '待解决',
        'create_time': DateTime.now().toIso8601String(),
        'update_time': DateTime.now().toIso8601String(),
      });
    }
    await db.update(
      'problems',
      {...values, 'update_time': DateTime.now().toIso8601String()},
      where: 'problem_id = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<void> setProblemResolved(
    int id, {
    required bool resolved,
    String solutionNote = '',
  }) =>
      AppDatabase.instance.update(
        'problems',
        {
          'status': resolved ? '已解决' : '待解决',
          'solution_note': solutionNote,
          'resolved_at': resolved ? DateTime.now().toIso8601String() : null,
          'update_time': DateTime.now().toIso8601String(),
        },
        where: 'problem_id = ?',
        whereArgs: [id],
      );

  Future<int> deleteProblem(int id) => AppDatabase.instance.delete(
    'problems',
    where: 'problem_id = ?',
    whereArgs: [id],
  );

  /// C2：[bookType] 为 cognition（认知本）或 diary（日记本）。
  Future<List<Map<String, dynamic>>> loadDiaries({
    required String bookType,
  }) =>
      AppDatabase.instance.rawQuery('''
        SELECT diaries.*, folders.folder_name
        FROM diaries LEFT JOIN folders ON diaries.folder_id = folders.folder_id
        WHERE diaries.book_type = ?
        ORDER BY diaries.update_time DESC
      ''', [bookType]);

  /// 读取文件夹；[bookType] 为 null 时返回全部本子的文件夹。
  Future<List<Map<String, dynamic>>> loadFolders({String? bookType}) async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'folders',
      columns: ['folder_id', 'parent_id', 'folder_name', 'book_type'],
      where: bookType == null ? null : 'book_type = ?',
      whereArgs: bookType == null ? null : [bookType],
      orderBy: 'sort, folder_name',
    );
  }

  /// C2：新建文件夹（归属于指定本子）。
  Future<int> createFolder({
    required String name,
    required String bookType,
    int? parentId,
    int? sort,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.insert('folders', {
      'folder_name': name,
      'book_type': bookType,
      'parent_id': ?parentId,
      'sort': sort ?? 0,
    });
  }

  Future<List<Map<String, dynamic>>> loadTags(String table) =>
      AppDatabase.instance.rawQuery(
        'SELECT id, name FROM $table ORDER BY name',
      );

  Future<void> addTag(String table, String name) =>
      AppDatabase.instance.rawExecute(
        'INSERT OR IGNORE INTO $table (name) VALUES (?)',
        [name],
      );

  Future<void> saveWish(Map<String, dynamic> values, {int? id}) async {
    final db = await AppDatabase.instance.database;
    if (id == null) {
      await db.insert('wishes', {
        ...values,
        'current_points': 0,
        'status': WishStatus.notStarted,
      });
    } else {
      await db.update(
        'wishes',
        {...values, 'update_time': DateTime.now().toIso8601String()},
        where: 'wish_id = ?',
        whereArgs: [id],
      );
    }
  }

  /// 新建时返回新希望的 hope_id；编辑时返回传入的 id。
  Future<int> saveHope(Map<String, dynamic> values, {int? id}) async {
    final db = await AppDatabase.instance.database;
    if (id == null) {
      return db.insert('hopes', {
        ...values,
        'progress': 0,
        'status': '未进行',
      });
    }
    await db.update(
      'hopes',
      {...values, 'update_time': DateTime.now().toIso8601String()},
      where: 'hope_id = ?',
      whereArgs: [id],
    );
    return id;
  }

  /// D1：分步任务 CRUD。
  Future<List<Map<String, dynamic>>> loadHopeSteps(int hopeId) async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'hope_steps',
      where: 'hope_id = ?',
      whereArgs: [hopeId],
      orderBy: 'sort, step_id',
    );
  }

  Future<int> saveHopeStep(Map<String, dynamic> values, {int? id}) async {
    final db = await AppDatabase.instance.database;
    if (id == null) {
      return db.insert('hope_steps', {
        ...values,
        'status': '未进行',
        'create_time': DateTime.now().toIso8601String(),
        'update_time': DateTime.now().toIso8601String(),
      });
    }
    await db.update(
      'hope_steps',
      {...values, 'update_time': DateTime.now().toIso8601String()},
      where: 'step_id = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<int> deleteHopeStep(int stepId) => AppDatabase.instance.delete(
    'hope_steps',
    where: 'step_id = ?',
    whereArgs: [stepId],
  );

  Future<void> saveDiary(Map<String, dynamic> values, {int? id}) async {
    final db = await AppDatabase.instance.database;
    if (id == null) {
      await db.insert('diaries', values);
    } else {
      await db.update(
        'diaries',
        values,
        where: 'diary_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int> deleteDiary(int id) => AppDatabase.instance.delete(
    'diaries',
    where: 'diary_id = ?',
    whereArgs: [id],
  );

  Future<void> moveDiary(int diaryId, int? folderId) =>
      AppDatabase.instance.update(
        'diaries',
        {'folder_id': folderId},
        where: 'diary_id = ?',
        whereArgs: [diaryId],
      );

  Future<void> addDesire({
    required String itemType,
    required int itemId,
    required String dateKey,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'desire_logs',
        where: 'item_type = ? AND item_id = ? AND desire_date = ?',
        whereArgs: [itemType, itemId, dateKey],
        limit: 1,
      );
      if (existing.isNotEmpty) throw StateError('今天已经增加过渴望度');
      final table = itemType == 'wish' ? 'wishes' : 'hopes';
      final idColumn = itemType == 'wish' ? 'wish_id' : 'hope_id';
      final itemRows = await transaction.query(
        table,
        columns: ['status'],
        where: '$idColumn = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (itemRows.isEmpty || itemRows.first['status'] == '已兑换') {
        throw StateError('已兑换的项目不能增加渴望度');
      }
      await transaction.insert('desire_logs', {
        'item_type': itemType,
        'item_id': itemId,
        'desire_date': dateKey,
        'amount': 1,
      });
      await transaction.rawUpdate(
        'UPDATE $table SET desire = desire + 1 WHERE $idColumn = ?',
        [itemId],
      );
    });
  }
}
