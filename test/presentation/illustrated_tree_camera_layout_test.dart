import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_camera_layout.dart';

void main() {
  test('同一章节切换浏览窗口时保留固定树干锚点', () {
    for (final size in [
      const Size(360, 800),
      const Size(430, 932),
      const Size(910, 800),
    ]) {
      final latest = IllustratedTreeCameraLayout(size, 10, 8);
      final previous = IllustratedTreeCameraLayout(size, 10, 7);
      expect(latest.sceneHeight, previous.sceneHeight);
      expect(
        latest.branchRect(right: false, index: 0),
        previous.branchRect(right: false, index: 1),
      );
      expect(previous.focusY, lessThan(latest.focusY));
    }
  });

  test('十章窗口中的两块文字牌面保留垂直间隔', () {
    for (final size in [
      const Size(360, 800),
      const Size(430, 932),
      const Size(910, 800),
    ]) {
      for (var first = 0; first < 9; first++) {
        final layout = IllustratedTreeCameraLayout(size, 10, first);
        final upper = layout.branchRect(right: false, index: 0);
        final lower = layout.branchRect(right: false, index: 1);
        // 对应正式枝牌文字区，不能只验证外层窗口有两个节点。
        expect(
          upper.top + upper.height * 668 / 1024,
          lessThan(lower.top + lower.height * 268 / 1024),
        );
      }
    }
  });
}
