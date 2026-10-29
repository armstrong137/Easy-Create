import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_camera_layout.dart';

void main() {
  test('密集章节近景保留牌面可读尺寸和间隔，树体画幅不随章数拉长', () {
    for (final size in [
      const Size(360, 800),
      const Size(430, 932),
      const Size(910, 800),
    ]) {
      final sparse = IllustratedTreeCameraLayout(size, 10, 0);
      for (final count in [30, 100, 1000]) {
        final layout = IllustratedTreeCameraLayout(size, count, count ~/ 2);
        final previous = IllustratedTreeCameraLayout(
          size,
          count,
          count ~/ 2 - 1,
        );
        final upper = layout.branchRect(right: false, index: 0);
        final lower = layout.branchRect(right: false, index: 1);
        expect(layout.sceneHeight, sparse.sceneHeight);
        expect(upper, previous.branchRect(right: false, index: 1));
        expect(
          upper.width * layout.chapterScale,
          closeTo(
            sparse.branchRect(right: false, index: 0).width *
                sparse.chapterScale,
            .001,
          ),
        );
        final gap = (lower.top - upper.bottom) * layout.chapterScale;
        expect(gap, greaterThanOrEqualTo(11.999));
        for (final right in [false, true]) {
          for (var index = 0; index < 2; index++) {
            final rect = layout.branchRect(right: right, index: index);
            final left =
                size.width / 2 +
                (rect.left - layout.focusX!) * layout.chapterScale;
            expect(left, greaterThanOrEqualTo(0));
            expect(
              left + rect.width * layout.chapterScale,
              lessThanOrEqualTo(size.width),
            );
          }
        }
      }
    }
  });
  test('宽屏完整画幅不因 cover 再次裁掉树冠', () {
    final layout = IllustratedTreeCameraLayout(const Size(910, 800), 10, 0);
    expect(layout.sceneWidth / layout.sceneHeight, closeTo(941 / 1672, 0.001));
  });
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
