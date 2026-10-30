import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'illustrated_tree_camera_layout.dart';
import 'organic_tree_projection.dart';
import 'organic_tree_study.dart';

/// 连续主树的镜头使用真实弧长锚点，复用统一场景与全景浏览机制。
class OrganicTreeCameraLayout extends IllustratedTreeCameraLayout {
  OrganicTreeCameraLayout(
    super.viewport,
    super.chapterCount,
    super.firstChapter, {
    required this.focusedChapter,
  });

  final int focusedChapter;
  OrganicTreeProjection get projection =>
      OrganicTreeProjection(Size(sceneWidth, sceneHeight));

  Offset get _center =>
      (projection.project(
            OrganicTreeFrame.trunkPoint(
              OrganicTreeFrame.chapterFraction(firstChapter, chapterCount),
            ),
          ) +
          projection.project(
            OrganicTreeFrame.trunkPoint(
              OrganicTreeFrame.chapterFraction(
                math.min(firstChapter + 1, math.max(0, chapterCount - 1)),
                chapterCount,
              ),
            ),
          )) /
      2;

  @override
  double get chapterScale => chapterCount <= 1
      ? 1
      : math.max(
          1.0,
          (math.min(viewport.width * .5, 220) / 1.5 + 12) /
              (900 * .72 / math.max(9, chapterCount - 1) * projection.scale),
        );

  @override
  double get focusX => _center.dx;

  @override
  double get focusY => _center.dy - viewport.height * .1 / chapterScale;

  double anchorFraction({required bool right, required int index}) => right
      ? OrganicTreeFrame.chapterFraction(focusedChapter, chapterCount) +
            (index - .5) *
                viewport.height *
                .22 /
                (900 * projection.scale * chapterScale)
      : OrganicTreeFrame.chapterFraction(firstChapter + index, chapterCount);

  @override
  Rect branchRect({required bool right, required int index}) {
    final width = math.min(viewport.width * .5, 220.0) / chapterScale;
    final anchor = projection.project(
      OrganicTreeFrame.trunkPoint(anchorFraction(right: right, index: index)),
    );
    return Rect.fromLTWH(
      anchor.dx - width * (right ? .12 : .88),
      anchor.dy - width / 1.5 * .7,
      width,
      width / 1.5,
    );
  }
}
