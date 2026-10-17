import 'package:app/stores/home/quote_repository.dart';
import 'package:app/utils/dialog.dart';
import 'package:flutter/material.dart';

class QuoteManagementPage extends StatefulWidget {
  const QuoteManagementPage({super.key});

  @override
  State<QuoteManagementPage> createState() => _QuoteManagementPageState();
}

class _QuoteManagementPageState extends State<QuoteManagementPage> {
  List<Map<String, dynamic>> _quotes = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quotes = await QuoteRepository.instance.allQuotes();
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _editQuote([Map<String, dynamic>? quote]) async {
    final contentController = TextEditingController(
      text: quote?['content'] as String? ?? '',
    );
    final authorController = TextEditingController(
      text: quote?['author'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<(String, String)?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(quote == null ? '添加今日语录' : '编辑语录'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: contentController,
                autofocus: true,
                maxLength: 300,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '语录内容'),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请输入语录内容' : null,
              ),
              TextFormField(
                controller: authorController,
                maxLength: 60,
                decoration: const InputDecoration(labelText: '来源 / 作者（选填）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(dialogContext, (
                  contentController.text,
                  authorController.text,
                ));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    contentController.dispose();
    authorController.dispose();
    if (result == null) return;
    try {
      await QuoteRepository.instance.saveQuote(
        quoteId: quote?['quote_id'] as int?,
        content: result.$1,
        author: result.$2,
      );
      await _loadQuotes();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存语录失败：$error')));
      }
    }
  }

  Future<void> _deleteQuote(Map<String, dynamic> quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除语录'),
        content: const Text('删除后，这条语录将不再参与首页今日语录的抽取。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await QuoteRepository.instance.deleteQuote(quote['quote_id'] as int);
      await _loadQuotes();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除语录失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日语录'),
        actions: [
          IconButton(
            tooltip: '添加语录',
            onPressed: () => _editQuote(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('语录读取失败：$_error'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _loadQuotes, child: const Text('重试')),
                ],
              ),
            )
          : _quotes.isEmpty
          ? const Center(child: Text('还没有语录，点击右上角添加'))
          : RefreshIndicator(
              onRefresh: _loadQuotes,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: _quotes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final quote = _quotes[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(quote['content'] as String),
                                if ((quote['author'] as String?)?.isNotEmpty ==
                                    true) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    '— ${quote['author']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _editQuote(quote);
                              } else {
                                _deleteQuote(quote);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editQuote(),
        icon: const Icon(Icons.add),
        label: const Text('添加语录'),
      ),
    );
  }
}
