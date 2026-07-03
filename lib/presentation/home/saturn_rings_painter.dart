import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'planet_view.dart';

/// 土星视图：3D 自转球体 + 静态光环贴层（用户定稿方案）
///
/// 三明治结构：后半环（球后）→ 球 → 前半环（球前），环倾斜静置。
class SaturnView extends StatelessWidget {
  const SaturnView({
    super.key,
    required this.assets,
    required this.spin,
    required this.diameter,
  });

  final PlanetShaderAssets assets;
  final double spin;

  /// 球体直径；环画布为其 1.9 倍
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final ringSize = Size.square(diameter * 1.9);
    return SizedBox.square(
      dimension: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 后半环（被球遮挡的部分）
          OverflowBox(
            maxWidth: ringSize.width,
            maxHeight: ringSize.height,
            child: CustomPaint(
                size: ringSize, painter: SaturnRingsPainter(front: false)),
          ),
          PlanetView(assets: assets, spin: spin, diameter: diameter),
          // 前半环（横跨球面的部分）
          OverflowBox(
            maxWidth: ringSize.width,
            maxHeight: ringSize.height,
            child: CustomPaint(
                size: ringSize, painter: SaturnRingsPainter(front: true)),
          ),
        ],
      ),
    );
  }
}

/// 土星光环 painter：透视椭圆环带（静态贴层，2026-07-03 用户定稿方案：
/// 球体 3D 自转、光环不随球转）
///
/// 分前后两半绘制：后半被星球遮挡（画在球下层）、前半横跨球面（球上层）。
/// 配色从用户土星素材取样：米色/浅驼色环带 + 深褐色卡西尼缝。
class SaturnRingsPainter extends CustomPainter {
  SaturnRingsPainter({required this.front});

  /// true = 只画前半环（球前），false = 只画后半环（球后）
  final bool front;

  /// 环带（相对星球半径的内外比例 + 颜色透明度），由内到外
  static const _bands = [
    (1.25, 1.45, Color(0xFFB8A98C), 0.85),
    (1.46, 1.52, Color(0xFF4A4038), 0.9), // 卡西尼缝（深）
    (1.53, 1.78, Color(0xFFCDbfA3), 0.8),
    (1.79, 1.88, Color(0xFF8A7B64), 0.55),
  ];

  /// 环平面倾角带来的纵向压扁比
  static const _flatten = 0.30;

  /// 环整体绕屏幕法线的倾斜角（弧度，模拟素材的斜置观感）
  static const _tilt = -0.28;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final planetR = size.width / 2 / 1.9; // 星球半径（环最大 1.88R 内切画布）

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_tilt);

    // 前/后半环裁剪：环带的上半（y<0）在球后，下半在球前
    final clip = Path()
      ..addRect(front
          ? Rect.fromLTRB(-size.width, 0, size.width, size.height)
          : Rect.fromLTRB(-size.width, -size.height, size.width, 0));
    canvas.clipPath(clip);

    for (final (inner, outer, color, alpha) in _bands) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (outer - inner) * planetR
        ..color = color.withValues(alpha: alpha);
      final mid = (inner + outer) / 2 * planetR;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset.zero, width: mid * 2, height: mid * 2 * _flatten),
        paint,
      );
    }

    // 环带内侧细线纹理：几圈半透明细环增强"密纹"质感
    final rng = math.Random(11);
    for (var i = 0; i < 9; i++) {
      final rr = (1.28 + rng.nextDouble() * 0.55) * planetR;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset.zero, width: rr * 2, height: rr * 2 * _flatten),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFF6B5E4C)
              .withValues(alpha: 0.25 + rng.nextDouble() * 0.2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SaturnRingsPainter oldDelegate) =>
      oldDelegate.front != front;
}
