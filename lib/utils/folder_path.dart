/// 文件夹路径工具
class FolderPathUtil {
  const FolderPathUtil._();

  /// 根据文件夹 ID 和文件夹列表，构建完整的文件夹路径
  /// 返回格式如 "父文件夹 / 子文件夹"
  static String buildPath(
    int folderId,
    List<Map<String, dynamic>> folders,
  ) {
    final byId = {for (final folder in folders) folder['folder_id']: folder};
    final path = <String>[];
    var current = byId[folderId];
    while (current != null) {
      path.insert(0, current['folder_name'] as String);
      final parentId = current['parent_id'] as int?;
      current = parentId == null ? null : byId[parentId];
    }
    return path.join(' / ');
  }

  /// 计算文件夹的深度（根文件夹为 0）
  static int depth(
    Map<String, dynamic> folder,
    List<Map<String, dynamic>> folders,
  ) {
    final byId = {for (final f in folders) f['folder_id']: f};
    var depth = 0;
    var parentId = folder['parent_id'] as int?;
    final visited = <int>{folder['folder_id'] as int};
    while (parentId != null) {
      if (!visited.add(parentId)) break;
      depth++;
      final parent = byId[parentId];
      parentId = parent?['parent_id'] as int?;
    }
    return depth;
  }
}
