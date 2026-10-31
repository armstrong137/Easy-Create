import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_camera_layout.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_scene.dart';

void main() {
  test('成熟历史近景的小节文字牌面不陷入主干', () {
    final submerged = <String>[];
    for (final count in [10, 30, 1000]) {
    final frame = OrganicTreeFrame(1, chapterCount: count.toDouble());
    final trunk = frame.trunkWood;
    for (final size in [const Size(360, 800), const Size(430, 932), const Size(480, 800)]) {
      for (final first in [0, count ~/ 2 - 1, count - 2]) {
      final layout = OrganicTreeCameraLayout(size, count, first, focusedChapter: first);
      for (var index = 0; index < 2; index++) {
        final rect = layout.sectionRectOutsideTrunk(
          layout.branchRect(right: true, index: index),
          layout.anchorFraction(right: true, index: index), frame);
        final title = Rect.fromLTWH(rect.right - rect.width * 394 / 1536,
          rect.top + rect.height * 268 / 1024,
          rect.width * 148 / 1536, rect.height * 400 / 1024);
        for (final point in [title.topLeft, title.topRight, title.bottomLeft,
          title.bottomRight, title.center]) {
          final native = (point - layout.projection.origin) / layout.projection.scale;
          if (trunk.contains(native)) submerged.add('$count 章 $first 行 $size 第 $index 块文字 $point');
        }
      }
    }
    }
    }
    expect(submerged, isEmpty, reason: '小节文字的四角和中心都不能落入主干');
  });
  test('单章幼树不因双牌密度规则放大，根冠保留在手机窗口内', () {
    const size = Size(430, 932);
    final layout = OrganicTreeCameraLayout(size, 1, 0, focusedChapter: 0);
    expect(layout.chapterScale, 1);
    final offset = (layout.focusY - size.height / 2).clamp(
      0.0,
      layout.sceneHeight - size.height,
    );
    for (final age in [0.0, .1, .2]) {
      final bounds = OrganicTreeFrame(age).wood.getBounds();
      final shift = Offset(size.width / 2 - layout.focusX, -offset);
      final topLeft = layout.projection.project(bounds.topLeft) + shift;
      final bottomRight = layout.projection.project(bounds.bottomRight) + shift;
      expect(topLeft.dx, greaterThanOrEqualTo(0));
      expect(topLeft.dy, greaterThanOrEqualTo(0));
      expect(bottomRight.dx, lessThanOrEqualTo(size.width));
      expect(bottomRight.dy, lessThanOrEqualTo(size.height));
    }
  });
  test('连续主树的章牌保持真实主干锚点和完整交互间距', () {
    for (final size in [
      const Size(360, 800),
      const Size(430, 932),
      const Size(910, 800),
    ]) {
      for (final count in [2, 10, 30, 1000]) {
        final first = count ~/ 2 - 1;
        final layout = OrganicTreeCameraLayout(
          size,
          count,
          first,
          focusedChapter: first + 1,
        );
        final previous = OrganicTreeCameraLayout(
          size,
          count,
          first - 1,
          focusedChapter: first,
        );
        final lower = layout.branchRect(right: false, index: 0);
        final upper = layout.branchRect(right: false, index: 1);
        expect(lower, previous.branchRect(right: false, index: 1));
        expect(
          (illustratedBranchHitRect(lower.size).shift(lower.topLeft).top -
            illustratedBranchHitRect(upper.size).shift(upper.topLeft).bottom) * layout.chapterScale,
          greaterThanOrEqualTo(12),
        );
        final point = OrganicTreeFrame.trunkPoint(
          OrganicTreeFrame.chapterFraction(first, count),
        );
        final root = Offset(
          lower.left + lower.width * .88,
          lower.top + lower.height * .7,
        );
        expect(
          (root - layout.projection.project(point)).distance *
              layout.chapterScale,
          lessThan(.001),
        );
        for (final right in [false, true]) {
          for (var index = 0; index < 2; index++) {
            final rect = layout.branchRect(right: right, index: index);
            final left =
                size.width / 2 +
                (rect.left - layout.focusX) * layout.chapterScale;
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
}
