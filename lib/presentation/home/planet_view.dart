import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 星球 shader 资源（program + 纹理），一次加载、全应用复用
class PlanetShaderAssets {
  const PlanetShaderAssets({required this.program, required this.texture});

  final ui.FragmentProgram program;
  final ui.Image texture;

  /// 从资产加载 shader 与指定行星纹理（planet 对应 `assets/textures/<planet>.jpg`）
  static Future<PlanetShaderAssets> load(String planet) async {
    final program = await ui.FragmentProgram.fromAsset('shaders/planet.frag');
    final bytes = await rootBundle.load('assets/textures/$planet.jpg');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return PlanetShaderAssets(program: program, texture: frame.image);
  }
}

/// 真实 3D 星球：FragmentShader 球面贴图 + 昼夜光照 + 自转
///
/// [spin] 为转速（圈/秒），来自 core/creative_energy.planetSpin：
/// 0 = 严格静止（零创作量），越大越快（调用方保证封顶）。
class PlanetView extends StatefulWidget {
  const PlanetView({
    super.key,
    required this.assets,
    required this.spin,
    required this.diameter,
  });

  final PlanetShaderAssets assets;

  /// 转速（圈/秒）
  final double spin;

  /// 星球直径（逻辑像素）
  final double diameter;

  @override
  State<PlanetView> createState() => _PlanetViewState();
}

class _PlanetViewState extends State<PlanetView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 当前自转角（弧度），跨帧累加
  double _rotation = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(PlanetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spin != widget.spin) _syncTicker();
  }

  /// 有转速才开 Ticker；静止时停帧省电
  void _syncTicker() {
    if (widget.spin > 0 && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (widget.spin <= 0 && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    setState(() {
      // 圈/秒 → 弧度/帧
      _rotation += widget.spin * dt * 2 * 3.14159265358979;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.diameter),
      painter: _PlanetPainter(
        program: widget.assets.program,
        texture: widget.assets.texture,
        rotation: _rotation,
      ),
    );
  }
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter({
    required this.program,
    required this.texture,
    required this.rotation,
  });

  final ui.FragmentProgram program;
  final ui.Image texture;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader()
      ..setFloat(0, size.width) // uSize.x
      ..setFloat(1, size.height) // uSize.y
      ..setFloat(2, rotation) // uRotation
      ..setImageSampler(0, texture); // uTexture

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PlanetPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.texture != texture;
}
