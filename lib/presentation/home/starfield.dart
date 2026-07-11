import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/creative_energy.dart';
import 'starfield_motion.dart';

/// 星空背景（阶段八 P2-2）：GPU 分形星云 shader 持续演变的动态宇宙
/// + 流星层；shader 加载前/失败/低端回退为用户四档银河摄影图。
///
/// 创作能量联动：当前小说的灵感/章节越多，[brightness] 越高——
/// 星云更亮、星场更密、（回退照片也切更亮档）。
class Starfield extends StatelessWidget {
  const Starfield({
    super.key,
    required this.brightness,
    this.animated = true,
    this.evolveSpeed = 1,
  });

  /// 全局星光亮度，由 core/creative_energy.starBrightness() 计算
  final double brightness;

  /// 宇宙演化速度倍率（core/creative_energy.nebulaEvolveSpeed，
  /// 全局章+节+灵感总量驱动：写得越多宇宙演变越"快进"）
  final double evolveSpeed;

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
        // 照片底：shader 加载期间与回退路径的背景（shader 就绪后被其遮住）
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
        if (animated) NebulaBackground(energy: _t, evolve: evolveSpeed),
        if (animated) _MeteorLayer(brightness: _t),
      ],
    );
  }
}

/// 星云 shader 程序（全局加载一次，热身后常驻）
final _nebulaProgram = ui.FragmentProgram.fromAsset('shaders/nebula.frag');

/// 星云层限到约 30fps：它是全屏 shader，长期满帧会和 3D 星球抢 GPU。
const kNebulaFrameInterval = Duration(milliseconds: 33);

/// 动态宇宙层：分形星云持续演变（nebula.frag），Ticker 驱动 uTime。
class NebulaBackground extends StatefulWidget {
  const NebulaBackground({
    super.key,
    required this.energy,
    required this.evolve,
  });

  /// 归一化创作能量 0~1（星云亮度/星场密度）
  final double energy;

  /// 演化速度倍率
  final double evolve;

  @override
  State<NebulaBackground> createState() => _NebulaBackgroundState();
}

class _NebulaBackgroundState extends State<NebulaBackground>
    with SingleTickerProviderStateMixin {
  final _elapsed = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// 管线预热：首帧只画 1×1（触发 GPU program 编译），下一帧再铺全屏。
  /// 直接全屏首帧会因编译卡一下（用户反馈"刚进去背景卡一下"）
  bool _warmed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      if (e - _lastTick < kNebulaFrameInterval) return;
      _lastTick = e;
      _elapsed.value = e.inMicroseconds / 1e6;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _nebulaProgram,
      builder: (context, snap) {
        final program = snap.data;
        // 未就绪/失败：留照片底（下层），不占位
        if (program == null) return const SizedBox.shrink();
        final painter = _NebulaPainter(
          shader: program.fragmentShader(),
          elapsed: _elapsed,
          energy: widget.energy,
          evolve: widget.evolve,
        );
        if (!_warmed) {
          // 预热帧渲染后立即切全屏（照片底还在，无视觉缺口）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _warmed = true);
          });
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1,
              height: 1,
              child: CustomPaint(painter: painter),
            ),
          );
        }
        return IgnorePointer(
          child: CustomPaint(key: const Key('星云演化层'), painter: painter),
        );
      },
    );
  }
}

class _NebulaPainter extends CustomPainter {
  _NebulaPainter({
    required this.shader,
    required this.elapsed,
    required this.energy,
    required this.evolve,
  }) : super(repaint: elapsed);

  final ui.FragmentShader shader;
  final ValueNotifier<double> elapsed;
  final double energy;
  final double evolve;

  @override
  void paint(Canvas canvas, Size size) {
    // uniform 顺序与 nebula.frag 声明一致：uSize, uTime, uEnergy, uEvolve
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, elapsed.value)
      ..setFloat(3, energy)
      ..setFloat(4, evolve);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_NebulaPainter old) =>
      old.energy != energy ||
      old.evolve != evolve ||
      old.elapsed != elapsed ||
      old.shader != shader;
}

/// 流星层：低频流星划过（调度逻辑见 starfield_motion.dart），叠在星云之上
class _MeteorLayer extends StatefulWidget {
  const _MeteorLayer({required this.brightness});

  /// 归一化亮度 0~1
  final double brightness;

  @override
  State<_MeteorLayer> createState() => _MeteorLayerState();
}

class _MeteorLayerState extends State<_MeteorLayer>
    with SingleTickerProviderStateMixin {
  final _elapsed = ValueNotifier<double>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _elapsed.value = e.inMicroseconds / 1e6)
      ..start();
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
        painter: _MeteorPainter(
          elapsed: _elapsed,
          brightness: widget.brightness,
        ),
      ),
    );
  }
}

class _MeteorPainter extends CustomPainter {
  _MeteorPainter({required this.elapsed, required this.brightness})
    : super(repaint: elapsed);

  final ValueNotifier<double> elapsed;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final t = elapsed.value;
    final energy = 0.45 + 0.55 * brightness;
    final m = meteorAt(t);
    if (m == null) return;
    // 划过 + 两端渐隐（sin 包络）；方向固定斜下 25°
    final fade = math.sin(m.progress * math.pi);
    const angle = 25 * math.pi / 180;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final travel = m.length * 2.2 * size.width;
    final head =
        Offset(m.startX * size.width, m.startY * size.height) +
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
  bool shouldRepaint(_MeteorPainter old) =>
      old.brightness != brightness || old.elapsed != elapsed;
}
