import 'package:flutter/material.dart';

/// 临时占位页面，未开发页面使用
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title页面（待补充业务内容）')),
    );
  }
}
