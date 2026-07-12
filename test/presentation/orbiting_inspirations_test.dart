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

  Future<void> pumpOrbit(
    WidgetTester tester,
    List<Inspiration> items, {
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitingInspirations(
              items: items,
              orbitWidth: 300,
              enabled: enabled,
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

  testWidgets('灵感应像卫星一样环绕星球移动', (tester) async {
    await pumpOrbit(tester, [fake(1, 'A'), fake(2, 'B'), fake(3, 'C')]);

    final before = tester.getCenter(find.text('A'));
    await tester.pump(const Duration(seconds: 8));
    final after = tester.getCenter(find.text('A'));

    expect((after - before).distance, greaterThan(4));
  });

  testWidgets('关闭 enabled 时灵感保持静止，避免抢 3D 首帧', (tester) async {
    await pumpOrbit(tester, [
      fake(1, 'A'),
      fake(2, 'B'),
      fake(3, 'C'),
    ], enabled: false);

    final before = tester.getCenter(find.text('A'));
    await tester.pump(const Duration(seconds: 8));
    final after = tester.getCenter(find.text('A'));

    expect((after - before).distance, lessThan(0.1));
  });

  test('性能护栏：环绕灵感只用轻量动画，不再描边或 Opacity 离屏', () {
    expect(
      'AnimationController'.allMatches(source).length,
      lessThanOrEqualTo(2),
    );
    expect(source, contains('_controller.repeat()'));
    expect(source, contains('widget.enabled'));
    expect(source, contains('_orbitDirection'));
    expect(source, isNot(contains('PaintingStyle.stroke')));
    expect(source, isNot(contains('child: Opacity(')));
  });
}
