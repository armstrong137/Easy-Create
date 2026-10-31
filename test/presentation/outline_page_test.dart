import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:novel_app/presentation/outline/tree_scene/organic_tree.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_branch.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_projection.dart';
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
    bool enableIllustratedCamera = false,
    bool useProductionRepository = false,
    Widget Function(TreeSceneController controller)? treeSceneBuilder,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = OutlinePage(
      novelId: 1,
      title: '测试小说',
      treeSceneBuilder: treeSceneBuilder,
      enableIllustratedCamera: enableIllustratedCamera,
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
    // 图片解码使用真实异步时钟，先完成解码再检验虚拟时钟中的枝条时序。
    final imageContext = tester.element(find.byType(OutlinePage));
    await tester.runAsync(() async {
      for (var stage = 0; stage < 6; stage++) {
        await precacheImage(
          AssetImage('assets/tree_scene/illustrated/age_$stage.png'),
          imageContext,
        );
      }
      await precacheImage(
        const AssetImage('assets/tree_scene/illustrated/age_1_integrated.png'),
        imageContext,
      );
      await precacheImage(
        const AssetImage('assets/tree_scene/illustrated/chapter_branch.png'),
        imageContext,
      );
    });
    await tester.pump();
    if (enableIllustratedCamera) {
      final future = tester.widget<FutureBuilder<List<ui.Image>>>(
        find.descendant(of: find.byType(OrganicTree), matching: find.byType(FutureBuilder<List<ui.Image>>)),
      ).future!;
      await tester.runAsync(() => future);
      await tester.pump();
    }
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

  testWidgets('大纲页默认渲染正式二维古树和书名', (tester) async {
    await seedNovel();
    await pumpOutline(tester, const []);

    expect(find.byKey(const Key('大纲页书名')), findsOneWidget);
    expect(find.text('测试小说'), findsOneWidget);
    expect(find.byType(TreeStandin), findsOneWidget);
    expect(find.text('新芽 +'), findsNothing);
    expect(tester.getSize(find.byType(TreeStandin)), const Size(430, 932));
  });

  testWidgets('书名在深色树皮上保留浅色轮廓且不重复文字', (tester) async {
    await pumpOutline(tester, const []);
    final title = tester.widget<Text>(find.byKey(const Key('大纲页书名')));
    final shadows = title.style!.shadows ?? const <Shadow>[];
    expect(shadows.length, greaterThanOrEqualTo(4));
    expect(shadows.every((shadow) => shadow.color.computeLuminance() > 0.7), isTrue);
    expect(shadows.any((shadow) => shadow.offset.dx < 0), isTrue);
    expect(shadows.any((shadow) => shadow.offset.dx > 0), isTrue);
    expect(shadows.any((shadow) => shadow.offset.dy < 0), isTrue);
    expect(shadows.any((shadow) => shadow.offset.dy > 0), isTrue);
    expect(find.byKey(const Key('大纲页书名')), findsOneWidget);
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

  testWidgets('枝牌语义只读完整标题一次且保留点击动作', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await seedNovel();
      final seeded = await seedOutline();
      await pumpOutline(tester, seeded.outline);
      for (final title in ['第一章', '第一节']) {
        final label = find.bySemanticsLabel(RegExp('^$title\$'));
        expect(label, findsOneWidget);
        expect(
          tester.getSemantics(label).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
      }
    } finally {
      handle.dispose();
    }
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

  testWidgets('浏览旧章平移树体而不回退树龄，枝牌相对树体不滑动', (tester) async {
    await seedNovel();
    final outline = List.generate(10, (index) => OutlineChapter(
      chapter: Chapter(id: index + 1, novelId: 1, title: '第${index + 1}章', sortOrder: index),
      sections: const [],
    ));
    await pumpOutline(tester, outline, enableIllustratedCamera: true);
    await tester.pump(const Duration(seconds: 2));
    final beforeTree = tester.getRect(find.byType(OrganicTree));
    final treeBark = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter).whereType<OrganicTreeStudyPainter>()
        .single.bark;
    final materialScale = OrganicTreeProjection(
      tester.getSize(find.byType(OrganicTree)),
    ).scale;
    for (final element in find.byType(OrganicBranch).evaluate()) {
      final branch = element.widget as OrganicBranch;
      expect(branch.trunkMask != null, isTrue);
      expect(branch.trunkMask!.contains(Offset(
        element.size!.width * (branch.right ? .12 : .88),
        element.size!.height * .7,
      )), isTrue, reason: '主干遮罩必须覆盖同帧真实枝根，不能使用错位的母版路径');
      expect((element.widget as OrganicBranch).treeScale, materialScale,
          reason: '枝条基础纹理密度应使用主树实际投影，不额外乘章节镜头缩放');
      expect((element.widget as OrganicBranch).maxRootRadius,
          closeTo(element.size!.height * .08, .0001),
          reason: '成年枝只传入生效半径，避免超出默认粗度的母干数值引发无效重绘');
    }
    final beforeBranch = tester.getRect(find.byKey(const Key('静态章交互_9')));
    await tester.dragFrom(const Offset(80, 650), const Offset(0, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final afterTree = tester.getRect(find.byType(OrganicTree));
    final afterBranch = tester.getRect(find.byKey(const Key('静态章交互_9')));
    expect(tester.widget<OrganicTree>(find.byType(OrganicTree)).age, 1);
    for (final branch in tester.widgetList<OrganicBranch>(find.byType(OrganicBranch))) {
      expect(branch.barkAge, 1, reason: '浏览旧章不能回退承托枝的材质树龄');
      expect(identical(branch.bark, treeBark), isTrue,
          reason: '历史中新显示的枝牌必须继续借用主树图片');
    }
    expect(afterTree.width, closeTo(beforeTree.width, .001));
    expect(afterTree.height, closeTo(beforeTree.height, .001));
    expect(afterTree.top, lessThan(beforeTree.top));
    expect(afterBranch.top - afterTree.top, closeTo(beforeBranch.top - beforeTree.top, 0.1));
    expect(find.byKey(const Key('静态章交互_10')), findsNothing);
  });

  testWidgets('实验大纲从幼树开始使用连续主树和真实章节热区', (tester) async {
    await seedNovel();
    final seeded = await seedOutline();
    await pumpOutline(tester, seeded.outline, enableIllustratedCamera: true);
    expect(find.byType(TreeStandin), findsNothing);
    expect(tester.widget<OrganicTree>(find.byType(OrganicTree)).age, .2);
    expect(find.byKey(Key('静态章交互_${seeded.chapterId}')), findsOneWidget);
    expect(find.byKey(Key('静态节交互_${seeded.sectionId}')), findsOneWidget);
    for (final element in find.byType(OrganicBranch).evaluate()) {
      final branch = element.widget as OrganicBranch;
      expect(branch.barkAge, .2, reason: '幼树承托枝必须接收主树同帧树龄，不能沿用成年树皮');
      expect(branch.maxRootRadius, greaterThan(0));
      expect(branch.maxRootRadius, lessThan(element.size!.height * .08),
          reason: '幼树承托枝应受母干限制，不使用成年枝默认粗度');
    }
    expect(tester.getSize(find.byKey(Key('静态章交互_${seeded.chapterId}'))).width,
        closeTo(215, .001), reason: '只约束木质截面，不缩小牌面与热区');
  });

  testWidgets('全景双击章牌打开重命名而不创建新章', (tester) async {
    await seedNovel();
    final outline = List.generate(10, (index) => OutlineChapter(
      chapter: Chapter(id: index + 1, novelId: 1, title: '第${index + 1}章', sortOrder: index),
      sections: const [],
    ));
    await pumpOutline(tester, outline, enableIllustratedCamera: true);
    await tester.tap(find.byKey(const Key('魔树全景切换')));
    await tester.pumpAndSettle();
    await doubleTapAt(tester, tester.getCenter(find.byKey(const Key('静态章交互_9'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('重命名输入框')), findsOneWidget);
    expect(await database.select(database.chapters).get(), isEmpty);
  });

  testWidgets('正式二维右侧最多显示两节且滑动会刷新窗口', (tester) async {
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
    expect(find.byKey(const Key('静态节交互_6')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_7')), findsOneWidget);

    final size = tester.getSize(find.byType(Scaffold));
    for (var index = 0; index < 3; index += 1) {
      await tester.dragFrom(
        Offset(size.width * 0.55, size.height * 0.65),
        const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('静态节交互_3')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_4')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_7')), findsNothing);
  });

  testWidgets('右侧拖动中页面重建仍只切换小节', (tester) async {
    await seedNovel();
    await pumpOutline(tester, [
      OutlineChapter(
        chapter: const Chapter(id: 1, novelId: 1, title: '第一章', sortOrder: 0),
        sections: List.generate(4, (index) => Section(
          id: index + 1, chapterId: 1, title: '第${index + 1}节', sortOrder: index,
        )),
      ),
    ]);
    expect(find.byKey(const Key('静态节交互_4')), findsOneWidget);
    final gesture = await tester.startGesture(const Offset(300, 640));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    // 模拟拖动尚未结束时数据刷新或其他状态触发页面重建。
    tester.element(find.byType(OutlinePage)).markNeedsBuild();
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('静态节交互_2')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_3')), findsOneWidget);
    expect(find.byKey(const Key('静态节交互_4')), findsNothing);
  });

  testWidgets('左半屏双击创建章节', (tester) async {
    await seedNovel();
    await pumpOutline(tester, null);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.25, size.height * 0.55));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await database.select(database.chapters).get();
    expect(chapters, hasLength(1));
    expect(find.byKey(Key('静态章交互_${chapters.single.id}')), findsOneWidget);
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
    expect(find.byKey(Key('静态节交互_${sections.single.id}')), findsOneWidget);
  });

  testWidgets('点击左侧新芽入口后由数据库流显示新章节', (tester) async {
    await seedNovel();
    await pumpOutline(tester, null);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await database.select(database.chapters).get();
    expect(chapters, hasLength(1));
    expect(find.byKey(Key('静态章交互_${chapters.single.id}')), findsOneWidget);
  });

  testWidgets('第二个结构节点先切换树龄档再让新章枝一次长出', (tester) async {
    await seedNovel();
    await database
        .into(database.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 0),
        );
    await pumpOutline(tester, null);
    expect(tester.widget<TreeStandin>(find.byType(TreeStandin)).stage, 1);

    await tester.tap(find.byKey(const Key('新增章节入口')));
    final newBranch = find.descendant(
      of: find.byKey(const Key('静态章交互_2')),
      matching: find.byType(ClipRect),
    );
    for (var frame = 0; frame < 60 && newBranch.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.widget<TreeStandin>(find.byType(TreeStandin)).stage, 2);
    expect(newBranch, findsOneWidget);
    final clipRender = tester.renderObject<RenderClipRect>(newBranch);
    final initialClip = clipRender.clipper!.getClip(clipRender.size);
    expect(initialClip.width, lessThanOrEqualTo(0.5));

    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 60));
    final growingClip = clipRender.clipper!.getClip(clipRender.size);
    expect(growingClip.width, greaterThan(0.5));
    expect(growingClip.width, lessThan(clipRender.size.width));

    await tester.pump(const Duration(milliseconds: 1000));
    final completedClip = clipRender.clipper!.getClip(clipRender.size);
    expect(completedClip.width, closeTo(clipRender.size.width, 0.5));
  });

  testWidgets('十个结构节点能够显示最终成熟古树', (tester) async {
    await seedNovel();
    for (var index = 0; index < 10; index += 1) {
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
    await pumpOutline(tester, null);

    final standin = find.byType(TreeStandin);
    expect(tester.widget<TreeStandin>(standin).stage, 5);
    final image = tester.widget<Image>(
      find.descendant(of: standin, matching: find.byType(Image)),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/tree_scene/illustrated/age_5.png',
    );
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
    expect(find.byKey(Key('静态章交互_${chapters.single.id}')), findsOneWidget);
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
    final chapters = await database.select(database.chapters).get();
    expect(find.byKey(Key('静态章交互_${chapters.single.id}')), findsOneWidget);
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
    final sections = await database.select(database.sections).get();
    expect(find.byKey(Key('静态节交互_${sections.single.id}')), findsOneWidget);
  });
}
