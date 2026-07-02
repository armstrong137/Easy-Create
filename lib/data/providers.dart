import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'repositories/inspiration_repository.dart';
import 'repositories/novel_repository.dart';

/// 应用唯一数据库实例（测试中可 override 为内存库）
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 大纲结构仓库（小说/章/节）
final novelRepositoryProvider = Provider<NovelRepository>(
  (ref) => NovelRepository(ref.watch(appDatabaseProvider)),
);

/// 灵感仓库（生命周期四流转）
final inspirationRepositoryProvider = Provider<InspirationRepository>(
  (ref) => InspirationRepository(ref.watch(appDatabaseProvider)),
);
