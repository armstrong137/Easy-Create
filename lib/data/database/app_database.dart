import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 应用唯一数据库（纯本地 SQLite，无账号无后端）
@DriftDatabase(tables: [Novels, Chapters, Sections, Inspirations])
class AppDatabase extends _$AppDatabase {
  /// 正式运行用：native 自动选本地文件；Web 显式指定 wasm/worker 运行时
  AppDatabase() : super(_openConnection());

  /// 测试用：允许注入内存数据库等任意执行器
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v2：灵感新增 chapter_id（可直接挂靠到章下）
      if (from < 2) {
        await m.addColumn(inspirations, inspirations.chapterId);
      }
    },
    beforeOpen: (details) async {
      // 开启外键约束：级联删除（删小说→删章→删节）与
      // 删节/删章时灵感放回魔毯（section_id / chapter_id 置 NULL）都依赖它
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'novel_app',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
