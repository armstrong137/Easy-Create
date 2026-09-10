import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 树体、枝牌及热区必须都放在 child 内，浏览仅平移整个场景。
class IllustratedTreeViewport extends StatelessWidget {
  const IllustratedTreeViewport({
    super.key,
    required this.sceneHeight,
    required this.focusY,
    required this.child,
  }) : assert(sceneHeight > 0);

  final double sceneHeight;
  final double focusY;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = math.max(sceneHeight, constraints.maxHeight);
      final maxOffset = height - constraints.maxHeight;
      final target = (focusY - constraints.maxHeight * 0.5).clamp(
        0.0,
        maxOffset,
      );
      return ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: target, end: target),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeInOutCubic,
          child: child,
          builder: (context, offset, scene) => Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: -offset.clamp(0.0, maxOffset),
                height: height,
                child: scene!,
              ),
            ],
          ),
        ),
      );
    },
  );
}
