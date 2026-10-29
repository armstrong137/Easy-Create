import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_viewport.dart';

void main() {
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
