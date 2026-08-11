import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/home/planet_scene/planet_scene.dart'
    show advanced3DProvider;
import 'package:novel_app/presentation/outline/outline_page.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_standin.dart';
import 'package:novel_app/presentation/section/section_page.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedNovel() async {
    await database
        .into(database.novels)
        .insert(
          NovelsCompanion.insert(
            title: '测试小说',
            planet: 'earth',
            sortOrder: 0,
            createdAt: DateTime(2026, 8, 10),
          ),
        );
  }

  Future<void> pumpOutline(
    WidgetTester tester,
    List<OutlineChapter> outline, {
    Widget? overlay,
  }) async {
    const page = OutlinePage(novelId: 1, title: '测试小说');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          advanced3DProvider.overrideWithValue(false),
          outlineProvider.overrideWith((ref, novelId) => Stream.value(outline)),
          sectionInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(const {}),
          ),
          chapterInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(const {}),
          ),
        ],
        child: MaterialApp(
          home: overlay == null
              ? page
              : Stack(
                  children: [
                    const Positioned.fill(child: page),
                    overlay,
                  ],
                ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<({int chapterId, int sectionId, List<OutlineChapter> outline})>
  seedOutline() async {
    final chapterId = await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 0),
        );
    final sectionId = await database
        .into(database.sections)
        .insert(
          SectionsCompanion.insert(
            chapterId: chapterId,
            title: '第一节',
            sortOrder: 0,
          ),
        );
    return (
      chapterId: chapterId,
      sectionId: sectionId,
      outline: [
        OutlineChapter(
          chapter: Chapter(
            id: chapterId,
            novelId: 1,
            title: '第一章',
            sortOrder: 0,
          ),
          sections: [
            Section(
              id: sectionId,
              chapterId: chapterId,
              title: '第一节',
              sortOrder: 0,
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('大纲页仅渲染实时三维场景的静态降级图和书名', (tester) async {
    await seedNovel();
    await pumpOutline(tester, const []);

    expect(find.byKey(const Key('大纲页书名')), findsOneWidget);
    expect(find.text('测试小说'), findsOneWidget);
    expect(find.byType(TreeStandin), findsOneWidget);
  });

  testWidgets('静态回退保留章节标签及小节导航', (tester) async {
    await seedNovel();
    final seeded = await seedOutline();
    await pumpOutline(tester, seeded.outline);

    expect(find.byKey(Key('静态章热区_${seeded.chapterId}')), findsOneWidget);
    expect(find.byKey(Key('静态节热区_${seeded.sectionId}')), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    await tester.tap(find.byKey(Key('静态节交互_${seeded.sectionId}')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(navigator.canPop(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(navigator.canPop(), isTrue);
    expect(find.byType(SectionPage), findsOneWidget);
    expect(find.byKey(const Key('小节标题输入框')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('静态回退支持将灵感拖入小节', (tester) async {
    await seedNovel();
    final seeded = await seedOutline();
    final now = DateTime(2026, 8, 10, 12);
    final inspirationId = await database
        .into(database.inspirations)
        .insert(
          InspirationsCompanion.insert(
            content: '静态回退灵感',
            createdAt: now,
            updatedAt: now,
            cardOrder: 0,
          ),
        );
    final inspiration = await (database.select(
      database.inspirations,
    )..where((table) => table.id.equals(inspirationId))).getSingle();
    await pumpOutline(
      tester,
      seeded.outline,
      overlay: Positioned(
        left: 8,
        bottom: 8,
        child: Draggable<Inspiration>(
          key: const Key('测试灵感拖拽源'),
          data: inspiration,
          feedback: const Material(child: SizedBox(width: 40, height: 40)),
          child: const ColoredBox(
            color: Colors.transparent,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );
    final source = tester.getCenter(find.byKey(const Key('测试灵感拖拽源')));
    final target = tester.getCenter(
      find.byKey(Key('静态节热区_${seeded.sectionId}')),
    );
    await tester.drag(
      find.byKey(const Key('测试灵感拖拽源')),
      target - source,
      touchSlopX: 0,
      touchSlopY: 0,
    );
    await tester.pump(const Duration(milliseconds: 300));
    final assigned = await (database.select(
      database.inspirations,
    )..where((table) => table.id.equals(inspirationId))).getSingle();
    expect(assigned.sectionId, seeded.sectionId);
  });

  testWidgets('静态回退保留章节编辑菜单', (tester) async {
    await seedNovel();
    final seeded = await seedOutline();
    await pumpOutline(tester, seeded.outline);
    await tester.longPress(find.byKey(Key('静态章交互_${seeded.chapterId}')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('菜单重命名')), findsOneWidget);
    expect(find.byKey(const Key('菜单删除')), findsOneWidget);
  });

  testWidgets('静态回退左侧滑动会刷新两章窗口', (tester) async {
    await seedNovel();
    final outline = List.generate(
      4,
      (index) => OutlineChapter(
        chapter: Chapter(
          id: index + 1,
          novelId: 1,
          title: '第${index + 1}章',
          sortOrder: index,
        ),
        sections: const [],
      ),
    );
    await pumpOutline(tester, outline);
    expect(find.byKey(const Key('静态章交互_3')), findsOneWidget);
    expect(find.byKey(const Key('静态章交互_4')), findsOneWidget);

    final size = tester.getSize(find.byType(Scaffold));
    await tester.dragFrom(
      Offset(size.width * 0.25, size.height * 0.6),
      const Offset(0, 80),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('静态章交互_2')), findsOneWidget);
    expect(find.byKey(const Key('静态章交互_4')), findsNothing);
  });

  testWidgets('静态回退右侧滑动会刷新五节窗口', (tester) async {
    await seedNovel();
    final sections = List.generate(
      7,
      (index) => Section(
        id: index + 1,
        chapterId: 1,
        title: '第${index + 1}节',
        sortOrder: index,
      ),
    );
    await pumpOutline(tester, [
      OutlineChapter(
        chapter: const Chapter(id: 1, novelId: 1, title: '第一章', sortOrder: 0),
        sections: sections,
      ),
    ]);
    expect(find.byKey(const Key('静态节交互_3')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_7')), findsOneWidget);

    final size = tester.getSize(find.byType(Scaffold));
    for (var index = 0; index < 3; index += 1) {
      await tester.dragFrom(
        Offset(size.width * 0.55, size.height * 0.65),
        const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('静态节交互_2')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_7')), findsNothing);
  });

  testWidgets('左半屏双击创建章节', (tester) async {
    await seedNovel();
    await pumpOutline(tester, const []);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.25, size.height * 0.55));

    final chapters = await database.select(database.chapters).get();
    expect(chapters, hasLength(1));
  });

  testWidgets('右半屏双击为当前章节创建小节', (tester) async {
    await seedNovel();
    final chapterId = await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 0),
        );
    final outline = [
      OutlineChapter(
        chapter: Chapter(id: chapterId, novelId: 1, title: '第一章', sortOrder: 0),
        sections: const [],
      ),
    ];
    await pumpOutline(tester, outline);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.75, size.height * 0.55));

    final sections = await database.select(database.sections).get();
    expect(sections, hasLength(1));
    expect(sections.single.chapterId, chapterId);
  });
}
