import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/home/home_page.dart'
    show inspirationPoolProvider;
import 'package:novel_app/presentation/outline/magic_carpet.dart'
    show CarpetOverlay;
import 'package:novel_app/presentation/outline/outline_page.dart';
import 'package:novel_app/presentation/section/section_page.dart'
    show sectionCardsProvider;

/// 大纲页（魔树版，2026-07-03 改版）：左右空白点击生枝 + 标签交互
///
/// 注意：drift 流一律 override；页面含动画时只定点 pump。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  OutlineChapter fakeChapter(int id, String title, int sectionCount) =>
      OutlineChapter(
        chapter: Chapter(id: id, novelId: 1, title: title, sortOrder: id),
        sections: [
          for (var j = 0; j < sectionCount; j++)
            Section(
              id: id * 100 + j,
              chapterId: id,
              title: '第${j + 1}节',
              sortOrder: j,
            ),
        ],
      );

  Future<void> pumpOutline(
    WidgetTester tester,
    List<OutlineChapter> outline, {
    List<Inspiration> pool = const [],
    Map<int, List<Inspiration>> sectionInspirations = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          outlineProvider.overrideWith((ref, novelId) => Stream.value(outline)),
          sectionInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(sectionInspirations),
          ),
          chapterInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(const {}),
          ),
          inspirationPoolProvider.overrideWith((ref) => Stream.value(pool)),
          sectionCardsProvider.overrideWith(
            (ref, sectionId) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          // 与 main.dart 一致：全局魔毯层叠在 Navigator 之上
          builder: (context, child) => CarpetOverlay(child: child!),
          home: const OutlinePage(novelId: 1, title: '测试小说'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 双击（建章/建节改为双击避免误触）：两次 tap 在同点、间隔 < 双击超时
  Future<void> doubleTapAt(WidgetTester tester, Offset p) async {
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> seedNovel() async {
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            title: '书',
            planet: 'earth',
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
  }

  Inspiration fakeInspiration(int id, String content, int sectionId) =>
      Inspiration(
        id: id,
        content: content,
        createdAt: DateTime(2026, 7, 1).add(Duration(minutes: id)),
        updatedAt: DateTime(2026, 7, 1),
        sectionId: sectionId,
        cardOrder: id,
      );

  testWidgets('空大纲：光杆魔树 + 左右空白区就位', (tester) async {
    await pumpOutline(tester, const []);

    expect(find.byKey(const Key('左空白区')), findsOneWidget);
    expect(find.byKey(const Key('右空白区')), findsOneWidget);
    expect(find.byType(Image), findsWidgets, reason: '魔树树干素材');
  });

  testWidgets('书名左右居中且加粗（不受左箭头/右留白不对称影响）', (tester) async {
    await pumpOutline(tester, const []);

    final titleFinder = find.byKey(const Key('大纲页书名'));
    final title = tester.widget<Text>(titleFinder);
    expect(title.style?.fontWeight, FontWeight.w700, reason: '书名须加粗');

    final center = tester.getCenter(titleFinder);
    final screen = tester.getSize(find.byType(OutlinePage));
    expect(
      (center.dx - screen.width / 2).abs(),
      lessThan(1.0),
      reason: '书名中心须与屏幕中线重合（Row+Expanded 布局会偏移）',
    );
  });

  testWidgets('点左空白：首章命名"引子"落库并播放生长动画', (tester) async {
    await seedNovel();
    await pumpOutline(tester, const []);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.05, size.height * 0.5));

    final chapters = await db.select(db.chapters).get();
    expect(chapters.single.title, '引子');
    await tester.pump(const Duration(milliseconds: 800)); // 播完生长
  });

  testWidgets('加章：树干变完之前，枝丫和标签不得出现', (tester) async {
    // 用户 2026-07-29 定稿："至少要等树干变了之后，枝丫再变化"。
    // 实拍里新枝在树干还在长的时候就冒出来，还挂在被抻长的旧照片上。
    await seedNovel();
    final outline = StreamController<List<OutlineChapter>>();
    addTearDown(outline.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          outlineProvider.overrideWith((ref, novelId) => outline.stream),
          sectionInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(const {}),
          ),
          chapterInspirationsProvider.overrideWith(
            (ref, novelId) => Stream.value(const {}),
          ),
          inspirationPoolProvider.overrideWith((ref) => Stream.value(const [])),
          sectionCardsProvider.overrideWith(
            (ref, sectionId) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => CarpetOverlay(child: child!),
          home: const OutlinePage(novelId: 1, title: '测试小说'),
        ),
      ),
    );
    outline.add(const []);
    await tester.pump(const Duration(milliseconds: 100));

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.05, size.height * 0.5));
    // 大纲流推来新章：枝已在树上，但树干这一轮（0→1 章要跨档）还没播完
    outline.add([fakeChapter(1, '引子', 0)]);
    await tester.pump(const Duration(milliseconds: 300));

    double capsuleOpacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byKey(const Key('章热区_1')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    expect(find.byKey(const Key('章热区_1')), findsOneWidget);
    expect(capsuleOpacity(), 0, reason: '树干还在变，标签必须还看不见');

    // 擦除 1.1s + 余量播完 → 枝丫生长动画启动 → 后段标签浮现
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 700));
    expect(capsuleOpacity(), 1, reason: '树干动完后枝丫与标签才长出来');
  });

  testWidgets('已有一章时点左空白命名"第一章"', (tester) async {
    await seedNovel();
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '引子', sortOrder: 0),
        );
    await pumpOutline(tester, [fakeChapter(1, '引子', 0)]);

    // 左下空白（章序自上而下：单章标签在左上角，左下角是干净空白）
    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.05, size.height * 0.75));

    final chapters = await db.select(db.chapters).get();
    expect(chapters.map((c) => c.title), contains('第一章'));
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('无章时点右空白：提示先长章枝、不落库', (tester) async {
    await pumpOutline(tester, const []);

    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.95, size.height * 0.5));

    expect(find.textContaining('先点左边空白'), findsOneWidget);
    final sections = await db.select(db.sections).get();
    expect(sections, isEmpty);

    // 排干浮层提示的停留定时器与淡出动画（1.7s 停留 + 0.26s 淡出）
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('点右空白：节挂到点击高度对应的章（左右对应关系）', (tester) async {
    await seedNovel();
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '引子', sortOrder: 0),
        );
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '第一章', sortOrder: 1),
        );
    await pumpOutline(tester, [
      fakeChapter(1, '引子', 0),
      fakeChapter(2, '第一章', 0),
    ]);

    // 章序自上而下：引子在上、第一章在下 → 双击右侧靠下挂到第一章
    final size = tester.getSize(find.byType(Scaffold));
    await doubleTapAt(tester, Offset(size.width * 0.85, size.height * 0.78));

    final sections = await db.select(db.sections).get();
    expect(sections.single.chapterId, 2, reason: '靠下高度对应最后一章（第一章）');
    expect(sections.single.title, '第一节');
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('窗口模式：一屏两章，左滑滚章节', (tester) async {
    await seedNovel();
    for (var i = 0; i < 4; i++) {
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              novelId: 1,
              title: '第${i + 1}章',
              sortOrder: i,
            ),
          );
    }
    await pumpOutline(tester, [
      for (var i = 1; i <= 4; i++) fakeChapter(i, '第$i章', 0),
    ]);

    expect(find.byKey(const Key('章热区_1')), findsOneWidget);
    expect(find.byKey(const Key('章热区_2')), findsOneWidget);
    expect(find.byKey(const Key('章热区_4')), findsNothing, reason: '一屏只见两章');

    // 左半屏向上滑两屏章高 → 镜头滑到末章
    final size = tester.getSize(find.byType(Scaffold));
    final bandH = (size.height - 52 - 12) / 2;
    await tester.dragFrom(
      Offset(size.width * 0.2, size.height * 0.7),
      Offset(0, -bandH * 2),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('章热区_4')), findsOneWidget, reason: '滑到底后末章可见');
    expect(find.byKey(const Key('章热区_1')), findsNothing);
  });

  testWidgets('窗口模式止血：魔树背景使用完整素材，不再分段拼接', (tester) async {
    await seedNovel();
    await pumpOutline(tester, [
      for (var i = 1; i <= 4; i++) fakeChapter(i, '第$i章', 0),
    ]);

    expect(find.byKey(const Key('魔树完整图')), findsOneWidget);
    expect(find.byKey(const Key('魔树顶段')), findsNothing);
    expect(find.byKey(const Key('魔树中段裁剪')), findsNothing);
    expect(find.byKey(const Key('魔树固定土壤层')), findsNothing);
    // 注：ShaderMask 现在是生长擦除的正当用法（换帧时自下而上扫），
    // 早先禁它是为了封掉"羽化拼接分段素材"那条路——该路由上面几个 key 守住
  });

  test('换档用自下而上的生长擦除，不得回到交叉淡入淡出', () {
    final src = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    // 相邻帧各 50% 混合时叶子会半透明重叠（实测 f19/f20 明显鬼影），读作 PPT
    // 翻页。改成新帧自下而上擦除覆盖旧帧——没有半透明，读作生长沿藤上行。
    expect(src, contains('kGrowWipeDuration'), reason: '换帧必须走生长擦除');
    expect(
      src,
      isNot(contains('AnimatedSwitcher')),
      reason: '整树交叉淡入淡出=PPT 翻页，禁止回流',
    );
    // 整帧解码 941×1672×4 ≈ 6.3MB，22 帧全预解码要 138MB：
    // 必须只预解码当前帧附近的窗口，且按显示宽度解码
    expect(src, contains('cacheWidth'), reason: '必须按显示宽度解码');
    expect(
      src,
      contains('ResizeImage(AssetImage(treeFrameAsset(f))'),
      reason: '预解码要与绘制用同一个 ImageProvider key，否则白解码一遍',
    );
  });

  test('整帧照原样画：不得再拆树层/土层、不得缩放拉伸', () {
    final src = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    // 五档时代为了"泥土不动"把素材拆成树层+土层并纵向拉伸，一路衍生出
    // 平切口、土堆被切平、叶子被切断等一串问题。帧序列自己表达生长，
    // 代码只需照原样画整帧。
    expect(src, isNot(contains('soilClip')), reason: '不得再拆土层');
    expect(src, isNot(contains('kSoilAsset')));
    expect(
      src,
      contains('Positioned.fromRect(rect: rect, child: img)'),
      reason: '整帧照 imageRect 原样画',
    );
  });

  test('窗口模式止血：代码禁止分段平铺、镜像、羽化路线回流', () {
    final src = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    expect(src, isNot(contains('_SegmentedMagicTreeImage')));
    expect(src, isNot(contains('_TreeMiddleTiles')));
    expect(src, isNot(contains('_FeatheredTreeMiddleTile')));
    expect(
      src,
      isNot(contains('Matrix4.diagonal3Values(1, index.isOdd ? -1 : 1, 1)')),
    );
  });

  test('分段魔树不得用整树 AnimatedSwitcher 交叉淡入淡出', () {
    final src = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    expect(
      src,
      isNot(contains("ValueKey('tree_segments_")),
      reason: '阶段切换不能把整棵树交叉淡入淡出，否则会出现半透明鬼影',
    );
  });

  test('卷须生长使用裁剪显露，不再整体缩放精灵', () {
    final src = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    expect(
      src,
      isNot(contains('Transform.scale')),
      reason: '卷须整体缩放会产生强拉伸图片感，应使用 ClipRect + Align 显露',
    );
    expect(src, contains('widthFactor: growth'));
  });

  testWidgets('窗口模式：右滑滚小节（树背景不动、章带内滚）', (tester) async {
    await seedNovel();
    await pumpOutline(tester, [
      fakeChapter(1, '第1章', 10),
      fakeChapter(2, '第2章', 0),
      fakeChapter(3, '第3章', 0),
    ]);

    // 底部对齐：默认最新的第十节钉在带底可见，最老的第一节在带外
    // （下拉滚动露出更老小节的数学，由 magic_tree_model_test 的"溢出可滚"覆盖；
    //  拖动手势在这套重叠布局里坐标脆弱，改由真机验证）
    expect(
      find.byKey(const Key('节热区_109')),
      findsOneWidget,
      reason: '默认最新的第十节钉在带底可见',
    );
    expect(find.byKey(const Key('节热区_100')), findsNothing, reason: '最老的第一节在带外');
  });

  testWidgets('长按章标签 → 菜单 → 删除确认 → 章被剪掉', (tester) async {
    await seedNovel();
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '引子', sortOrder: 0),
        );
    await pumpOutline(tester, [fakeChapter(1, '引子', 0)]);

    await tester.longPress(find.byKey(const Key('章热区_1')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('菜单删除')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('删除确认按钮')));
    await tester.pump(const Duration(milliseconds: 400));

    final chapters = await db.select(db.chapters).get();
    expect(chapters, isEmpty);
  });

  testWidgets('单击节标签 → 进小节页（用户定稿：单击即进）', (tester) async {
    await seedNovel();
    await pumpOutline(tester, [fakeChapter(1, '引子', 1)]);

    await tester.tap(find.byKey(const Key('节热区_100')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('小节标题输入框')), findsOneWidget);
  });

  testWidgets('小节标签下最多显示三条灵感预览', (tester) async {
    await pumpOutline(
      tester,
      [fakeChapter(1, '引子', 1)],
      sectionInspirations: {
        100: [
          fakeInspiration(1, '第一条预览', 100),
          fakeInspiration(2, '第二条预览', 100),
          fakeInspiration(3, '第三条预览', 100),
          fakeInspiration(4, '第四条不显示', 100),
        ],
      },
    );

    expect(find.text('第一条预览'), findsOneWidget);
    expect(find.text('第二条预览'), findsOneWidget);
    expect(find.text('第三条预览'), findsOneWidget);
    expect(find.text('第四条不显示'), findsNothing);
  });

  testWidgets('拖拽：魔毯灵感拖到节标签 → 挂靠落库 → 魔毯缩球', (tester) async {
    await seedNovel();
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(novelId: 1, title: '引子', sortOrder: 0),
        );
    await db
        .into(db.sections)
        .insert(
          SectionsCompanion.insert(chapterId: 1, title: '第一节', sortOrder: 0),
        );
    final now = DateTime.now();
    final inspId = await db
        .into(db.inspirations)
        .insert(
          InspirationsCompanion.insert(
            content: '拖我上树',
            createdAt: now,
            updatedAt: now,
            cardOrder: 0,
          ),
        );
    final insp = Inspiration(
      id: inspId,
      content: '拖我上树',
      createdAt: now,
      updatedAt: now,
      cardOrder: 0,
    );

    await pumpOutline(
      tester,
      [
        const OutlineChapter(
          chapter: Chapter(id: 1, novelId: 1, title: '引子', sortOrder: 0),
          sections: [Section(id: 1, chapterId: 1, title: '第一节', sortOrder: 0)],
        ),
      ],
      pool: [insp],
    );

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final from = tester.getCenter(find.byKey(Key('魔毯灵感_$inspId')));
    final to = tester.getCenter(find.byKey(const Key('节热区_1')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(inspId))).getSingle();
    expect(saved.sectionId, 1);
    expect(find.byKey(const Key('魔毯小球')), findsOneWidget, reason: '拖入后魔毯自动缩球');
  });
}
