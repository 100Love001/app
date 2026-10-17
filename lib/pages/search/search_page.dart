import 'dart:async';
import 'dart:convert';

import 'package:app/stores/database/add_database.dart';
import 'package:app/stores/search/search_repository.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  SearchScope _scope = SearchScope.all;
  List<Map<String, Object?>> _results = [];
  bool _loading = false;
  Object? _error;

  static const _scopes = [
    (SearchScope.all, '全部'),
    (SearchScope.tags, '标签'),
    (SearchScope.tasks, '任务'),
    (SearchScope.wishes, '愿望'),
    (SearchScope.hopes, '希望'),
    (SearchScope.finance, '财务'),
    (SearchScope.diaries, '日记'),
    (SearchScope.moods, '心情'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _requestId++;
    _controller.dispose();
    super.dispose();
  }

  /// C1：日记正文可能以 delta JSON 存储，搜索展示前需转回纯文本；
  /// 解析失败（损坏内容/历史纯文本）时回退显示原文。
  static String _plainDiaryText(Object? raw, {String? format}) {
    final content = raw as String? ?? '';
    if (content.isEmpty) return '';
    final trimmed = content.trimLeft();
    final looksLikeDelta = format == 'delta' ||
        (format == null && trimmed.startsWith('['));
    if (!looksLikeDelta) return content;
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return Document.fromJson(decoded).toPlainText().trim();
      }
    } catch (_) {
      // 内容损坏时回退为原文。
    }
    return content;
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final requestId = ++_requestId;
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _search(requestId),
    );
  }

  Future<void> _search([int? requestedId]) async {
    final requestId = requestedId ?? ++_requestId;
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await SearchRepository.instance.search(
        keyword: keyword,
        scope: _scope,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('全局搜索')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _scheduleSearch,
            onSubmitted: (_) => _scheduleSearch(_controller.text),
            decoration: InputDecoration(
              hintText: '搜索名称、内容或标签',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _controller.clear();
                  _scheduleSearch('');
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              for (final (scope, label) in _scopes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _scope == scope,
                    onSelected: (_) {
                      setState(() => _scope = scope);
                      _debounce?.cancel();
                      ++_requestId;
                      _search();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('搜索失败：$_error'))
              : _controller.text.trim().isEmpty
              ? const Center(child: Text('输入关键词，搜索标签、任务、清单或记录'))
              : _results.isEmpty
              ? const Center(child: Text('没有找到相关内容'))
              : ListView.builder(
                  itemCount: _results.length,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemBuilder: (context, index) {
                    final row = _results[index];
                    final type = row['result_type'] as String;
                    final isDiaryResult = type == '认知本' || type == '日记本';
                    final description = isDiaryResult
                        ? _plainDiaryText(row['description'])
                        : (row['description'] as String? ?? '');
                    final details = <String>[
                      if ((row['tag_name'] as String?)?.isNotEmpty == true)
                        row['tag_name'] as String,
                      if ((row['status'] as String?)?.isNotEmpty == true)
                        row['status'] as String,
                      if ((row['date'] as String?)?.isNotEmpty == true)
                        row['date'] as String,
                      if (row['amount'] != null) '¥${row['amount']}',
                    ];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(_iconFor(type), size: 20),
                        ),
                        title: Text(row['title'] as String? ?? ''),
                        subtitle: Text(
                          [
                            type,
                            if (details.isNotEmpty) details.join(' · '),
                            if (description.isNotEmpty) description,
                          ].join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _showDetail(row),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Future<void> _showDetail(Map<String, Object?> row) async {
    final type = row['result_type'] as String;
    final title = row['title'] as String? ?? '';
    final description = row['description'] as String? ?? '';
    final recordId = row['record_id'];

    String content = (type == '认知本' || type == '日记本')
        ? _plainDiaryText(description)
        : description;
    String? tag;
    String? status;
    String? date;
    double? amount;

    if (recordId != null) {
      try {
        final detail = await _loadRecord(type, recordId as int);
        if (detail != null) {
          final rawContent = detail['content'] as String? ?? description;
          content = (type == '认知本' || type == '日记本')
              ? _plainDiaryText(
                  rawContent,
                  format: detail['content_format'] as String?,
                )
              : rawContent;
          tag = detail['tag'] as String?;
          status = detail['status'] as String?;
          date = detail['date'] as String?;
          // REAL 列在历史数据中可能以 int 落库，用 toDouble 统一转换避免强转异常。
          amount = detail['amount'] == null
              ? null
              : toDouble(detail['amount']);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tag != null || status != null || date != null || amount != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      [
                        type,
                        ?tag,
                        ?status,
                        ?date,
                        if (amount != null) '¥$amount',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (content.isNotEmpty) Text(content),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, Object?>?> _loadRecord(String type, int id) async {
    return switch (type) {
      '特殊任务' => _loadSpecialTask(id),
      '日常任务' => _loadDailyTask(id),
      '愿望' => _loadWish(id),
      '希望' => _loadHope(id),
      '财务' => _loadFinance(id),
      '日记' || '认知本' || '日记本' => _loadDiary(id),
      '心情' => _loadMood(id),
      _ => null,
    };
  }

  Future<Map<String, Object?>?> _loadSpecialTask(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(special_tasks.content, special_tasks.remark, '') AS content,
        COALESCE(special_task_tags.name, '未分类') AS tag
      FROM special_tasks
      LEFT JOIN special_task_tags ON special_tasks.task_tag_id = special_task_tags.id
      WHERE special_tasks.id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _loadDailyTask(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(daily_tasks.content, daily_tasks.remark, '') AS content,
        COALESCE(daily_task_tags.name, '未分类') AS tag
      FROM daily_tasks
      LEFT JOIN daily_task_tags ON daily_tasks.task_tag_id = daily_task_tags.id
      WHERE daily_tasks.id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _loadWish(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(wishes.content, wishes.note, '') AS content,
        COALESCE(wish_tags.name, '未分类') AS tag,
        wishes.status AS status
      FROM wishes
      LEFT JOIN wish_tags ON wishes.tag_id = wish_tags.id
      WHERE wishes.wish_id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _loadHope(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(hopes.content, hopes.notes, '') AS content,
        COALESCE(hope_tags.name, '未分类') AS tag,
        hopes.status AS status
      FROM hopes
      LEFT JOIN hope_tags ON hopes.tag_id = hope_tags.id
      WHERE hopes.hope_id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _loadFinance(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'income_expenses',
      where: 'record_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'content': row['remark'] ?? '',
      'tag': row['category'] ?? '',
      'status': row['type'] ?? '',
      'date': row['record_date'] ?? '',
      'amount': row['amount'],
    };
  }

  Future<Map<String, Object?>?> _loadDiary(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(diaries.content, '') AS content,
        diaries.content_format AS content_format,
        folders.folder_name AS tag
      FROM diaries
      LEFT JOIN folders ON diaries.folder_id = folders.folder_id
      WHERE diaries.diary_id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _loadMood(int id) async {
    final rows = await AppDatabase.instance.rawQuery(
      '''
      SELECT COALESCE(mood_record.reason, '') AS content,
        mood_tag.name AS tag,
        mood_record.record_date AS date
      FROM mood_record
      JOIN mood_tag ON mood_record.tag_id = mood_tag.id
      WHERE mood_record.id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  IconData _iconFor(String type) => switch (type) {
    '财务' => Icons.account_balance_wallet_outlined,
    '希望' => Icons.emoji_events_outlined,
    '愿望' => Icons.card_giftcard_outlined,
    '心情' || '心情标签' => Icons.mood_outlined,
    '日记' || '认知本' || '日记本' => Icons.menu_book_outlined,
    '特殊任务' || '日常任务' => Icons.task_alt_outlined,
    _ => Icons.sell_outlined,
  };
}
