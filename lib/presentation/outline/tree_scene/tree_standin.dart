import 'package:flutter/material.dart';

import 'illustrated_tree_scene.dart';

class TreeStandin extends StatelessWidget {
  const TreeStandin({
    super.key,
    required this.stage,
    required this.growthRevision,
    this.completeCrown = false,
    this.showGrowthLight = true,
  });

  final int stage;
  final int growthRevision;
  final bool completeCrown;
  final bool showGrowthLight;

  @override
  Widget build(BuildContext context) {
    final asset = completeCrown && stage == 5
        ? 'assets/tree_scene/illustrated/mature_complete.png'
        : illustratedTreeAssetForStage(stage);
    return ColoredBox(
      color: const Color(0xFFFDF6EC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            image: true,
            label: '魔树成长场景',
            child: LayoutBuilder(
              builder: (context, constraints) => Image.asset(
                asset,
                key: ValueKey(asset),
                width: double.infinity,
                height: double.infinity,
                fit: constraints.maxWidth / constraints.maxHeight > 0.85
                    ? BoxFit.contain
                    : BoxFit.cover,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
          if (showGrowthLight)
            IllustratedTreeGrowthLight(growthRevision: growthRevision),
        ],
      ),
    );
  }
}

/// 树图、枝条和主干前景上方统一绘制一次，避免接缝处重复发光。
class IllustratedTreeGrowthLight extends StatelessWidget {
  const IllustratedTreeGrowthLight({super.key, required this.growthRevision});

  final int growthRevision;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TweenAnimationBuilder<double>(
      key: ValueKey('魔树能量_$growthRevision'),
      tween: Tween(begin: 0.42, end: 0),
      duration: const Duration(milliseconds: 1100),
      builder: (context, opacity, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 0.72),
            radius: 0.62,
            colors: [
              const Color(0xFFF3B832).withValues(alpha: opacity),
              const Color(0x00F3B832),
            ],
          ),
        ),
      ),
    ),
  );
}
