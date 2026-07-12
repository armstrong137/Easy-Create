import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/inspiration_font.dart';
import '../../data/database/app_database.dart';

/// 环绕星球飞行的灵感文字（轻量 2.5D 卫星轨道）。
///
/// 只展示最近 [maxItems] 条：文字会按稳定随机轨道从不同方向绕行，
/// 且每条灵感固定顺/逆时针方向，避免每次 build 都跳位置。
class OrbitingInspirations extends StatefulWidget {
  const OrbitingInspirations({
    super.key,
    required this.items,
    required this.orbitWidth,
    required this.child,
    this.enabled = true,
    this.fade = false,
  });

  /// 魔毯灵感（新的在前），内部只取前 maxItems 条。
  final List<Inspiration> items;

  /// 轨道横向直径（约星球直径的 1.5 倍，比例和谐）。
  final double orbitWidth;

  /// 被环绕的星球。
  final Widget child;

  /// 是否运行动画。3D 场景未稳定或放大观察时暂停，避免抢首帧。
  final bool enabled;

  /// 淡出环绕文字（星球放大观察时让位）。
  final bool fade;

  /// 最多环绕几条，避免灵感增多后压垮星球帧率。
  static const maxItems = 5;

  @override
  State<OrbitingInspirations> createState() => _OrbitingInspirationsState();
}

class _OrbitingInspirationsState extends State<OrbitingInspirations>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 46),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrbitingInspirations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = widget.items
        .take(OrbitingInspirations.maxItems)
        .toList(growable: false);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final back = <Widget>[];
        final front = <Widget>[];
        for (var i = 0; i < visibleItems.length; i++) {
          final item = visibleItems[i];
          final seed = _orbitSeed(item);
          final direction = _orbitDirection(seed);
          final speed = 0.72 + _unit(seed, 17) * 0.56;
          final phase = _unit(seed, 29) * math.pi * 2;
          final theta =
              phase + _controller.value * math.pi * 2 * direction * speed;
          final x = math.cos(theta);
          final z = math.sin(theta);
          final depth = (z + 1) / 2;
          final scale = 0.70 + 0.36 * depth;
          final opacity = widget.fade ? 0.0 : 0.30 + 0.70 * depth;
          final tilt = 0.09 + _unit(seed, 43) * 0.13;
          final bob = math.sin(theta * 1.7 + phase) * widget.orbitWidth * 0.025;

          final text = RepaintBoundary(
            child: Transform.translate(
              offset: Offset(
                x * widget.orbitWidth * (0.43 + _unit(seed, 61) * 0.10),
                -z * widget.orbitWidth * tilt + bob,
              ),
              child: Transform.scale(
                scale: scale,
                child: _OrbitText(content: item.content, opacity: opacity),
              ),
            ),
          );

          (z > 0 ? front : back).add(text);
        }

        Widget layer(List<Widget> texts) =>
            Stack(alignment: Alignment.center, children: texts);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [layer(back), child!, layer(front)],
        );
      },
    );
  }
}

int _orbitSeed(Inspiration item) {
  var hash = item.id * 1000003 + item.content.length * 9176;
  for (final code in item.content.codeUnits.take(32)) {
    hash = 0x1fffffff & (hash * 33 + code);
  }
  return hash;
}

double _orbitDirection(int seed) => seed.isEven ? 1 : -1;

double _unit(int seed, int salt) {
  final mixed = 0x1fffffff & (seed * 1103515245 + salt * 12345);
  return mixed / 0x1fffffff;
}

/// 单条环绕文字：中文黑楷体 / 英文品牌斜体 + 轻量白色阴影轮廓，超长省略。
class _OrbitText extends StatelessWidget {
  const _OrbitText({required this.content, required this.opacity});

  final String content;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final brand = inspirationIsBrand(content);
    final style = TextStyle(
      fontFamily: brand ? 'EasyCreateBrand' : 'LXGWWenKai',
      fontStyle: brand ? FontStyle.italic : FontStyle.normal,
      fontSize: 15,
      fontWeight: brand ? FontWeight.w600 : FontWeight.w500,
      height: 1.2,
      color: Colors.black.withValues(alpha: opacity),
      shadows: [
        Shadow(
          color: Colors.white.withValues(alpha: opacity * 0.90),
          blurRadius: 2,
        ),
        Shadow(
          color: Colors.white.withValues(alpha: opacity * 0.55),
          blurRadius: 5,
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        content,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
