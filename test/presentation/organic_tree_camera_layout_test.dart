import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_camera_layout.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';

void main() {
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
          (lower.top - upper.bottom) * layout.chapterScale,
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
