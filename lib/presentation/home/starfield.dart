import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/creative_energy.dart';
import 'starfield_motion.dart';

/// 星空背景：用户四张银河摄影图打底（亮度四档），叠程序化动态层
/// （星点呼吸闪烁 + 远近双层视差漂移 + 低频流星），阶段八 P2-2。
///
/// 创作能量联动：当前小说的灵感/章节越多，[brightness] 越高——
/// 照片切换到更亮一档，动态星点也随之更亮。
class Starfield extends StatelessWidget {
  const Starfield({super.key, required this.brightness, this.animated = true});

  /// 全局星光亮度，由 core/creative_energy.starBrightness() 计算
  final double brightness;

  /// 动态层开关：测试环境/低端机回退纯静态照片
  /// （无限 Ticker 会让 widget 测试的 pumpAndSettle 挂死——项目教训）
  final bool animated;

  /// 亮度归一化 0~1
  double get _t =>
      ((brightness - kStarBrightnessMin) /
              (kStarBrightnessMax - kStarBrightnessMin))
          .clamp(0.0, 1.0);

  /// 亮度分四档，对应 starfield_1（最暗）~ starfield_4（最亮）
  int get _tier => (_t * 3.999).floor() + 1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: Image.asset(
            'assets/textures/starfield_$_tier.jpg',
            // key 变化驱动 AnimatedSwitcher 做交叉淡入淡出
            key: ValueKey(_tier),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        if (animated) _DynamicStarLayer(brightness: _t),
      ],
    );
  }
}

/// 动态星层：Ticker 驱动 elapsed，经 ValueNotifier 只重绘本层
/// （不 setState 整棵星空树，照片层零重建）
class _DynamicStarLayer extends StatefulWidget {
  const _DynamicStarLayer({required this.brightness});

  /// 归一化亮度 0~1（能量越高星点越亮）
  final double brightness;

  @override
  State<_DynamicStarLayer> createState() => _DynamicStarLayerState();
}

class _DynamicStarLayerState extends State<_DynamicStarLayer>
    with SingleTickerProviderStateMixin {
  final _elapsed = ValueNotifier<double>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (e) => _elapsed.value = e.inMicroseconds / 1e6,
    )..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        key: const Key('动态星空层'),
        painter: _StarPainter(elapsed: _elapsed, brightness: widget.brightness),
      ),
    );
  }
}

/// 单颗星点的静态属性（固定种子生成，帧间不变）
class _Star {
  const _Star(this.x, this.y, this.radius, this.index);

  final double x; // 0~1
  final double y; // 0~1
  final double radius; // 逻辑像素
  final int index; // 闪烁相位种子
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.elapsed, required this.brightness})
    : super(repaint: elapsed);

  final ValueNotifier<double> elapsed;
  final double brightness;

  /// 远层（慢、小、密）与近层（快、大、疏）——双层视差
  static final List<_Star> _far = _makeStars(seed: 11, count: 54, rMin: 0.5, rMax: 1.1);
  static final List<_Star> _near = _makeStars(seed: 23, count: 26, rMin: 1.0, rMax: 1.9);

  static List<_Star> _makeStars({
    required int seed,
    required int count,
    required double rMin,
    required double rMax,
  }) {
    return List.generate(count, (i) {
      return _Star(
        hashRand(seed, i * 3),
        hashRand(seed, i * 3 + 1),
        rMin + hashRand(seed, i * 3 + 2) * (rMax - rMin),
        i,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = elapsed.value;
    // 能量越高星点越亮（0.45~1.0），照片底本身也在换更亮档
    final energy = 0.45 + 0.55 * brightness;

    // 远层 40 秒横漂一屏、近层 16 秒：速度差即视差
    _paintLayer(canvas, size, _far, t, driftOffset(t, 1 / 40), 31, energy * 0.75);
    _paintLayer(canvas, size, _near, t, driftOffset(t, 1 / 16), 47, energy);

    _paintMeteor(canvas, size, t, energy);
  }

  void _paintLayer(
    Canvas canvas,
    Size size,
    List<_Star> stars,
    double t,
    double drift,
    int twinkleSeed,
    double alpha,
  ) {
    final paint = Paint();
    for (final s in stars) {
      final x = ((s.x + drift) % 1.0) * size.width;
      final y = s.y * size.height;
      final a = (twinkle(t, twinkleSeed, s.index) * alpha).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), s.radius, paint);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, double t, double energy) {
    final m = meteorAt(t);
    if (m == null) return;
    // 划过 + 两端渐隐（sin 包络）；方向固定斜下 25°
    final fade = math.sin(m.progress * math.pi);
    const angle = 25 * math.pi / 180;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final travel = m.length * 2.2 * size.width;
    final head = Offset(m.startX * size.width, m.startY * size.height) +
        dir * (m.progress * travel);
    final tail = head - dir * (m.length * size.width);

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.9 * fade * energy),
        ],
      ).createShader(Rect.fromPoints(tail, head));
    canvas.drawLine(tail, head, paint);
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.brightness != brightness || old.elapsed != elapsed;
}
