import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_gestures.dart';

void main() {
  test('手势归属在按下时锁定且跨中线不切换', () {
    final gestures = TreeSceneGestures();
    expect(gestures.begin(x: 80, width: 400), TreeGestureOwner.chapter);
    gestures.update(deltaY: 24, x: 360, width: 400);
    expect(gestures.owner, TreeGestureOwner.chapter);
    expect(gestures.end(), TreeGestureDirection.previous);
  });

  test('右侧上推只产生下一小节动作', () {
    final gestures = TreeSceneGestures();
    expect(gestures.begin(x: 300, width: 400), TreeGestureOwner.section);
    gestures.update(deltaY: -46, x: 40, width: 400);
    expect(gestures.end(), TreeGestureDirection.next);
  });

  test('不足阈值的抖动不会切换章或节', () {
    final gestures = TreeSceneGestures();
    gestures.begin(x: 120, width: 400);
    gestures.update(deltaY: 8, x: 130, width: 400);
    expect(gestures.end(), TreeGestureDirection.none);
  });

  test('拖拽坐标桥在一秒内不超过30次', () {
    var now = DateTime(2026);
    final sent = <(double, double)>[];
    final bridge = TreeDragBridge(
      now: () => now,
      send: (x, y) => sent.add((x, y)),
    );
    for (var index = 0; index < 100; index += 1) {
      bridge.update(x: index / 100, y: 0.5);
      now = now.add(const Duration(milliseconds: 10));
    }
    expect(sent.length, lessThanOrEqualTo(30));
  });
}
