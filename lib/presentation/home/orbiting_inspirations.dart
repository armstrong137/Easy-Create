import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';

/// 环绕星球飞行的灵感文字（2.5D 椭圆轨道）
///
/// 三维感实现（定稿方案）：
/// - 文字沿 x-z 平面圆轨道公转，z 决定前后：z>0 在星球前、z<0 在星球后
/// - 近大远小（缩放）+ 近实远虚（透明度）
/// - 遮挡：组件分两层渲染，后层文字 → [child]（星球）→ 前层文字
///
/// 只展示最近 [maxItems] 条（定稿"最近几条"，具体条数待阶段七终审）。
class OrbitingInspirations extends StatefulWidget {
  const OrbitingInspirations({
    super.key,
    required this.items,
    required this.orbitWidth,
    required this.child,
  });

  /// 魔毯灵感（新的在前），内部只取前 maxItems 条
  final List<Inspiration> items;

  /// 轨道横向直径（约星球直径的 1.5 倍，比例和谐）
  final double orbitWidth;

  /// 被环绕的星球
  final Widget child;

  /// 最多环绕几条（假设值，待终审调优）
  static const maxItems = 5;

  /// 公转一圈的时长
  static const orbitPeriod = Duration(seconds: 36);

  @override
  State<OrbitingInspirations> createState() => _OrbitingInspirationsState();
}

class _OrbitingInspirationsState extends State<OrbitingInspirations>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OrbitingInspirations.orbitPeriod,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.take(OrbitingInspirations.maxItems).toList();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value * 2 * math.pi;

        // 计算每条灵感的轨道位置，按 z 分前后两层
        final back = <Widget>[];
        final front = <Widget>[];
        for (var i = 0; i < items.length; i++) {
          // 均匀分布相位，随时间公转
          final theta = phase + i * 2 * math.pi / items.length;
          final x = math.cos(theta); // [-1,1] 横向
          final z = math.sin(theta); // [-1,1] 前后（>0 在前）

          final depth = (z + 1) / 2; // 0=最远 1=最近
          final scale = 0.72 + 0.38 * depth; // 近大远小
          final opacity = 0.25 + 0.75 * depth; // 近实远虚

          final text = Transform.translate(
            offset: Offset(
              x * widget.orbitWidth / 2,
              // 轨道纵向微倾斜：远端略高、近端略低，增强三维感
              -z * widget.orbitWidth * 0.10,
            ),
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: _OrbitText(content: items[i].content),
              ),
            ),
          );

          (z > 0 ? front : back).add(text);
        }

        return Stack(
          alignment: Alignment.center,
          children: [...back, widget.child, ...front],
        );
      },
    );
  }
}

/// 单条环绕文字：加粗黑楷体 + 细白描边（可读性方案，待终审），超长省略
class _OrbitText extends StatelessWidget {
  const _OrbitText({required this.content});

  final String content;

  static const _style = TextStyle(
    fontFamily: 'LXGWWenKai',
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // 文字不宽于轨道中央星球，比例和谐、避免喧宾夺主
      constraints: const BoxConstraints(maxWidth: 150),
      child: Stack(
        children: [
          // 底层：细白描边（在暗星空与亮星球上都保证轮廓）
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.white,
            ),
          ),
          // 上层：纯黑字身
          Text(
            content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style.copyWith(color: Colors.black),
          ),
        ],
      ),
    );
  }
}
