import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/outline_page.dart';
import 'package:novel_app/presentation/outline/pencil_tree_painter.dart';

/// 阶段四·1：大纲页渲染 smoke（大纲流一律 override，勿进真 drift 流）
void main() {
  Future<void> pumpOutline(
      WidgetTester tester, List<OutlineChapter> outline) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          outlineProvider.overrideWith((ref, novelId) => Stream.value(outline)),
        ],
        child: const MaterialApp(
          home: OutlinePage(novelId: 1, title: '测试小说'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空大纲渲染纯白秃树页不崩溃', (tester) async {
    await pumpOutline(tester, const []);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('测试小说'), findsOneWidget);
  });

  testWidgets('有章节时树 painter 收到正确数据', (tester) async {
    await pumpOutline(tester, [
      OutlineChapter(
        chapter: const Chapter(id: 1, novelId: 1, title: '引子', sortOrder: 0),
        sections: const [
          Section(id: 10, chapterId: 1, title: '第一节', sortOrder: 0),
        ],
      ),
    ]);

    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PencilTreePainter));
    final painter = paint.painter as PencilTreePainter;
    expect(painter.tree.branches, hasLength(1));
    expect(painter.tree.branches.single.twigs, hasLength(1));
  });
}
