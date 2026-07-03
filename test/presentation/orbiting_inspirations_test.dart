import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/presentation/home/orbiting_inspirations.dart';

/// 阶段三·4：环绕灵感文字 2.5D 轨道
///
/// 注意：组件内含 repeat() 无限动画，测试只能 pump 固定时长，
/// 严禁 pumpAndSettle（永不 settle 会超时）。
void main() {
  Inspiration fake(int id, String content) => Inspiration(
        id: id,
        content: content,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
        cardOrder: 0,
      );

  Future<void> pumpOrbit(
      WidgetTester tester, List<Inspiration> items) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitingInspirations(
              items: items,
              orbitWidth: 300,
              child: const SizedBox.square(
                  dimension: 200, key: Key('星球占位')),
            ),
          ),
        ),
      ),
    );
    // 推进一帧动画（不可 pumpAndSettle）
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('空灵感时只显示星球，无环绕文字', (tester) async {
    await pumpOrbit(tester, const []);

    expect(find.byKey(const Key('星球占位')), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('灵感文字环绕出现（描边+字身双层渲染）', (tester) async {
    await pumpOrbit(tester, [fake(1, '月光落在旧钢琴上')]);

    // 每条文字渲染两份：白描边层 + 黑字身层
    expect(find.text('月光落在旧钢琴上'), findsNWidgets(2));
  });

  testWidgets('只环绕最近 5 条，更早的不显示', (tester) async {
    final items = [for (var i = 1; i <= 7; i++) fake(i, '灵感$i')];
    await pumpOrbit(tester, items);

    expect(find.text('灵感1'), findsNWidgets(2), reason: '最近5条应显示');
    expect(find.text('灵感5'), findsNWidgets(2), reason: '第5条应显示');
    expect(find.text('灵感6'), findsNothing, reason: '第6条不应显示');
    expect(find.text('灵感7'), findsNothing);
  });

  testWidgets('公转推进若干帧不崩溃且文字仍在', (tester) async {
    await pumpOrbit(tester, [fake(1, 'A'), fake(2, 'B'), fake(3, 'C')]);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.text('A'), findsNWidgets(2));
    expect(find.text('C'), findsNWidgets(2));
  });
}
