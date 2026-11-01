import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'illustrated_tree_camera_layout.dart';
import 'organic_tree_projection.dart';
import 'organic_tree_study.dart';
import 'organic_branch.dart';
import 'organic_tree_canopy.dart';

/// 连续主树的镜头使用真实弧长锚点，复用统一场景与全景浏览机制。
class OrganicTreeCameraLayout extends IllustratedTreeCameraLayout {
  OrganicTreeCameraLayout(
    super.viewport,
    super.chapterCount,
    super.firstChapter, {
    required this.focusedChapter,
  });

  final int focusedChapter;
  bool get inCanopy => focusedChapter >= 10;
  int get visibleChapterCount => inCanopy ? 1 : 2;
  double get _baseSceneHeight => math.max(
    viewport.height * 1.6,
    viewport.width *
        OrganicTreeProjection.nativeSize.height /
        OrganicTreeProjection.nativeSize.width,
  );
  @override
  double get sceneWidth => math.max(
    viewport.width,
    _baseSceneHeight *
        OrganicTreeProjection.nativeSize.width /
        OrganicTreeProjection.nativeSize.height,
  );
  double get upperExtent =>
      OrganicTreeFrame.upperExtentFor(chapterCount.toDouble());
  double get sceneTopInset =>
      upperExtent * sceneWidth / OrganicTreeProjection.nativeSize.width;
  @override
  double get sceneHeight => _baseSceneHeight + sceneTopInset;
  OrganicTreeProjection get projection => OrganicTreeProjection(
    Size(sceneWidth, sceneHeight),
    upperExtent: upperExtent,
  );

  Offset get _center => inCanopy
      ? projection.project(OrganicTreeFrame.chapterPoint(focusedChapter))
      : (projection.project(
                  OrganicTreeFrame.trunkPoint(
                    OrganicTreeFrame.chapterFraction(
                      firstChapter,
                      chapterCount,
                    ),
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
  double get chapterScale => inCanopy ? _canopyScale : 1;

  double get _canopyScale {
    var radius = OrganicBranchPainter.radiusAt(.72, 1, 92, .025);
    var branch = OrganicTreeFrame.canopyBranch(focusedChapter);
    while (true) {
      radius *=
          OrganicCanopyBranch.rootRatio *
          OrganicBranchPainter.radiusAt(
            OrganicCanopyBranch.attachment,
            1,
            1,
            OrganicCanopyBranch.tipRatio,
          );
      if (branch.parent == null) break;
      branch = OrganicTreeFrame.canopyBranch(branch.parent! + 10);
    }
    // 保留母枝体积，近景不因深层细枝而放大成木质墙面。
    return (4 / (radius * projection.scale)).clamp(1.0, 2.0);
  }

  @override
  double get focusX => _center.dx;

  @override
  double get focusY => _center.dy - viewport.height * .1 / chapterScale;

  double _trunkFraction({required bool right, required int index}) => right
      ? OrganicTreeFrame.chapterFraction(focusedChapter, chapterCount) +
            (index - .5) *
                viewport.height *
                .22 /
                (OrganicTreeFrame.trunkLength * projection.scale * chapterScale)
      : OrganicTreeFrame.chapterFraction(firstChapter + index, chapterCount);

  OrganicTreeAttachment? attachment({
    required bool right,
    required int index,
    required OrganicTreeFrame frame,
  }) {
    if (inCanopy) return frame.chapterAttachment(focusedChapter);
    final fraction = _trunkFraction(right: right, index: index);
    final point = frame.anchorAt(fraction);
    return point == null
        ? null
        : (
            point: point,
            radius: frame.trunkRadiusAt(fraction),
            wood: frame.trunkWood,
          );
  }

  @override
  Rect branchRect({required bool right, required int index}) {
    final width = math.min(viewport.width * .5, 220.0) / chapterScale;
    var anchor = projection.project(
      inCanopy
          ? OrganicTreeFrame.chapterPoint(focusedChapter)
          : OrganicTreeFrame.trunkPoint(
              _trunkFraction(right: right, index: index),
            ),
    );
    if (inCanopy && right) {
      anchor += Offset(0, (index - .5) * viewport.height * .22 / chapterScale);
    } else if (!inCanopy && !right && chapterCount > 1) {
      // 牌面为阅读让位，枝根仍由同帧母枝坐标单独连接，不放大粗主干。
      anchor = Offset(anchor.dx, _center.dy + (.5 - index) * viewport.height * .22);
    }
    return Rect.fromLTWH(
      anchor.dx - width * (right ? .12 : .88),
      anchor.dy - width / 1.5 * .7,
      width,
      width / 1.5,
    );
  }

  /// 右侧牌面避开同帧母干；枝根仍留在母干内，牌面不越过近景屏幕边缘。
  Rect sectionRectOutsideTrunk(Rect rect, int index, OrganicTreeFrame frame) {
    const titleRatio = 1 - 320 / 1536;
    if (inCanopy) return rect;
    final radius =
        attachment(right: true, index: index, frame: frame)!.radius *
        projection.scale;
    final clearance = rect.width * .12 + 4 / chapterScale;
    final needed = radius + clearance - rect.width * (titleRatio - .12);
    final available =
        focusX +
        viewport.width / (2 * chapterScale) -
        (rect.left + rect.width * titleRatio + clearance);
    return rect.shift(Offset(needed.clamp(0.0, math.max(0.0, available)), 0));
  }
}
