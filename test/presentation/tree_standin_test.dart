import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_scene.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_standin.dart';

void main() {
  test('树龄映射到六张静态替身且边界受限', () {
    expect(illustratedTreeStageForNodeCount(-1), 0);
    expect(illustratedTreeStageForNodeCount(1), 1);
    expect(illustratedTreeStageForNodeCount(2), 2);
    expect(illustratedTreeStageForNodeCount(7), 4);
    expect(illustratedTreeStageForNodeCount(10), 5);
    expect(illustratedTreeStageForNodeCount(40), 5);
  });

  test('正式二维树龄素材使用同源高清插画', () {
    expect(
      illustratedTreeAssetForNodeCount(0),
      'assets/tree_scene/illustrated/age_0.png',
    );
    expect(
      illustratedTreeAssetForNodeCount(4),
      'assets/tree_scene/illustrated/age_3.png',
    );
    expect(
      illustratedTreeAssetForNodeCount(10),
      'assets/tree_scene/illustrated/age_5.png',
    );
  });

  testWidgets('正式二维树使用全屏覆盖和柔和阶段过渡', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 1280,
          height: 668,
          child: TreeStandin(stage: 0, growthRevision: 0),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, double.infinity);
    expect(image.height, double.infinity);
    expect(image.fit, BoxFit.contain);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });

  testWidgets('树枝牌保持真实枝条承托和竖排文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 360,
          height: 240,
          child: IllustratedBranchPlaque(
            title: '第十章',
            side: IllustratedBranchSide.left,
            selected: true,
            animateIn: false,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/tree_scene/illustrated/chapter_branch.png',
    );
    expect(find.text('第\n十\n章'), findsOneWidget);
    expect(find.byKey(const Key('选中枝牌光晕')), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });

  for (final side in IllustratedBranchSide.values) {
    testWidgets('枝牌${side.name}侧的选中金边和文字对齐原始牌面', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: IllustratedBranchPlaque(
                title: '第十一章',
                side: side,
                selected: true,
                animateIn: false,
              ),
            ),
          ),
        ),
      );
      final glow = find.byKey(const Key('选中枝牌光晕'));
      final paint = tester.widget<CustomPaint>(glow);
      final transform = tester.widget<Transform>(
        find.ancestor(of: glow, matching: find.byType(Transform)).first,
      );
      expect(
        transform.transform.storage[0],
        side == IllustratedBranchSide.left ? 1 : -1,
      );
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        paint.painter!.paint(Canvas(recorder), const Size(300, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 200);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(pixels.getUint8((90 * 300 + 43) * 4 + 3), greaterThan(20));
        expect(pixels.getUint8((90 * 300 + 100) * 4 + 3), 0);
        image.dispose();
        picture.dispose();
      });
      final plaque = tester.getRect(find.byType(IllustratedBranchPlaque));
      final text = tester.getRect(find.byKey(const Key('枝牌文字区')));
      final centerX = side == IllustratedBranchSide.left
          ? 320 / 1536
          : 1 - 320 / 1536;
      expect(text.center.dx - plaque.left, closeTo(300 * centerX, 0.01));
      expect(text.width, closeTo(300 * 148 / 1536, 0.01));
      expect(text.top - plaque.top, closeTo(200 * 268 / 1024, 0.01));
      expect(text.height, closeTo(200 * 400 / 1024, 0.01));
    });
  }
}
