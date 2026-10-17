import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 通用 CSV 导出工具：生成带 UTF-8 BOM 的 CSV 文件并调起系统分享。
/// 带 BOM 是为了让 Excel 直接打开时中文不乱码。
class CsvExporter {
  const CsvExporter._();

  /// 单元格转义：含逗号/引号/换行的字段加引号包裹，内部引号翻倍。
  static String escape(Object? value) {
    final text = '${value ?? ''}';
    final needsQuote =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    final escaped = text.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  /// 组装完整 CSV 文本（首行 \uFEFF BOM + CRLF 行尾）。
  static String build(List<List<Object?>> rows) => '\uFEFF'
      '${rows.map((row) => row.map(escape).join(',')).join('\r\n')}';

  /// 把 [rows] 写成临时目录下的 CSV 文件并调起系统分享面板。
  /// 文件名建议含时间戳，避免同名覆盖历史导出。
  static Future<void> shareCsv({
    required String fileName,
    required List<List<Object?>> rows,
    required String subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(build(rows), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: subject,
        text: subject,
      ),
    );
  }

  /// 历史流水 create_time 可能是 'YYYY-MM-DD HH:MM:SS' 或 ISO8601 带 T，
  /// 统一替换为空格便于在 Excel 中筛选。
  static String normalizeTime(Object? value) =>
      '${value ?? ''}'.replaceFirst('T', ' ');
}
