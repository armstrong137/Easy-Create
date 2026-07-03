import 'package:flutter/material.dart';

import '../../core/creative_energy.dart';

/// 星空背景：用户提供的四张银河摄影图，亮度递增（2026-07-03 定稿）
///
/// 创作能量联动：当前小说的灵感/章节越多，[brightness] 越高，
/// 星空切换到更亮的一档背景（切档时淡入淡出过渡）。
class Starfield extends StatelessWidget {
  const Starfield({super.key, required this.brightness});

  /// 全局星光亮度，由 core/creative_energy.starBrightness() 计算
  final double brightness;

  /// 亮度归一化后分四档，对应 starfield_1（最暗）~ starfield_4（最亮）
  int get _tier {
    final t = ((brightness - kStarBrightnessMin) /
            (kStarBrightnessMax - kStarBrightnessMin))
        .clamp(0.0, 1.0);
    return (t * 3.999).floor() + 1;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: Image.asset(
        'assets/textures/starfield_$_tier.jpg',
        // key 变化驱动 AnimatedSwitcher 做交叉淡入淡出
        key: ValueKey(_tier),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}
