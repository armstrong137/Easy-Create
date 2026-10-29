import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_trunk.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_standin.dart';

void main() {
  test('实验前景只遮挡枝根，保留落在树干前方的文字牌面', () {
    final clip = IllustratedTreeTrunkClipper(
      stage: 5,
      completeCrown: true,
      branchNecks: [
        Rect.fromCenter(center: const Offset(500, 1000), width: 40, height: 30),
      ],
    ).getClip(const Size(941, 1672));
    expect(clip.contains(const Offset(500, 1000)), isTrue);
    expect(clip.contains(const Offset(500, 950)), isFalse);
    expect(clip.getBounds().width, lessThanOrEqualTo(40));
    expect(clip.getBounds().height, lessThanOrEqualTo(30));
  });
  testWidgets('未解码的新阶段不能沿新轮廓显示旧树干', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: IllustratedTreeTrunk(stage: 5)),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/tree_scene/illustrated/age_5.png'),
        tester.element(find.byType(IllustratedTreeTrunk)),
      ),
    );
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await const AssetImage('assets/tree_scene/illustrated/age_4.png').evict();
    await tester.pumpWidget(
      const MaterialApp(home: IllustratedTreeTrunk(stage: 4)),
    );
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      isNull,
      reason: '阶段4解码前不能遗留阶段5树干',
    );
  });

  testWidgets('同源前景在生长发光期间也不改变树干像素', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/tree_scene/illustrated/age_5.png'),
        tester.element(find.byType(SizedBox)),
      ),
    );
    Future<List<int>> capture(bool foreground) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const Key('同源'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const TreeStandin(
                  stage: 5,
                  growthRevision: 1,
                  showGrowthLight: false,
                ),
                if (foreground) const IllustratedTreeTrunk(stage: 5),
                const IllustratedTreeGrowthLight(growthRevision: 1),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      return (await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('同源')),
        );
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List().toList();
        image.dispose();
        return bytes;
      }))!;
    }

    final background = await capture(false);
    final composed = await capture(true);
    var maxDifference = 0;
    for (var i = 0; i < background.length; i++) {
      final difference = (background[i] - composed[i]).abs();
      if (difference > maxDifference) maxDifference = difference;
    }
    expect(maxDifference, lessThanOrEqualTo(1), reason: '前景仅改变遮挡关系，不应出现亮度边界');
  });

  testWidgets('树干遮挡枝基但保留外侧枝条和点击', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 430,
            height: 932,
            child: RepaintBoundary(
              key: const Key('合成'),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps += 1,
                    child: const ColoredBox(color: Color(0xFFFF00FF)),
                  ),
                  const IllustratedTreeTrunk(stage: 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/tree_scene/illustrated/age_5.png'),
        tester.element(find.byType(IllustratedTreeTrunk)),
      );
    });
    await tester.pump(const Duration(milliseconds: 16));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('合成')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> pixel(int x, int y) => List.generate(
        3,
        (channel) => pixels.getUint8((y * image.width + x) * 4 + channel),
      );
      expect(pixel(215, 460), isNot([255, 0, 255]), reason: '枝基应在树干后');
      expect(pixel(30, 460), [255, 0, 255], reason: '外侧牌面不得被背景覆盖');
      image.dispose();
    });
    await tester.tapAt(tester.getCenter(find.byKey(const Key('合成'))));
    expect(taps, 1, reason: '前景不得截获点击');
  });

  test('树干轮廓沿原图取景，不随宽屏和竖屏错位', () {
    const clipper = IllustratedTreeTrunkClipper(stage: 5);
    for (final size in [const Size(430, 932), const Size(910, 800)]) {
      final path = clipper.getClip(size);
      expect(path.contains(Offset(size.width / 2, size.height / 2)), isTrue);
      expect(path.contains(Offset(10, size.height / 2)), isFalse);
    }
  });
}
