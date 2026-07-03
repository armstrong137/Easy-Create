import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/outline_page.dart';
import 'package:novel_app/presentation/outline/pencil_tree_painter.dart';

/// 阶段四：大纲页（铅笔树 + 玻璃＋号）
///
/// 注意：大纲流一律 override（防 drift 流挂死）；页面含无限反光动画，
/// 只能定点 pump，严禁 pumpAndSettle。创建落库用真内存库验证。
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
                sortOrder: j),
        ],
      );

  Future<void> pumpOutline(
      WidgetTester tester, List<OutlineChapter> outline) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          outlineProvider.overrideWith((ref, novelId) => Stream.value(outline)),
        ],
        child: const MaterialApp(
          home: OutlinePage(novelId: 1, title: '测试小说'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('空大纲渲染秃树页与左右玻璃＋号', (tester) async {
    await pumpOutline(tester, const []);

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const Key('长章按钮')), findsOneWidget);
    expect(find.byKey(const Key('长节按钮')), findsOneWidget);
  });

  testWidgets('有章节时树 painter 收到正确数据', (tester) async {
    await pumpOutline(tester, [fakeChapter(1, '引子', 1)]);

    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PencilTreePainter));
    final painter = paint.painter as PencilTreePainter;
    expect(painter.tree.branches, hasLength(1));
    expect(painter.tree.branches.single.twigs, hasLength(1));
  });

  testWidgets('点左＋：首章命名"引子"落库并播放生长动画', (tester) async {
    await pumpOutline(tester, const []);

    // 先造小说行，满足章的外键
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));

    await tester.tap(find.byKey(const Key('长章按钮')));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await db.select(db.chapters).get();
    expect(chapters.single.title, '引子');

    // 播完生长动画（700ms）
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('已有一章时点左＋命名"第一章"', (tester) async {
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));
    await pumpOutline(tester, [fakeChapter(1, '引子', 0)]);

    await tester.tap(find.byKey(const Key('长章按钮')));
    await tester.pump(const Duration(milliseconds: 100));

    final chapters = await db.select(db.chapters).get();
    expect(chapters.single.title, '第一章', reason: '第二个章按序命名');
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('无章时点右＋：提示先建章、不落库', (tester) async {
    await pumpOutline(tester, const []);

    await tester.tap(find.byKey(const Key('长节按钮')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('先点左边的＋'), findsOneWidget);
    final sections = await db.select(db.sections).get();
    expect(sections, isEmpty);
  });

  testWidgets('长按章标签 → 菜单 → 删除确认 → 章从库中剪掉', (tester) async {
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
        novelId: 1, title: '引子', sortOrder: 0));
    await pumpOutline(tester, [fakeChapter(1, '引子', 0)]);

    await tester.longPress(find.byKey(const Key('章热区_1')));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('菜单删除')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('删除确认按钮')));
    await tester.pump(const Duration(milliseconds: 400));

    final chapters = await db.select(db.chapters).get();
    expect(chapters, isEmpty, reason: '确认后章应被删除');
  });

  testWidgets('双击章标签 → 重命名对话框 → 保存落库', (tester) async {
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
        novelId: 1, title: '引子', sortOrder: 0));
    await pumpOutline(tester, [fakeChapter(1, '引子', 0)]);

    // 双击 = 两次快速点击
    await tester.tap(find.byKey(const Key('章热区_1')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const Key('章热区_1')));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
        find.byKey(const Key('重命名输入框')), '楔子·星海之始');
    await tester.tap(find.byKey(const Key('重命名确认按钮')));
    await tester.pump(const Duration(milliseconds: 400));

    final chapters = await db.select(db.chapters).get();
    expect(chapters.single.title, '楔子·星海之始');
  });

  testWidgets('双击节标签 → 进小节页 → 改标题落库', (tester) async {
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
        novelId: 1, title: '引子', sortOrder: 0));
    await db.into(db.sections).insert(SectionsCompanion.insert(
        chapterId: 1, title: '第一节', sortOrder: 0));
    await pumpOutline(tester, [fakeChapter(1, '引子', 1)]);

    const twigKey = Key('节热区_100'); // fakeChapter 的节 id = 1*100+0
    final center = tester.getCenter(find.byKey(twigKey));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    final titleField = find.byKey(const Key('小节标题输入框'));
    expect(titleField, findsOneWidget, reason: '双击节应进入小节页');

    // 小节页操作真实节 id=100？——fake 数据 id 与真库 id 不同，
    // 此处仅验证导航与输入框存在；改名落库单测放数据层
    await tester.enterText(titleField, '月下独白');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('点右＋：节挂到最新一章、按章内序号命名', (tester) async {
    // 真库造链路：小说 + 两章（节要挂到最后一章 id=2）
    await db.into(db.novels).insert(NovelsCompanion.insert(
        title: '书', planet: 'earth', sortOrder: 0, createdAt: DateTime.now()));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
        novelId: 1, title: '引子', sortOrder: 0));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
        novelId: 1, title: '第一章', sortOrder: 1));

    await pumpOutline(tester, [
      fakeChapter(1, '引子', 0),
      fakeChapter(2, '第一章', 2), // 已有 2 节 → 新节应叫"第三节"
    ]);

    await tester.tap(find.byKey(const Key('长节按钮')));
    await tester.pump(const Duration(milliseconds: 100));

    final sections = await db.select(db.sections).get();
    expect(sections.single.chapterId, 2, reason: '挂到最新一章');
    expect(sections.single.title, '第三节');
    await tester.pump(const Duration(milliseconds: 800));
  });
}
