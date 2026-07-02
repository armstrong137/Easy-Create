import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 应用唯一数据库（纯本地 SQLite，无账号无后端）
@DriftDatabase(tables: [Novels, Chapters, Sections, Inspirations])
class AppDatabase extends _$AppDatabase {
  /// 正式运行用：drift_flutter 自动选择双端本地文件位置
  AppDatabase() : super(_openConnection());

  /// 测试用：允许注入内存数据库等任意执行器
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // 开启外键约束：级联删除（删小说→删章→删节）与
          // 删节时灵感放回魔毯（section_id 置 NULL）都依赖它
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'novel_app');
  }
}
