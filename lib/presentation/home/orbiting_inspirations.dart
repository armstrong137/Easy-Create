import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/inspiration_font.dart';
import '../../data/database/app_database.dart';

/// 环绕星球飞行的灵感文字（2.5D 椭圆轨道）
///
/// 三维感实现（定稿方案）：
/// - 文字沿 x-z 平面圆轨道公转，z 决定前后：z>0 在星球前、z<0 在星球后
/// - 近大远小（缩放）+ 近实远虚（透明度）
/// - 遮挡：组件分两层渲染，后层文字 → [child]（星球）→ 前层文字
///
/// 只展示最近 [maxItems] 条（定稿"最近几条"，具体条数待阶段七终审）。
class OrbitingInspirations extends StatelessWidget {
  const OrbitingInspirations({
    super.key,
    required this.items,
    required this.orbitWidth,
    required this.child,
    this.fade = false,
  });

  /// 魔毯灵感（新的在前），内部只取前 maxItems 条
  final List<Inspiration> items;

  /// 轨道横向直径（约星球直径的 1.5 倍，比例和谐）
  final double orbitWidth;

  /// 被环绕的星球
  final Widget child;

  /// 淡出环绕文字（星球放大观察时让位，不喧宾夺主）
  final bool fade;

  /// 最多环绕几条（假设值，待终审调优）
  static const maxItems = 5;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(OrbitingInspirations.maxItems).toList();

    // 计算每条灵感的静态轨道位置，按 z 分前后两层。
    // 这里不再常驻 60fps 公转动画：3D 星球 iframe 与 Flutter 共用主线程，
    // 环绕文字逐帧重绘会挤掉星球帧，灵感从 0 变有时尤其明显。
    final back = <Widget>[];
    final front = <Widget>[];
    for (var i = 0; i < visibleItems.length; i++) {
      final theta = -math.pi / 6 + i * 2 * math.pi / visibleItems.length;
      final x = math.cos(theta); // [-1,1] 横向
      final z = math.sin(theta); // [-1,1] 前后（>0 在前）

      final depth = (z + 1) / 2; // 0=最远 1=最近
      final scale = 0.72 + 0.38 * depth; // 近大远小
      final opacity = 0.25 + 0.75 * depth; // 近实远虚

      final text = Transform.translate(
        offset: Offset(
          x * orbitWidth / 2,
          // 轨道纵向微倾斜：远端略高、近端略低，增强三维感
          -z * orbitWidth * 0.10,
        ),
        child: Transform.scale(
          scale: scale,
          child: _OrbitText(content: visibleItems[i].content, opacity: opacity),
        ),
      );

      (z > 0 ? front : back).add(text);
    }

    // 前后文字层各自包一层 Stack，外层恒为 3 个 children：
    // 文字跨前后边界时（back/front 条数变化）星球 child 的树位置不变。
    Widget layer(List<Widget> texts) => AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: fade ? 0 : 1,
      child: Stack(alignment: Alignment.center, children: texts),
    );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [layer(back), child, layer(front)],
    );
  }
}

/// 单条环绕文字：中文黑楷体 / 英文品牌斜体 + 轻量白色阴影轮廓，超长省略
class _OrbitText extends StatelessWidget {
  const _OrbitText({required this.content, required this.opacity});

  final String content;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    // 英文灵感用品牌斜体，与首页标题同款；中文落楷体
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
      // 文字不宽于轨道中央星球，比例和谐、避免喧宾夺主
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
