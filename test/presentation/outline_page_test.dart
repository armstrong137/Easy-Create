import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/data/repositories/novel_repository.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/home/planet_scene/planet_scene.dart'
    show advanced3DProvider;
import 'package:novel_app/presentation/outline/outline_page.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_controller.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_protocol.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_standin.dart';
import 'package:novel_app/presentation/section/section_page.dart';

class ControllableNovelRepository extends NovelRepository {
  ControllableNovelRepository(this.database) : super(database) {
    _outline = StreamController<List<OutlineChapter>>.broadcast(
      onListen: () => unawaited(_emitOutline()),
    );
  }

  final AppDatabase database;
  late final StreamController<List<OutlineChapter>> _outline;
  int _novelId = 1;

  Future<Chapter> Function(int novelId)? createChapterHandler;
  Future<Section> Function(int chapterId)? createSectionHandler;

  @override
  Future<Chapter> createChapter({required int novelId, String? title}) {
    final handler = createChapterHandler;
    final creation = handler == null
        ? super.createChapter(novelId: novelId, title: title)
        : handler(novelId);
    return creation.then((chapter) async {
      await _emitOutline();
      return chapter;
    });
  }

  @override
  Future<Section> createSection({required int chapterId, String? title}) {
    final handler = createSectionHandler;
    final creation = handler == null
        ? super.createSection(chapterId: chapterId, title: title)
        : handler(chapterId);
    return creation.then((section) async {
      await _emitOutline();
      return section;
    });
  }

  @override
  Stream<List<OutlineChapter>> watchOutline(int novelId) {
    _novelId = novelId;
    return _outline.stream;
  }

  Future<void> _emitOutline() async {
    if (_outline.isClosed) return;
    final chapters =
        await (database.select(database.chapters)
              ..where((table) => table.novelId.equals(_novelId))
              ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
            .get();
    final result = <OutlineChapter>[];
    for (final chapter in chapters) {
      final sections =
          await (database.select(database.sections)
                ..where((table) => table.chapterId.equals(chapter.id))
                ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
              .get();
      result.add(OutlineChapter(chapter: chapter, sections: sections));
    }
    if (!_outline.isClosed) _outline.add(result);
  }

  Future<void> close() => _outline.close();
}

void main() {
  late AppDatabase database;
  late List<ControllableNovelRepository> repositories;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repositories = [];
  });

