import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 程序化星空背景：固定种子随机星点，整体亮度由创作能量驱动
///
/// [brightness] 取值见 core/creative_energy.dart（有上下限），
/// 星点位置/大小每次构建稳定不变（固定种子），只有亮度随创作量变化。
class Starfield extends StatelessWidget {
  const Starfield({super.key, required this.brightness});

  /// 全局星光亮度 [0,1]，由 starBrightness() 计算
  final double brightness;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarfieldPainter(brightness: brightness),
      size: Size.infinite,
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.brightness});

  final double brightness;

  /// 星点数量（暗淡星空，不追求繁星）
  static const _starCount = 180;

  /// 固定种子：保证星点分布在重绘间稳定
  static final List<_Star> _stars = _generateStars();

  static List<_Star> _generateStars() {
    final rng = math.Random(42);
    return List.generate(_starCount, (_) {
      return _Star(
        // 比例坐标，绘制时乘以实际尺寸
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.4 + rng.nextDouble() * 1.1,
        // 个体亮度差异：0.35~1.0，营造深浅层次
        glow: 0.35 + rng.nextDouble() * 0.65,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 深空背景：顶部近黑的深蓝 → 底部纯黑的微渐变
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [const Color(0xFF060A18), const Color(0xFF02030A)],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 星点：白色圆点，透明度 = 个体层次 × 全局创作亮度
    final starPaint = Paint();
    for (final star in _stars) {
      starPaint.color =
          Colors.white.withValues(alpha: (star.glow * brightness).clamp(0, 1));
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}

/// 单颗星点的静态属性（比例坐标）
class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.glow,
  });

  final double x;
  final double y;
  final double radius;
  final double glow;
}
