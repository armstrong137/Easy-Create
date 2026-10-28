import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/presentation/home/home_page.dart'
    show inspirationPoolProvider;
import 'package:novel_app/presentation/outline/magic_carpet.dart'
    show CarpetOverlay;
import 'package:novel_app/presentation/section/inspiration_card.dart';
import 'package:novel_app/presentation/section/section_page.dart';

/// 阶段六·1：小节页主区最新一张灵感卡（卡堆流照例 override）
void main() {
  Inspiration fake(int id, String content, int order) => Inspiration(
    id: id,
    content: content,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
    sectionId: 1,
    cardOrder: order,
  );

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpSection(WidgetTester tester, List<Inspiration> cards) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sectionCardsProvider.overrideWith(
            (ref, sectionId) => Stream.value(cards),
          ),
        ],
        child: const MaterialApp(
          home: SectionPage(sectionId: 1, initialTitle: '第一节'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSectionWithCarpet(
    WidgetTester tester,
    List<Inspiration> cards,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sectionCardsProvider.overrideWith(
            (ref, sectionId) => Stream.value(cards),
          ),
          inspirationPoolProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          builder: (context, child) => CarpetOverlay(child: child!),
          home: const SectionPage(sectionId: 1, initialTitle: '第一节'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragToCarpet(WidgetTester tester, Finder source) async {
    final from = tester.getCenter(source);
    final to = tester.getCenter(find.byKey(const Key('魔毯小球')));
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -4));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 真库造一条挂在节 1 的灵感（编辑/放回操作走真库）
  Future<Inspiration> seedCard(String content) async {
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
    final id = await db
        .into(db.inspirations)
        .insert(
          InspirationsCompanion.insert(
            content: content,
            createdAt: now,
            updatedAt: now,
            sectionId: const Value(1),
            cardOrder: 0,
          ),
        );
    return (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  testWidgets('空节显示邀请文案', (tester) async {
    await pumpSection(tester, const []);
    expect(find.textContaining('还没有灵感卡'), findsOneWidget);
  });

  testWidgets('主区只显示卡包第一张（当前展示卡），身后不露卡边', (tester) async {
    // watchSectionCards 按 card_order 升序：第一张 = 当前展示（用户定稿）
    await pumpSection(tester, [fake(1, '当前展示卡', 0), fake(2, '包里第二张', 1)]);

    expect(find.byKey(const Key('主区卡_1')), findsOneWidget);
    expect(find.text('当前展示卡'), findsOneWidget);
    expect(find.text('包里第二张'), findsNothing, reason: '主区只显示第一张，其余在卡片包里');
  });

  testWidgets('从魔毯拖一条灵感到小节页 → 挂进本节（用户定稿：图1 拖入落点）', (tester) async {
    // 真库造一条魔毯灵感（section_id 为空）
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
            content: '拖进小节的灵感',
            createdAt: now,
            updatedAt: now,
            cardOrder: 0,
          ),
        );
    final insp = Inspiration(
      id: inspId,
      content: '拖进小节的灵感',
      createdAt: now,
      updatedAt: now,
      cardOrder: 0,
    );

    // 卡堆流 override 空（避免真 drift 流挂 pending timer）；落点行为走真库，
    // 断言直接查库。页面上铺一个 Draggable 源模拟魔毯里的灵感。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sectionCardsProvider.overrideWith(
            (ref, sectionId) => Stream.value(const []),
          ),
        ],
        child: MaterialApp(
          home: Stack(
            children: [
              const SectionPage(sectionId: 1, initialTitle: '第一节'),
              // 模拟魔毯里的一条可拖灵感
              Align(
                alignment: Alignment.bottomCenter,
                child: Draggable<Inspiration>(
                  data: insp,
                  feedback: const SizedBox(width: 40, height: 20),
                  child: Container(
                    key: const Key('拖源'),
                    width: 40,
                    height: 20,
                    color: const Color(0xFF000000),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 从拖源拖到屏幕中央（小节页 body 落点）
    final from = tester.getCenter(find.byKey(const Key('拖源')));
    final to = tester.getCenter(find.byType(SectionPage));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveTo(to);
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pumpAndSettle();

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(inspId))).getSingle();
    expect(saved.sectionId, 1, reason: '拖到小节页应挂进本节');
  });

  testWidgets('点卡片包按钮展开全部卡片', (tester) async {
    await pumpSection(tester, [fake(1, '第一张卡', 0), fake(2, '最新的卡', 1)]);

    await tester.tap(find.byKey(const Key('卡片包按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('包内卡_1')), findsOneWidget);
    expect(find.byKey(const Key('包内卡_2')), findsOneWidget);
    expect(find.textContaining('卡片包 · 2 张'), findsOneWidget);
  });

  testWidgets('长按主区灵感卡拖到魔毯后放回灵感池', (tester) async {
    final card = await seedCard('从主区拖回魔毯');
    await pumpSectionWithCarpet(tester, [card]);

    await dragToCarpet(tester, find.byKey(Key('主区卡_${card.id}')));

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(card.id))).getSingle();
    expect(saved.sectionId, isNull, reason: '主区卡拖回魔毯后应脱离小节');
  });

  testWidgets('长按主区灵感卡即可放回灵感池', (tester) async {
    final card = await seedCard('主区长按直接放回');
    await pumpSectionWithCarpet(tester, [card]);

    await tester.longPress(find.byKey(Key('主区卡_${card.id}')));
    await tester.pumpAndSettle();

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(card.id))).getSingle();
    expect(saved.sectionId, isNull, reason: '主区卡长按后应直接脱离小节回到魔毯');
  });

  testWidgets('长按卡片包内灵感卡拖到魔毯后放回灵感池', (tester) async {
    final card = await seedCard('从卡片包拖回魔毯');
    await pumpSectionWithCarpet(tester, [card]);

    await tester.tap(find.byKey(const Key('卡片包按钮')));
    await tester.pumpAndSettle();
    await dragToCarpet(tester, find.byKey(Key('包内卡_${card.id}')));

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(card.id))).getSingle();
    expect(saved.sectionId, isNull, reason: '卡片包内卡拖回魔毯后应脱离小节');
  });

  testWidgets('长按卡片包内灵感卡即可放回灵感池', (tester) async {
    final card = await seedCard('卡包长按直接放回');
    await pumpSectionWithCarpet(tester, [card]);

    await tester.tap(find.byKey(const Key('卡片包按钮')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(Key('包内卡_${card.id}')));
    await tester.pumpAndSettle();

    final saved = await (db.select(
      db.inspirations,
    )..where((t) => t.id.equals(card.id))).getSingle();
    expect(saved.sectionId, isNull, reason: '卡片包内卡长按后应直接脱离小节回到魔毯');
  });

  testWidgets('超长内容省略显示（不撑爆屏幕）', (tester) async {
    final long = '灵感' * 3000; // 6000 字
    await pumpSection(tester, [fake(1, long, 0)]);

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(InspirationCard),
        matching: find.byType(Text),
      ),
    );
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, isNotNull);
  });

  group('全文编辑器（阶段六·4）', () {
    testWidgets('点主区卡进编辑器，改文返回自动保存', (tester) async {
      final card = await seedCard('初稿');
      await pumpSection(tester, [card]);

      await tester.tap(find.byKey(Key('主区卡_${card.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('全文编辑框')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('全文编辑框')), '重写后的正文，长夜将尽。');

      // 点自绘返回键 → PopScope 自动保存
      await tester.tap(find.byKey(const Key('编辑器返回')));
      await tester.pumpAndSettle();

      final saved = await (db.select(
        db.inspirations,
      )..where((t) => t.id.equals(card.id))).getSingle();
      expect(saved.content, '重写后的正文，长夜将尽。');
      // 同毫秒内保存时 updatedAt 可能等于 createdAt，故断言"不早于"
      expect(saved.updatedAt.isBefore(saved.createdAt), isFalse);
    });

    testWidgets('全文编辑失焦时保存正文且保持小节归属', (tester) async {
      final card = await seedCard('失焦前正文');
      await pumpSection(tester, [card]);
      await tester.tap(find.byKey(Key('主区卡_${card.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('全文编辑框')), '失焦后的正文');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final saved = await (db.select(db.inspirations)
        ..where((table) => table.id.equals(card.id))).getSingle();
      expect(saved.content, '失焦后的正文');
      expect(saved.sectionId, card.sectionId);
      expect(find.byKey(const Key('全文编辑框')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('全文编辑框')), card.content);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final restored = await (db.select(db.inspirations)
        ..where((table) => table.id.equals(card.id))).getSingle();
      expect(restored.content, card.content);
    });

    testWidgets('数万字长文本编辑器渲染不崩', (tester) async {
      final card = await seedCard('长' * 30000); // 3 万字
      await pumpSection(tester, [card]);

      await tester.tap(find.byKey(Key('主区卡_${card.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('全文编辑框')), findsOneWidget);
    });

    testWidgets('放回魔毯：确认后 section_id 置空、弹回小节页', (tester) async {
      final card = await seedCard('要放回的卡');
      await pumpSection(tester, [card]);

      await tester.tap(find.byKey(Key('主区卡_${card.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('放回魔毯按钮')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('放回魔毯确认按钮')));
      await tester.pumpAndSettle();

      final saved = await (db.select(
        db.inspirations,
      )..where((t) => t.id.equals(card.id))).getSingle();
      expect(saved.sectionId, isNull, reason: '放回魔毯而非删除');
      expect(find.byKey(const Key('全文编辑框')), findsNothing, reason: '放回后应弹回小节页');
    });
  });
}
