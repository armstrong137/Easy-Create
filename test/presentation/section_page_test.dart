import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
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

  testWidgets('点卡片包按钮展开全部卡片', (tester) async {
    await pumpSection(tester, [fake(1, '第一张卡', 0), fake(2, '最新的卡', 1)]);

    await tester.tap(find.byKey(const Key('卡片包按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('包内卡_1')), findsOneWidget);
    expect(find.byKey(const Key('包内卡_2')), findsOneWidget);
    expect(find.textContaining('卡片包 · 2 张'), findsOneWidget);
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
