import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/carpet_constants.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/presentation/home/home_page.dart'
    show inspirationPoolProvider;
import 'package:novel_app/presentation/outline/magic_carpet.dart';

/// 阶段五·1+2：魔毯缩球/展开与列表（灵感池流照例 override）
void main() {
  Inspiration fake(int id, String content) => Inspiration(
    id: id,
    content: content,
    createdAt: DateTime(2026, 7, 1).add(Duration(minutes: id)),
    updatedAt: DateTime(2026, 7, 1),
    cardOrder: 0,
  );

  tearDown(() {
    carpetDragging.value = null;
    carpetTucked.value = false;
  });

  Future<void> pumpCarpet(WidgetTester tester, List<Inspiration> pool) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inspirationPoolProvider.overrideWith((ref) => Stream.value(pool)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topRight, child: MagicCarpet()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('高度伸缩 carpetHeight', () {
    test('有上下限：零灵感取下限，海量灵感封顶', () {
      expect(carpetHeight(0), kCarpetMinHeight);
      expect(carpetHeight(2), greaterThan(carpetHeight(0)));
      expect(carpetHeight(1000), kCarpetMaxHeight);
    });

    test('魔毯视觉尺寸足够醒目', () {
      expect(kCarpetBallSize, greaterThanOrEqualTo(88));
      expect(kCarpetMinHeight, greaterThanOrEqualTo(170));
      expect(kCarpetMaxHeight, greaterThanOrEqualTo(420));
    });
  });

  testWidgets('初始为缩球态，点击展开显示列表', (tester) async {
    await pumpCarpet(tester, [fake(1, '深夜的旋律')]);

    expect(find.byKey(const Key('魔毯小球')), findsOneWidget);
    expect(find.text('深夜的旋律'), findsNothing, reason: '缩球态不显示列表');

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    expect(find.text('深夜的旋律'), findsOneWidget);
    expect(find.textContaining('灵感魔毯 · 1'), findsOneWidget);
  });

  testWidgets('展开态整体高度足够容纳大尺寸魔毯横幅', (tester) async {
    await pumpCarpet(tester, [fake(1, '深夜的旋律')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MagicCarpet)).height,
      greaterThanOrEqualTo(420),
    );
  });

  testWidgets('点收起按钮缩回小球', (tester) async {
    await pumpCarpet(tester, [fake(1, 'A')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('魔毯收起按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('魔毯小球')), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('收起时先播放反向卷回帧，再回到小球', (tester) async {
    await pumpCarpet(tester, [fake(1, '反向卷回')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('魔毯收起按钮')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.text('反向卷回'),
      findsOneWidget,
      reason: '反向卷回动画期间仍应保持展开面板，而不是瞬间切回小球',
    );
    expect(find.byKey(const Key('魔毯小球')), findsNothing);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('魔毯小球')), findsOneWidget);
    expect(find.text('反向卷回'), findsNothing);
  });

  testWidgets('空魔毯展开显示邀请文案', (tester) async {
    await pumpCarpet(tester, const []);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    expect(find.textContaining('魔毯空空如也'), findsOneWidget);
  });

  testWidgets('列表按传入顺序渲染（灵感池已保证新的在前）', (tester) async {
    await pumpCarpet(tester, [fake(3, '最新'), fake(2, '中间'), fake(1, '最早')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    final newest = tester.getTopLeft(find.text('最新'));
    final oldest = tester.getTopLeft(find.text('最早'));
    expect(newest.dy, lessThan(oldest.dy), reason: '新灵感在列表上方');
  });

  testWidgets('拖拽中外部收起魔毯会清理拖拽态', (tester) async {
    final pool = StreamController<List<Inspiration>>();
    addTearDown(pool.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [inspirationPoolProvider.overrideWith((ref) => pool.stream)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: MagicCarpet(key: magicCarpetKey),
            ),
          ),
        ),
      ),
    );
    pool.add([fake(1, '会被拖走的灵感')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('魔毯灵感_1'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(-8, 8));
    await tester.pump();
    expect(carpetDragging.value?.id, 1, reason: '测试应先进入拖拽态');

    magicCarpetKey.currentState?.collapse();
    await tester.pump(const Duration(milliseconds: 40));

    expect(carpetDragging.value, isNull, reason: '外部收起时必须同步清理拖拽态');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
