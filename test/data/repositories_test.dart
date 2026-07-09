import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/repositories/inspiration_repository.dart';
import 'package:novel_app/data/repositories/novel_repository.dart';

/// 数据层单元测试：验证大纲结构 CRUD 与灵感生命周期定稿规则
void main() {
  late AppDatabase db;
  late NovelRepository novelRepo;
  late InspirationRepository inspirationRepo;

  setUp(() {
    // 每个用例独立的内存数据库，互不污染
    db = AppDatabase.forTesting(NativeDatabase.memory());
    novelRepo = NovelRepository(db);
    inspirationRepo = InspirationRepository(db);
  });

  tearDown(() async => db.close());

  // 建一条 小说→章→节 链路，返回节 id（灵感测试的挂靠点）
  Future<int> createSectionChain() async {
    final novel = await novelRepo.createNovel(title: '测试小说', planet: 'earth');
    final chapter = await novelRepo.createChapter(
      novelId: novel.id,
      title: '第一章',
    );
    final section = await novelRepo.createSection(
      chapterId: chapter.id,
      title: '第一节',
    );
    return section.id;
  }

  group('大纲结构 CRUD', () {
    test('创建小说/章/节，sort_order 依次递增', () async {
      final n1 = await novelRepo.createNovel(title: '甲', planet: 'earth');
      final n2 = await novelRepo.createNovel(title: '乙', planet: 'mars');
      expect(n1.sortOrder, 0);
      expect(n2.sortOrder, 1);

      final c1 = await novelRepo.createChapter(novelId: n1.id, title: '引子');
      final c2 = await novelRepo.createChapter(novelId: n1.id, title: '第一章');
      // 另一部小说的章序号独立计数
      final cOther = await novelRepo.createChapter(
        novelId: n2.id,
        title: '第一章',
      );
      expect([c1.sortOrder, c2.sortOrder], [0, 1]);
      expect(cOther.sortOrder, 0);

      final s1 = await novelRepo.createSection(chapterId: c1.id, title: '一');
      final s2 = await novelRepo.createSection(chapterId: c1.id, title: '二');
      expect([s1.sortOrder, s2.sortOrder], [0, 1]);
    });

    test('并发建章：sort_order 与默认名互不重复（原子事务防连点竞态）', () async {
      final novel = await novelRepo.createNovel(title: '书', planet: 'earth');
      // 同时（不 await）发起 5 次建章，模拟快速连点/生长动画期间再点。
      // 修复前"读 max→插入"非原子，5 次会读到同一 max、产生重复 sort_order 与重名。
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) novelRepo.createChapter(novelId: novel.id),
      ]);

      final orders = results.map((c) => c.sortOrder).toList()..sort();
      expect(orders, [0, 1, 2, 3, 4], reason: 'sort_order 连续且唯一');
      final titles = results.map((c) => c.title).toSet();
      expect(titles.length, 5, reason: '5 章标题互不重复（无两个第一章）');
      expect(titles, containsAll(['引子', '第一章', '第二章', '第三章', '第四章']));
    });

    test('省略标题时按新序号自动命名（引子 → 第一章 …；节 第一节 …）', () async {
      final novel = await novelRepo.createNovel(title: '书', planet: 'earth');
      final c0 = await novelRepo.createChapter(novelId: novel.id);
      final c1 = await novelRepo.createChapter(novelId: novel.id);
      expect([c0.title, c1.title], ['引子', '第一章']);

      final s0 = await novelRepo.createSection(chapterId: c1.id);
      final s1 = await novelRepo.createSection(chapterId: c1.id);
      expect([s0.title, s1.title], ['第一节', '第二节']);
    });

    test('重命名小说/章/节生效', () async {
      final novel = await novelRepo.createNovel(title: '旧名', planet: 'earth');
      await novelRepo.renameNovel(novel.id, '新名');
      final novels = await novelRepo.watchNovels().first;
      expect(novels.single.title, '新名');
    });

    test('删除小说级联删除其下章与节', () async {
      final sectionId = await createSectionChain();
      final novels = await novelRepo.watchNovels().first;
      await novelRepo.deleteNovel(novels.single.id);

      final chapters = await db.select(db.chapters).get();
      final sections = await db.select(db.sections).get();
      expect(chapters, isEmpty, reason: '删小说应级联删章');
      expect(sections, isEmpty, reason: '删小说应级联删节，节 $sectionId 应消失');
    });
  });

  group('创作能量计数（首页转速/亮度数据源）', () {
    test('新小说创作量为 0；章节与挂靠灵感累加；魔毯灵感不计入', () async {
      final novel = await novelRepo.createNovel(title: '书', planet: 'earth');
      expect(await novelRepo.watchCreativeCount(novel.id).first, 0);

      final chapter = await novelRepo.createChapter(
        novelId: novel.id,
        title: '一章',
      );
      final section = await novelRepo.createSection(
        chapterId: chapter.id,
        title: '一节',
      );
      expect(
        await novelRepo.watchCreativeCount(novel.id).first,
        2,
        reason: '1 章 + 1 节',
      );

      final insp = await inspirationRepo.addInspiration('灵感');
      expect(
        await novelRepo.watchCreativeCount(novel.id).first,
        2,
        reason: '魔毯灵感不归属任何小说',
      );

      await inspirationRepo.assignToSection(insp.id, section.id);
      expect(
        await novelRepo.watchCreativeCount(novel.id).first,
        3,
        reason: '挂入小节后计入该小说',
      );
    });
  });

  group('卡堆重排序（阶段六·3）', () {
    test('reorderCards 按新顺序重写 card_order', () async {
      final sectionId = await createSectionChain();
      final a = await inspirationRepo.addInspiration('A');
      final b = await inspirationRepo.addInspiration('B');
      final c = await inspirationRepo.addInspiration('C');
      await inspirationRepo.assignToSection(a.id, sectionId);
      await inspirationRepo.assignToSection(b.id, sectionId);
      await inspirationRepo.assignToSection(c.id, sectionId);

      // 原顺序 A,B,C → 重排为 C,A,B
      await inspirationRepo.reorderCards([c.id, a.id, b.id]);

      final cards = await inspirationRepo.watchSectionCards(sectionId).first;
      expect(cards.map((e) => e.content).toList(), ['C', 'A', 'B']);
      expect(cards.map((e) => e.cardOrder).toList(), [0, 1, 2]);
    });
  });

  group('灵感生命周期（用户定稿四规则）', () {
    test('规则一：新灵感入池，section_id 为 NULL', () async {
      final insp = await inspirationRepo.addInspiration('一个灵感');
      expect(insp.sectionId, isNull);

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.single.content, '一个灵感');
    });

    test('魔毯按创建先后排序，最早的在最上（用户定稿：灵感一在顶）', () async {
      final t = DateTime(2026, 7, 1);
      await inspirationRepo.addInspiration('最早', createdAt: t);
      await inspirationRepo.addInspiration(
        '中间',
        createdAt: t.add(const Duration(minutes: 1)),
      );
      await inspirationRepo.addInspiration(
        '最新',
        createdAt: t.add(const Duration(minutes: 2)),
      );

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.map((e) => e.content).toList(), ['最早', '中间', '最新']);
    });

    test('魔毯内重排：reorderCards 重写池序并持久生效', () async {
      final a = await inspirationRepo.addInspiration('A');
      final b = await inspirationRepo.addInspiration('B');
      final c = await inspirationRepo.addInspiration('C');

      await inspirationRepo.reorderCards([c.id, a.id, b.id]);

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.map((e) => e.content).toList(), ['C', 'A', 'B']);

      // 重排后新速记的灵感仍排在末尾（card_order 接最大值）
      await inspirationRepo.addInspiration('D');
      final pool2 = await inspirationRepo.watchPool().first;
      expect(pool2.map((e) => e.content).toList(), ['C', 'A', 'B', 'D']);
    });

    test('规则二：拖入小节后从魔毯消失，最新拖入排最前（当前展示卡）', () async {
      final sectionId = await createSectionChain();
      final a = await inspirationRepo.addInspiration('灵感A');
      final b = await inspirationRepo.addInspiration('灵感B');

      await inspirationRepo.assignToSection(a.id, sectionId);
      await inspirationRepo.assignToSection(b.id, sectionId);

      final pool = await inspirationRepo.watchPool().first;
      expect(pool, isEmpty, reason: '拖入后应从魔毯消失');

      // 用户定稿：新拖入的成为卡包第一张（当前展示），故 B 在前
      final cards = await inspirationRepo.watchSectionCards(sectionId).first;
      expect(cards.map((e) => e.content).toList(), ['灵感B', '灵感A']);
      expect(cards.first.content, '灵感B', reason: '最后拖入的排第一 = 当前展示');
    });

    test('规则三：从小节删卡放回魔毯，排到魔毯顶部（核心用例）', () async {
      final sectionId = await createSectionChain();
      final t = DateTime(2026, 7, 1);
      await inspirationRepo.addInspiration('最早', createdAt: t);
      final mid = await inspirationRepo.addInspiration(
        '中间',
        createdAt: t.add(const Duration(minutes: 1)),
      );
      await inspirationRepo.addInspiration(
        '最新',
        createdAt: t.add(const Duration(minutes: 2)),
      );

      // “中间”拖入小节再放回：刚发生改动的放第一（用户定稿），
      // 方便用户马上处理刚放回的灵感
      await inspirationRepo.assignToSection(mid.id, sectionId);
      await inspirationRepo.removeFromSection(mid.id);

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.map((e) => e.content).toList(), [
        '中间',
        '最早',
        '最新',
      ], reason: '放回的灵感排到魔毯顶部');
    });

    test('规则四：在魔毯删除是真删，不可恢复', () async {
      final insp = await inspirationRepo.addInspiration('要删的');
      await inspirationRepo.deleteForever(insp.id);

      final all = await db.select(db.inspirations).get();
      expect(all, isEmpty, reason: '真删后表中无残留行');
    });

    test('删除小节时其下灵感放回魔毯（不陪葬）', () async {
      final sectionId = await createSectionChain();
      final insp = await inspirationRepo.addInspiration('挂在节上');
      await inspirationRepo.assignToSection(insp.id, sectionId);

      await novelRepo.deleteSection(sectionId);

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.single.content, '挂在节上', reason: '删节后灵感应回魔毯而非被删');
    });

    test('删除整部小说时，挂在其小节下的灵感也放回魔毯', () async {
      final sectionId = await createSectionChain();
      final insp = await inspirationRepo.addInspiration('挂在节上');
      await inspirationRepo.assignToSection(insp.id, sectionId);

      final novels = await novelRepo.watchNovels().first;
      await novelRepo.deleteNovel(novels.single.id);

      final pool = await inspirationRepo.watchPool().first;
      expect(
        pool.single.content,
        '挂在节上',
        reason: '级联删除链（小说→章→节）末端触发 set null，灵感存活',
      );
    });

    test('编辑魔毯中的灵感 → 跳到池顶部（用户定稿：刚改动的放第一）', () async {
      final t = DateTime(2026, 7, 1);
      await inspirationRepo.addInspiration('第一条', createdAt: t);
      final second = await inspirationRepo.addInspiration(
        '第二条',
        createdAt: t.add(const Duration(minutes: 1)),
      );

      // 编辑排在下面的"第二条" → 应跳到魔毯顶部，方便马上处理
      await inspirationRepo.updateContent(second.id, '改过的第二条');

      final pool = await inspirationRepo.watchPool().first;
      expect(pool.map((e) => e.content).toList(), ['改过的第二条', '第一条']);
      final edited = pool[0];
      expect(edited.updatedAt.isAfter(edited.createdAt), isTrue);
    });

    test('编辑挂在小节里的灵感：只改内容，不动卡堆顺序', () async {
      final sectionId = await createSectionChain();
      final a = await inspirationRepo.addInspiration('卡A');
      final b = await inspirationRepo.addInspiration('卡B');
      await inspirationRepo.assignToSection(a.id, sectionId);
      await inspirationRepo.assignToSection(b.id, sectionId);

      // 编辑卡堆第二张（A）：不应改变卡堆顺序
      await inspirationRepo.updateContent(a.id, '改过的卡A');

      final cards = await inspirationRepo.watchSectionCards(sectionId).first;
      expect(cards.map((e) => e.content).toList(), ['卡B', '改过的卡A']);
    });
  });
}
