import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
    carpetTrashPending.value = null;
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
      expect(carpetHeight(3), greaterThan(carpetHeight(0)));
      expect(carpetHeight(1000), lessThanOrEqualTo(kCarpetMaxHeight));
    });

    test('整槽显示：列表高度是卡槽整数倍，且不超可用空间（卡要么完整要么不显示）', () {
      // 溢出时（灵感多于可见槽数）高度须恰为 整槽数×槽高+顶部内边距
      final h = carpetHeight(1000);
      expect((h - kCarpetListTopPad) % kCarpetItemHeight, 0);
      // 屏幕剩余空间受限时同样整槽、且不超出可用空间（防止面板伸出屏幕底）
      final h2 = carpetHeight(1000, maxAvail: 300);
      expect((h2 - kCarpetListTopPad) % kCarpetItemHeight, 0);
      expect(h2, lessThanOrEqualTo(300));
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

  testWidgets('黑色星空背景下标题有浅色背板，文字不糊进背景', (tester) async {
    await pumpCarpet(tester, [fake(1, '深夜的旋律')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    final box = tester.widget<DecoratedBox>(find.byKey(const Key('魔毯标题背板')));
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xEFFFFDF6));
    expect(decoration.borderRadius, isNotNull);
  });

  test('展开态不能用整面板 opaque 命中层挡住首页星球点击', () {
    final src = File(
      'lib/presentation/outline/magic_carpet.dart',
    ).readAsStringSync();
    expect(
      src,
      isNot(contains('behavior: HitTestBehavior.opaque')),
      reason: '透明区域应露出并放过底层星球点击；收起请点右上角 X',
    );
  });

  test('垃圾桶删除确认由全局宿主托管，拖拽结束也不会丢失删除动作', () {
    final src = File(
      'lib/presentation/outline/magic_carpet.dart',
    ).readAsStringSync();
    expect(src, contains('carpetTrashPending'));
    expect(src, contains('class _TrashDeleteHost'));
    expect(src, contains('carpetTrashPending.value = widget.inspiration'));
    expect(src, contains('rootNavigatorKey'));
    expect(src, contains('deleteForever(inspiration.id)'));
    expect(src, isNot(contains('_confirmDelete()')));
  });

  test('魔毯小球素材必须是真透明背景，不能把灰底阴影带到星空里', () {
    final file = File('assets/textures/carpet_ball_clean.png');
    expect(file.existsSync(), isTrue);
    final image = img.decodePng(file.readAsBytesSync())!;
    var dirtyBottomPixels = 0;
    for (var y = (image.height * 0.80).round(); y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final avg = (p.r + p.g + p.b) / 3;
        final diff = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b) -
            [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
        if (p.a > 24 && avg > 80 && avg < 245 && diff < 35) {
          dirtyBottomPixels++;
        }
      }
    }
    expect(dirtyBottomPixels, lessThan(80));
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

  testWidgets('列表按传入顺序渲染（池序由仓库保证：先入池的在上）', (tester) async {
    await pumpCarpet(tester, [fake(1, '第一条'), fake(2, '第二条'), fake(3, '第三条')]);

    await tester.tap(find.byKey(const Key('魔毯小球')));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('第一条'));
    final third = tester.getTopLeft(find.text('第三条'));
    expect(first.dy, lessThan(third.dy), reason: '池序第一条在列表最上');
    expect(
      find.byKey(const Key('魔毯排序把手_1')),
      findsOneWidget,
      reason: '每行有排序把手',
    );
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
