import 'package:app/constants/app_constants.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'migration.dart';

class MigrationV12 extends Migration {
  @override
  int get targetVersion => 12;

  @override
  Future<void> up(Database db) async {
    // 归一旧版愿望状态字面值 '待攒积分'：
    // 已有积分投入的归入“进行中”，从未投入的归入“未开始”。
    await db.rawUpdate(
      '''
      UPDATE wishes
      SET status = CASE
        WHEN current_points > 0 THEN ?
        ELSE ?
      END
      WHERE status = ?
      ''',
      [
        WishStatus.inProgress,
        WishStatus.notStarted,
        WishStatus.legacyPendingPoints,
      ],
    );
  }
}