  tearDown(() async {
    for (final repository in repositories) {
      await repository.close();
    }
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
    List<OutlineChapter>? outline, {
    Widget? overlay,
    NovelRepository? repository,
    bool enable3D = false,
    bool useProductionRepository = false,
    Widget Function(TreeSceneController controller)? treeSceneBuilder,
  }) async {
    final page = OutlinePage(
      novelId: 1,
      title: '测试小说',
      treeSceneBuilder: treeSceneBuilder,
    );
    final liveRepository =
        repository ??
        (useProductionRepository
            ? null
            : ControllableNovelRepository(database));
    if (liveRepository is ControllableNovelRepository &&
        !repositories.contains(liveRepository)) {
      repositories.add(liveRepository);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          advanced3DProvider.overrideWithValue(enable3D),
          if (liveRepository != null)
            novelRepositoryProvider.overrideWithValue(liveRepository),
          if (outline != null)
            outlineProvider.overrideWith(
              (ref, novelId) => Stream.value(outline),
            ),
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
                    Positioned.fill(child: page),
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
    await pumpOutline(tester, null);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.25, size.height * 0.55));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await database.select(database.chapters).get();
    expect(chapters, hasLength(1));
    expect(find.text('引子'), findsOneWidget);
  });

  testWidgets('右半屏双击为当前章节创建小节', (tester) async {
    await seedNovel();
    final chapterId = await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 0),
        );
    await pumpOutline(tester, null);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.75, size.height * 0.55));
    await tester.pump(const Duration(milliseconds: 100));

    final sections = await database.select(database.sections).get();
    expect(sections, hasLength(1));
    expect(sections.single.chapterId, chapterId);
    expect(find.text('第一节'), findsOneWidget);
  });

  testWidgets('点击左侧新芽入口后由数据库流显示新章节', (tester) async {
    await seedNovel();
    await pumpOutline(tester, null);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(await database.select(database.chapters).get(), hasLength(1));
    expect(find.text('引子'), findsOneWidget);
  });

  testWidgets('生产 watchOutline 在浏览早期章节时聚焦新建章节', (tester) async {
    await seedNovel();
    for (var index = 0; index < 4; index += 1) {
      await database
          .into(database.chapters)
          .insert(
            ChaptersCompanion.insert(
              novelId: 1,
              title: '第${index + 1}章',
              sortOrder: index,
            ),
          );
    }
    await pumpOutline(tester, null, useProductionRepository: true);

    final size = tester.getSize(find.byType(Scaffold));
    for (var index = 0; index < 3; index += 1) {
      await tester.dragFrom(
        Offset(size.width * 0.25, size.height * 0.6),
        const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('静态章交互_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await (database.select(
      database.chapters,
    )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get();
    expect(chapters, hasLength(5));
    expect(find.byKey(Key('静态章交互_${chapters.last.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('生产 watchOutline 在浏览早期小节时聚焦新建小节', (tester) async {
    await seedNovel();
    final chapterId = await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 0),
        );
    for (var index = 0; index < 7; index += 1) {
      await database
          .into(database.sections)
          .insert(
            SectionsCompanion.insert(
              chapterId: chapterId,
              title: '第${index + 1}节',
              sortOrder: index,
            ),
          );
    }
    await pumpOutline(tester, null, useProductionRepository: true);

    final size = tester.getSize(find.byType(Scaffold));
    for (var index = 0; index < 6; index += 1) {
      await tester.dragFrom(
        Offset(size.width * 0.75, size.height * 0.65),
        const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('静态节交互_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('新增小节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    final sections = await (database.select(
      database.sections,
    )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get();
    expect(sections, hasLength(8));
    expect(find.byKey(Key('静态节交互_${sections.last.id}')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('实时 3D 未上报新 projection 时仍显示数据库新标签', (tester) async {
    await seedNovel();
    TreeSceneController? scene;
    await pumpOutline(
      tester,
      null,
      enable3D: true,
      useProductionRepository: true,
      treeSceneBuilder: (controller) {
        scene = controller;
        return const SizedBox.expand();
      },
    );

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await database.select(database.chapters).get();
    expect(chapters, hasLength(1));
    expect(find.text('引子'), findsOneWidget);
    final bridgeKey = Key('静态章交互_${chapters.single.id}');
    expect(find.byKey(bridgeKey), findsOneWidget);

    await scene!.handleEvent(
      TreeSceneEvent(
        sessionId: scene!.sessionId,
        sequence: 1,
        type: 'tree.visibleLabels',
        payload: {
          'labels': [
            {
              'kind': 'chapter',
              'id': chapters.single.id,
              'x': 0.1,
              'y': 0.3,
              'width': 0.2,
              'height': 0.1,
            },
          ],
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(bridgeKey), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '引子',
      ),
      findsOneWidget,
    );

    await scene!.handleEvent(
      TreeSceneEvent(
        sessionId: scene!.sessionId,
        sequence: 2,
        type: 'tree.visibleLabels',
        payload: const {'labels': []},
      ),
    );
    await tester.pump();
    expect(find.byKey(bridgeKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('projection 早于创建 Future 返回时不会重新生成静态桥接', (tester) async {
    await seedNovel();
    final chapterId = await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '引子', sortOrder: 0),
        );
    final repository = ControllableNovelRepository(database);
    final chapter = await (database.select(
      database.chapters,
    )..where((table) => table.id.equals(chapterId))).getSingle();
    repository.createChapterHandler = (_) async => chapter;
    TreeSceneController? scene;
    await pumpOutline(
      tester,
      null,
      repository: repository,
      enable3D: true,
      treeSceneBuilder: (controller) {
        scene = controller;
        return const SizedBox.expand();
      },
    );

    await scene!.handleEvent(
      TreeSceneEvent(
        sessionId: scene!.sessionId,
        sequence: 1,
        type: 'tree.visibleLabels',
        payload: {
          'labels': [
            {
              'kind': 'chapter',
              'id': chapterId,
              'x': 0.1,
              'y': 0.3,
              'width': 0.2,
              'height': 0.1,
            },
          ],
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    await scene!.handleEvent(
      TreeSceneEvent(
        sessionId: scene!.sessionId,
        sequence: 2,
        type: 'tree.visibleLabels',
        payload: const {'labels': []},
      ),
    );
    await tester.pump();

    expect(find.byKey(Key('静态章交互_$chapterId')), findsNothing);
  });

  testWidgets('章节创建 pending 时连点只提交一次', (tester) async {
    await seedNovel();
    final repository = ControllableNovelRepository(database);
    final pending = Completer<Chapter>();
    var calls = 0;
    repository.createChapterHandler = (novelId) {
      calls += 1;
      return pending.future;
    };
    await pumpOutline(tester, null, repository: repository);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump();

    expect(calls, 1);
    expect(find.byKey(const Key('新增章节进度')), findsOneWidget);

    pending.complete(
      const Chapter(id: 1, novelId: 1, title: '引子', sortOrder: 0),
    );
    await tester.pump();
  });

  testWidgets('章节创建失败显示中文反馈并可继续创建', (tester) async {
    await seedNovel();
    final repository = ControllableNovelRepository(database)
      ..createChapterHandler = (_) async => throw StateError('写入失败');
    await pumpOutline(tester, null, repository: repository);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('创建章节失败，请稍后再试'), findsOneWidget);

    repository.createChapterHandler = null;
    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('引子'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('无章节时小节入口禁用，有当前章后可创建并显示标签', (tester) async {
    await seedNovel();
    await pumpOutline(tester, null);

    final disabled = tester.widget<Semantics>(find.byKey(const Key('新增小节入口')));
    expect(disabled.properties.enabled, isFalse);
    await tester.tap(find.byKey(const Key('新增小节入口')));
    await tester.pump();
    expect(await database.select(database.sections).get(), isEmpty);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));
    final enabled = tester.widget<Semantics>(find.byKey(const Key('新增小节入口')));
    expect(enabled.properties.enabled, isTrue);

    await tester.tap(find.byKey(const Key('新增小节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(await database.select(database.sections).get(), hasLength(1));
    expect(find.text('第一节'), findsOneWidget);
  });
}
