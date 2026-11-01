import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_app/core/chinese_numbers.dart';
import 'package:novel_app/core/startup_focus_binding.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/main.dart' show NovelApp;
import 'package:novel_app/presentation/shared/quick_capture/capture_button_prefs.dart';

/// 独立Web验收入口：正式应用和仓库，单独数据库；不打开用户的novel_app。
Future<void> main() async {
  StartupWidgetsBinding();
  final count = int.parse(Uri.base.queryParameters['chapters'] ?? '1000');
  if (count != 100 && count != 1000) throw ArgumentError('验收规模只支持100或1000章');
  final db = AppDatabase.forTesting(
    driftDatabase(
      name: 'easy_create_tree_qa_$count',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ),
  );
  // 刷新保留此前交互结果；只在此独立数据库尚无小说时生成一次。
  if (await db.select(db.novels).getSingleOrNull() == null) {
    await db.transaction(() async {
      await db
          .into(db.novels)
          .insert(
            NovelsCompanion.insert(
              id: const Value(1),
              title: '规模验收$count',
              planet: 'earth',
              sortOrder: 0,
              createdAt: DateTime(2026, 11, 1),
            ),
          );
      await db.batch((batch) {
        batch.insertAll(
          db.chapters,
          List.generate(
            count,
            (index) => ChaptersCompanion.insert(
              id: Value(index + 1),
              novelId: 1,
              title: defaultChapterTitle(index),
              sortOrder: index,
            ),
          ),
        );
        batch.insertAll(db.sections, [
          for (final chapter in [1, count ~/ 2, count])
            for (var index = 0; index < 2; index++)
              SectionsCompanion.insert(
                chapterId: chapter,
                title: defaultSectionTitle(index),
                sortOrder: index,
              ),
        ]);
      });
    });
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const NovelApp(),
    ),
  );
}
