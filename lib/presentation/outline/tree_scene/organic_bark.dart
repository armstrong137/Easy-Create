import 'package:flutter/material.dart';

/// 主干与承托枝共用树皮基色，体积明暗由各自截面处理。
const organicBarkTint = ColorFilter.matrix([
  1.8,
  0,
  0,
  0,
  12,
  0,
  1.6,
  0,
  0,
  9,
  0,
  0,
  1.3,
  0,
  4,
  0,
  0,
  0,
  1,
  0,
]);

/// 幼龄树皮细嫩，纹理对比度连续增强；成年保持既有材质。
ColorFilter organicBarkTintForAge(double age) {
  final value = age.clamp(0.0, 1.0);
  if (value == 1) return organicBarkTint;
  final detail = .3 + .7 * value * value * (3 - 2 * value);
  final smooth = 1 - detail;
  return ColorFilter.matrix([
    1.8 * detail, 0, 0, 0, 12 * detail + 104 * smooth,
    0, 1.6 * detail, 0, 0, 9 * detail + 116 * smooth,
    0, 0, 1.3 * detail, 0, 4 * detail + 66 * smooth,
    0, 0, 0, 1, 0,
  ]);
}
