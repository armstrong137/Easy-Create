import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 完整古树使用固定画幅，浏览章节只改变树干锚点和镜头位置。
class IllustratedTreeCameraLayout {
  IllustratedTreeCameraLayout(
    this.viewport,
    this.chapterCount,
    this.firstChapter,
  );

  final Size viewport;
  final int chapterCount;
  final int firstChapter;

  double get sceneHeight =>
      math.max(viewport.height * 1.6, viewport.width * 1672 / 941);
  double get sceneWidth => math.max(viewport.width, sceneHeight * 941 / 1672);
  double get _scale => math.max(viewport.width / 941, sceneHeight / 1672);
  double get _left => (sceneWidth - 941 * _scale) / 2;
  double get _top => sceneHeight - 1672 * _scale;
  double _anchorY(int chapterIndex) =>
      _top +
      (450 + 800 * chapterIndex / math.max(1, chapterCount - 1)) * _scale;
  double get _center =>
      (_anchorY(firstChapter) + _anchorY(firstChapter + 1)) / 2;
  double get chapterScale {
    final spacing = 800 * _scale / math.max(1, chapterCount - 1);
    final hitHeight = math.min(viewport.width * 0.5, 220.0) / 1.5;
    return math.max(1.0, (hitHeight + 12) / spacing);
  }

  double? get focusX => chapterScale == 1
      ? null
      : _left +
            (525 - 30 * (firstChapter + .5) / math.max(1, chapterCount - 1)) *
                _scale;
  double get focusY => _center - viewport.height * 0.1 / chapterScale;

  Rect branchRect({required bool right, required int index}) {
    final width = math.min(viewport.width * 0.5, 220.0) / chapterScale;
    final height = width / 1.5;
    final anchorY = right
        ? _center + (index - 0.5) * viewport.height * 0.22 / chapterScale
        : _anchorY(firstChapter + index);
    // 坐标来自完整树 v2 的树干内侧，枝基交给同源前景遮挡。
    final chapterPosition =
        (firstChapter + index) / math.max(1, chapterCount - 1);
    final trunkLeft = 510 - 30 * chapterPosition;
    final anchorX =
        _left + (trunkLeft + 15 + (right ? 15 : -15) / chapterScale) * _scale;
    return Rect.fromLTWH(
      anchorX - width * (right ? 0.12 : 0.88),
      anchorY - height * 0.7,
      width,
      height,
    );
  }
}
