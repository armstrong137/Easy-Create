import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
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

  Future<void> pumpSection(
      WidgetTester tester, List<Inspiration> cards) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sectionCardsProvider.overrideWith(
              (ref, sectionId) => Stream.value(cards)),
        ],
        child: const MaterialApp(
          home: SectionPage(sectionId: 1, initialTitle: '第一节'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空节显示邀请文案', (tester) async {
    await pumpSection(tester, const []);
    expect(find.textContaining('还没有灵感卡'), findsOneWidget);
  });

  testWidgets('主区只显示最新一张卡（card_order 最大）', (tester) async {
    await pumpSection(tester, [
      fake(1, '第一张卡', 0),
      fake(2, '最新的卡', 1),
    ]);

    expect(find.byKey(const Key('主区卡_2')), findsOneWidget);
    expect(find.text('最新的卡'), findsOneWidget);
    expect(find.text('第一张卡'), findsNothing, reason: '主区默认只显示最新一张');
  });

  testWidgets('点卡片包按钮展开全部卡片', (tester) async {
    await pumpSection(tester, [
      fake(1, '第一张卡', 0),
      fake(2, '最新的卡', 1),
    ]);

    await tester.tap(find.byKey(const Key('卡片包按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('包内卡_1')), findsOneWidget);
    expect(find.byKey(const Key('包内卡_2')), findsOneWidget);
    expect(find.textContaining('卡片包 · 2 张'), findsOneWidget);
  });

  testWidgets('超长内容省略显示（不撑爆屏幕）', (tester) async {
    final long = '灵感' * 3000; // 6000 字
    await pumpSection(tester, [fake(1, long, 0)]);

    final text = tester.widget<Text>(find.descendant(
      of: find.byType(InspirationCard),
      matching: find.byType(Text),
    ));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, isNotNull);
  });
}
