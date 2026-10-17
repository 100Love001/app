import 'package:app/stores/database/add_database.dart';

enum SearchScope { all, tags, tasks, wishes, hopes, finance, diaries, moods }

class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  Future<List<Map<String, Object?>>> search({
    required String keyword,
    SearchScope scope = SearchScope.all,
  }) async {
    final db = await AppDatabase.instance.database;
    // 必须先转义反斜杠本身，否则后续 % _ 产生的转义符会被二次解释。
    final escaped = keyword
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final pattern = '%$escaped%';
    final futures = <Future<List<Map<String, Object?>>>>[];

    if (scope == SearchScope.all || scope == SearchScope.tags) {
      for (final (table, name, type) in [
        ('tags', 'tag_name', '全局标签'),
        ('wish_tags', 'name', '愿望标签'),
        ('hope_tags', 'name', '希望标签'),
        ('special_task_tags', 'name', '特殊任务标签'),
        ('daily_task_tags', 'name', '日常任务标签'),
        ('mood_tag', 'name', '心情标签'),
      ]) {
        final descriptionColumn = table == 'tags'
            ? "COALESCE(tag_group, '')"
            : "COALESCE(remark, '')";
        futures.add(() async {
          final rows = await db.rawQuery(
            "SELECT $name AS title, $descriptionColumn AS description "
            "FROM $table WHERE $name LIKE ? ESCAPE '\\'",
            [pattern],
          );
          return rows.map((row) => {...row, 'result_type': type}).toList();
        }());
      }
    }
    if (scope == SearchScope.all || scope == SearchScope.tasks) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT special_tasks.id AS record_id,
            special_tasks.name AS title,
            COALESCE(special_tasks.content, special_tasks.remark, '') AS description,
            COALESCE(special_task_tags.name, '未分类') AS tag_name
          FROM special_tasks
          LEFT JOIN special_task_tags ON special_tasks.task_tag_id = special_task_tags.id
          WHERE special_tasks.is_deleted = 0 AND (
            special_tasks.name LIKE ? ESCAPE '\\' OR special_tasks.content LIKE ? ESCAPE '\\'
            OR special_tasks.remark LIKE ? ESCAPE '\\' OR special_task_tags.name LIKE ? ESCAPE '\\')
          ''',
          [pattern, pattern, pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '特殊任务'}).toList();
      }());
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT daily_tasks.id AS record_id,
            daily_tasks.name AS title,
            COALESCE(daily_tasks.content, daily_tasks.remark, '') AS description,
            COALESCE(daily_task_tags.name, '未分类') AS tag_name
          FROM daily_tasks
          LEFT JOIN daily_task_tags ON daily_tasks.task_tag_id = daily_task_tags.id
          WHERE daily_tasks.is_deleted = 0 AND (
            daily_tasks.name LIKE ? ESCAPE '\\' OR daily_tasks.content LIKE ? ESCAPE '\\'
            OR daily_tasks.remark LIKE ? ESCAPE '\\' OR daily_task_tags.name LIKE ? ESCAPE '\\')
          ''',
          [pattern, pattern, pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '日常任务'}).toList();
      }());
    }
    if (scope == SearchScope.all || scope == SearchScope.wishes) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT wishes.wish_id AS record_id,
            wishes.name AS title,
            COALESCE(wishes.content, wishes.note, '') AS description,
            COALESCE(wish_tags.name, '未分类') AS tag_name,
            wishes.status AS status
          FROM wishes LEFT JOIN wish_tags ON wishes.tag_id = wish_tags.id
          WHERE wishes.name LIKE ? ESCAPE '\\' OR wishes.content LIKE ? ESCAPE '\\'
            OR wishes.note LIKE ? ESCAPE '\\' OR wish_tags.name LIKE ? ESCAPE '\\'
          ''',
          [pattern, pattern, pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '愿望'}).toList();
      }());
    }
    if (scope == SearchScope.all || scope == SearchScope.hopes) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT hopes.hope_id AS record_id,
            hopes.name AS title,
            COALESCE(hopes.content, hopes.notes, '') AS description,
            COALESCE(hope_tags.name, '未分类') AS tag_name,
            hopes.status AS status
          FROM hopes LEFT JOIN hope_tags ON hopes.tag_id = hope_tags.id
          WHERE hopes.name LIKE ? ESCAPE '\\' OR hopes.content LIKE ? ESCAPE '\\'
            OR hopes.notes LIKE ? ESCAPE '\\' OR hope_tags.name LIKE ? ESCAPE '\\'
          ''',
          [pattern, pattern, pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '希望'}).toList();
      }());
    }
    if (scope == SearchScope.all || scope == SearchScope.finance) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT record_id, category AS title, COALESCE(remark, '') AS description,
            type AS status, record_date AS date, amount
          FROM income_expenses
          WHERE category LIKE ? ESCAPE '\\' OR remark LIKE ? ESCAPE '\\' OR type LIKE ? ESCAPE '\\'
            OR record_date LIKE ? ESCAPE '\\' OR CAST(amount AS TEXT) LIKE ? ESCAPE '\\'
          ''',
          [pattern, pattern, pattern, pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '财务'}).toList();
      }());
    }
    if (scope == SearchScope.all || scope == SearchScope.diaries) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT diaries.diary_id AS record_id,
            diaries.title AS title,
            COALESCE(diaries.content, '') AS description,
            diaries.book_type AS book_type,
            folders.folder_name AS tag_name
          FROM diaries LEFT JOIN folders ON diaries.folder_id = folders.folder_id
          WHERE diaries.title LIKE ? ESCAPE '\\' OR diaries.content LIKE ? ESCAPE '\\' OR folders.folder_name LIKE ? ESCAPE '\\'
          ''',
          [pattern, pattern, pattern],
        );
        // C2：全局搜索同时覆盖认知本/日记本，结果分别标注来源本子。
        return rows
            .map(
              (row) => {
                ...row,
                'result_type': row['book_type'] == 'diary' ? '日记本' : '认知本',
              },
            )
            .toList();
      }());
    }
    if (scope == SearchScope.all || scope == SearchScope.moods) {
      futures.add(() async {
        final rows = await db.rawQuery(
          '''
          SELECT mood_record.id AS record_id, mood_tag.name AS title,
            COALESCE(mood_record.reason, '') AS description,
            mood_record.record_date AS date
          FROM mood_record JOIN mood_tag ON mood_record.tag_id = mood_tag.id
          WHERE mood_tag.name LIKE ? ESCAPE '\\' OR mood_record.reason LIKE ? ESCAPE '\\'
          ''',
          [pattern, pattern],
        );
        return rows.map((row) => {...row, 'result_type': '心情'}).toList();
      }());
    }

    final results = await Future.wait(futures);
    return results.expand((list) => list).toList();
  }
}
