import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/presentation/home/orbiting_inspirations.dart';

/// 阶段三：环绕灵感文字 2.5D 轨道。
void main() {
  final source = File(
    'lib/presentation/home/orbiting_inspirations.dart',
  ).readAsStringSync();

  Inspiration fake(int id, String content) => Inspiration(
    id: id,
    content: content,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
    cardOrder: 0,
  );

  Future<void> pumpOrbit(WidgetTester tester, List<Inspiration> items) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitingInspirations(
              items: items,
              orbitWidth: 300,
              child: const SizedBox.square(dimension: 200, key: Key('星球占位')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('空灵感时只显示星球，无环绕文字', (tester) async {
    await pumpOrbit(tester, const []);

    expect(find.byKey(const Key('星球占位')), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('灵感文字环绕出现：单 Text + 阴影轮廓，避免双层描边开销', (tester) async {
    await pumpOrbit(tester, [fake(1, '月光落在旧钢琴上')]);

    expect(find.text('月光落在旧钢琴上'), findsOneWidget);
  });

  testWidgets('只环绕最近 5 条，更早的不显示', (tester) async {
    final items = [for (var i = 1; i <= 7; i++) fake(i, '灵感$i')];
    await pumpOrbit(tester, items);

    expect(find.text('灵感1'), findsOneWidget, reason: '最近 5 条应显示');
    expect(find.text('灵感5'), findsOneWidget, reason: '第 5 条应显示');
    expect(find.text('灵感6'), findsNothing, reason: '第 6 条不应显示');
    expect(find.text('灵感7'), findsNothing);
  });

  testWidgets('多次刷新不崩溃且文字仍在', (tester) async {
    await pumpOrbit(tester, [fake(1, 'A'), fake(2, 'B'), fake(3, 'C')]);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(find.text('A'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  test('性能护栏：环绕灵感不再常驻逐帧动画或描边双绘制', () {
    expect(source, isNot(contains('AnimationController')));
    expect(source, isNot(contains('..repeat()')));
    expect(source, isNot(contains('PaintingStyle.stroke')));
    expect(source, isNot(contains('child: Opacity(')));
  });
}
