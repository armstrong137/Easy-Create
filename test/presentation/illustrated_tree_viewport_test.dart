import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_viewport.dart';

void main() {
  testWidgets('增长后的全景边缘渐隐不吞掉原始留白内的树冠', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: RepaintBoundary(
      key: const Key('全景像素验收'),
      child: const SizedBox(width: 300, height: 500,
        child: ColoredBox(color: Colors.white,
          child: IllustratedTreeViewport(sceneWidth: 300, sceneHeight: 4000,
            sceneTopInset: 3000, focusY: 3500, overview: true,
            child: ColoredBox(color: Color(0xFFFF0000))),
        ),
      ),
    ))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('全景像素验收')));
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = data!.buffer.asUint8List();
      final pixel = (15 * image.width + 150) * 4;
      expect(rgba[pixel], 255);
      expect(rgba[pixel + 1], lessThan(5), reason: '树冠安全留白之外应完整可见，不能随画布增高扩大渐隐带');
      image.dispose();
    });
  });
  testWidgets('顶部扩展画布时，已有枝牌不随场景原点跳动', (tester) async {
    Future<void> show(double inset) => tester.pumpWidget(MaterialApp(home: Center(
      child: SizedBox(width: 300, height: 500,
        child: IllustratedTreeViewport(sceneWidth: 600, sceneHeight: 1000 + inset,
          sceneTopInset: inset, focusX: 300, focusY: 700 + inset, chapterScale: 2,
          child: Stack(children: [Positioned(left: 280, top: 680 + inset,
            width: 40, height: 40, child: const ColoredBox(
              key: Key('固定世界枝牌'), color: Colors.green))]),
        ),
      ),
    )));
    await show(0);
    final before = tester.getRect(find.byKey(const Key('固定世界枝牌')));
    await show(800);
    for (final elapsed in [0, 100, 230, 460]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(tester.getRect(find.byKey(const Key('固定世界枝牌'))), before);
    }
  });
  testWidgets('近景放大围绕指定树干锚点并保持热区命中', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: const Key('近景窗口'),
            width: 300,
            height: 500,
            child: IllustratedTreeViewport(
              sceneWidth: 600,
              sceneHeight: 1500,
              focusX: 360,
              focusY: 700,
              chapterScale: 3,
              child: Stack(
                children: [
                  Positioned(
                    left: 360 - 20 / 3,
                    top: 700 - 20 / 3,
                    width: 40 / 3,
                    height: 40 / 3,
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: const ColoredBox(
                        key: Key('放大枝牌'),
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final window = tester.getRect(find.byKey(const Key('近景窗口')));
    final plaque = tester.getRect(find.byKey(const Key('放大枝牌')));
    expect(plaque.width, closeTo(40, .001));
    expect(plaque.center.dx, closeTo(window.center.dx, .001));
    expect(plaque.center.dy, closeTo(window.center.dy, .001));
    await tester.tap(find.byKey(const Key('放大枝牌')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('全景往返不重建树体状态或重播生长', (tester) async {
    var mounts = 0;
    Future<void> show(bool overview) => tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 500,
          child: IllustratedTreeViewport(
            sceneWidth: 600,
            sceneHeight: 1000,
            focusY: 700,
            overview: overview,
            child: _TrackedTree(onMount: () => mounts++),
          ),
        ),
      ),
    );
    await show(false);
    await tester.pumpAndSettle();
    await show(true);
    await tester.pumpAndSettle();
    await show(false);
    await tester.pumpAndSettle();
    expect(mounts, 1);
  });
  testWidgets('全景完整容纳原始画幅且缩放后的枝牌仍可点击', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: IllustratedTreeViewport(
              sceneWidth: 600,
              sceneHeight: 1000,
              focusY: 700,
              overview: true,
              child: ColoredBox(
                key: const Key('完整画幅'),
                color: Colors.brown,
                child: Center(
                  child: GestureDetector(
                    onTap: () => tapped++,
                    child: const SizedBox(
                      key: Key('全景枝牌'),
                      width: 100,
                      height: 80,
                      child: ColoredBox(color: Colors.green),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = tester.getRect(find.byKey(const Key('完整画幅')));
    expect(frame.width, closeTo(300, 0.01));
    expect(frame.height, closeTo(500, 0.01));
    await tester.tap(find.byKey(const Key('全景枝牌')));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('浏览只移动场景，枝牌与树体保持相对位置和点击命中', (tester) async {
    var tapped = 0;
    Future<void> show(double focusY) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: IllustratedTreeViewport(
              sceneHeight: 1500,
              focusY: focusY,
              child: Stack(
                children: [
                  const Positioned(
                    left: 140,
                    top: 0,
                    width: 20,
                    height: 1500,
                    child: ColoredBox(key: Key('树干'), color: Colors.brown),
                  ),
                  Positioned(
                    left: 40,
                    top: 700,
                    width: 100,
                    height: 70,
                    child: GestureDetector(
                      onTap: () => tapped++,
                      child: const ColoredBox(
                        key: Key('枝牌'),
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await show(735);
    await tester.pumpAndSettle();
    final trunk = tester.getRect(find.byKey(const Key('树干')));
    final plaque = tester.getRect(find.byKey(const Key('枝牌')));
    expect(trunk.height, 1500);
    expect(plaque.top - trunk.top, 700);
    await tester.tap(find.byKey(const Key('枝牌')));
    expect(tapped, 1);
    await show(850);
    await tester.pump(const Duration(milliseconds: 200));
    final movingTrunk = tester.getRect(find.byKey(const Key('树干')));
    final movingPlaque = tester.getRect(find.byKey(const Key('枝牌')));
    expect(movingTrunk.height, 1500);
    expect(movingPlaque.top - movingTrunk.top, closeTo(700, 0.001));
    expect(movingTrunk.top, lessThan(trunk.top));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('枝牌')));
    expect(tapped, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('根冠两端限制镜头且不让画幅出现空洞', (tester) async {
    Future<void> show(double focusY) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 500,
            child: IllustratedTreeViewport(
              sceneHeight: 1500,
              focusY: focusY,
              child: const ColoredBox(key: Key('场景'), color: Colors.brown),
            ),
          ),
        ),
      ),
    );
    await show(-500);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('场景'))).dy, 0);
    await show(2000);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byKey(const Key('场景'))).dy, 500);
    expect(tester.getSize(find.byKey(const Key('场景'))).height, 1500);
  });
}

class _TrackedTree extends StatefulWidget {
  const _TrackedTree({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_TrackedTree> createState() => _TrackedTreeState();
}

class _TrackedTreeState extends State<_TrackedTree> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.brown);
}
