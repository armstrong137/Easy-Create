import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_projection.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';

void main() {
  test('手机和宽屏枝牌根部都投影到真实树干上，保持母版比例', () {
    final frame = OrganicTreeFrame(1);
    for (final size in [
      const Size(430, 932),
      const Size(910, 800),
      const Size(941, 1672),
    ]) {
      final projection = OrganicTreeProjection(size);
      final source =
          projection.project(Offset.zero) &
          Size(941 * projection.scale, 1672 * projection.scale);
      expect(source.width / source.height, closeTo(941 / 1672, .00001));
      expect(source.left, greaterThanOrEqualTo(0));
      expect(source.top, greaterThanOrEqualTo(0));
      for (var index = 0; index < 10; index++) {
        final anchor = frame.chapterAnchor(index, 10)!;
        for (final right in [false, true]) {
          final rect = projection.branchRect(
            anchor,
            const Size(180, 120),
            right: right,
          );
          final root = Offset(
            rect.left + rect.width * (right ? .12 : .88),
            rect.top + rect.height * .7,
          );
          expect((root - projection.project(anchor)).distance, lessThan(.0001));
          final recovered = (root - projection.origin) / projection.scale;
          expect(frame.wood.contains(recovered), isTrue);
        }
      }
    }
  });
}
