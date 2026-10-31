import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_scene.dart';

void main() {
  testWidgets('实验枝牌保留绘制尺寸，透明上下留白不截获指针', (tester) async {
    for (final enabled in [true, false]) {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 150,
              child: IllustratedBranchHitRegion(
                key: const Key('枝牌绘制范围'),
                enabled: enabled,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ColoredBox(color: Colors.brown),
                ),
              ),
            ),
          ),
        ),
      );
      final bounds = tester.getRect(find.byKey(const Key('枝牌绘制范围')));
      expect(bounds.size, const Size(200, 150));
      await tester.tapAt(bounds.topCenter + const Offset(0, 4));
      await tester.tapAt(bounds.bottomCenter - const Offset(0, 4));
      expect(taps, enabled ? 0 : 2, reason: '旧路径保持完整热区，实验路径只收紧透明留白');
      await tester.tapAt(bounds.center);
      expect(taps, enabled ? 1 : 3);
    }
  });
}
