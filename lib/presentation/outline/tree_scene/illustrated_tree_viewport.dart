import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 树体、枝牌及热区共用场景；章节浏览平移，全景等比缩放，不作为成长动画。
class IllustratedTreeViewport extends StatelessWidget {
  const IllustratedTreeViewport({
    super.key,
    required this.sceneHeight,
    required this.focusY,
    required this.child,
    this.sceneWidth,
    this.overview = false,
  }) : assert(sceneHeight > 0);

  final double sceneHeight;
  final double focusY;
  final Widget child;
  final double? sceneWidth;
  final bool overview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = math.max(sceneHeight, constraints.maxHeight);
      final width = sceneWidth ?? constraints.maxWidth;
      final overviewScale = math.min(
        constraints.maxWidth / width,
        constraints.maxHeight / height,
      );
      final maxOffset = height - constraints.maxHeight;
      final target = overview
          ? -(constraints.maxHeight - height * overviewScale) / 2
          : (focusY - constraints.maxHeight * 0.5).clamp(0.0, maxOffset);
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
                left: (constraints.maxWidth - width) / 2,
                width: width,
                top: -offset,
                height: height,
                child: AnimatedScale(
                  scale: overview ? overviewScale : 1,
                  alignment: Alignment.topCenter,
                  duration: const Duration(milliseconds: 460),
                  curve: Curves.easeInOutCubic,
                  child: overview
                      ? ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, 0.08, 0.92, 1],
                          ).createShader(bounds),
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0, 0.06, 0.94, 1],
                            ).createShader(bounds),
                            child: scene!,
                          ),
                        )
                      : scene!,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
