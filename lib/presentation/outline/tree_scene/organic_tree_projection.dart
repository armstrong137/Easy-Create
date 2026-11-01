import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 连续树体、枝牌和热区使用同一母版到场景坐标变换。
class OrganicTreeProjection {
  // 扩展两侧几何空间，保留原主干与根部坐标，不横向拉伸树体。
  static const nativeBounds = Rect.fromLTWH(-100, 0, 1200, 1672);
  static final nativeSize = nativeBounds.size;
  OrganicTreeProjection(Size scene, {double upperExtent = 0}) {
    scale = math.min(scene.width / nativeSize.width,
        scene.height / (nativeSize.height + upperExtent));
    origin = Offset(
      (scene.width - nativeSize.width * scale) / 2 - nativeBounds.left * scale,
      (scene.height - (nativeSize.height + upperExtent) * scale) / 2 + upperExtent * scale,
    );
  }

  late final double scale;
  late final Offset origin;

  Offset project(Offset point) => origin + point * scale;

  Rect branchRect(Offset treeAnchor, Size plaqueSize, {required bool right}) {
    final anchor = project(treeAnchor);
    return Rect.fromLTWH(
      anchor.dx - plaqueSize.width * (right ? .12 : .88),
      anchor.dy - plaqueSize.height * .7,
      plaqueSize.width,
      plaqueSize.height,
    );
  }
}
