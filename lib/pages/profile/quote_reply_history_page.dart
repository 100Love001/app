import 'package:app/stores/home/quote_repository.dart';
import 'package:flutter/material.dart';

class QuoteReplyHistoryPage extends StatefulWidget {
  const QuoteReplyHistoryPage({super.key});

  @override
  State<QuoteReplyHistoryPage> createState() => _QuoteReplyHistoryPageState();
}

class _QuoteReplyHistoryPageState extends State<QuoteReplyHistoryPage> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _replies = [];

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  Future<void> _loadReplies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final replies = await QuoteRepository.instance.allReplies();
      if (!mounted) return;
      setState(() {
        _replies = replies;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语录回复')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('回复历史读取失败：$_error'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _loadReplies,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : _replies.isEmpty
          ? const Center(child: Text('还没有语录回复'))
          : RefreshIndicator(
              onRefresh: _loadReplies,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _replies.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final reply = _replies[index];
                  final quote = reply['quote_content'] as String?;
                  final author = reply['quote_author'] as String?;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reply['content'] as String,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (quote != null) ...[
                            const Divider(height: 24),
                            Text(
                              '“$quote”${author?.isNotEmpty == true ? ' — $author' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            reply['create_time'] as String,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
