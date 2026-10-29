import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 连续树体、枝牌和热区使用同一母版到场景坐标变换。
class OrganicTreeProjection {
  OrganicTreeProjection(Size scene) {
    scale = math.min(scene.width / 941, scene.height / 1672);
    origin = Offset(
      (scene.width - 941 * scale) / 2,
      (scene.height - 1672 * scale) / 2,
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
