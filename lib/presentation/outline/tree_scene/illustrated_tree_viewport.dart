import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 树体、枝牌及热区共用场景；章节浏览平移，全景等比缩放，不作为成长动画。
class IllustratedTreeViewport extends StatefulWidget {
  const IllustratedTreeViewport({
    super.key,
    required this.sceneHeight,
    required this.focusY,
    required this.child,
    this.sceneWidth,
    this.overview = false,
    this.chapterScale = 1,
    this.focusX,
  }) : assert(sceneHeight > 0);

  final double sceneHeight;
  final double focusY;
  final Widget child;
  final double? sceneWidth;
  final bool overview;
  final double chapterScale;
  final double? focusX;

  @override
  State<IllustratedTreeViewport> createState() =>
      _IllustratedTreeViewportState();
}

class _IllustratedTreeViewportState extends State<IllustratedTreeViewport> {
  // 遮罩只在全景需要；移动同一子树，保留材质与生长控制器。
  final _sceneKey = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sceneHeight = widget.sceneHeight;
      final sceneWidth = widget.sceneWidth;
      final focusY = widget.focusY;
      final overview = widget.overview;
      final height = math.max(sceneHeight, constraints.maxHeight);
      final width = sceneWidth ?? constraints.maxWidth;
      final overviewScale = math.min(
        constraints.maxWidth / width,
        constraints.maxHeight / height,
      );
      final scale = overview ? overviewScale : widget.chapterScale;
      final maxOffset = math.max(0.0, height * scale - constraints.maxHeight);
      final targetY = overview
          ? -(constraints.maxHeight - height * overviewScale) / 2
          : (focusY * scale - constraints.maxHeight * 0.5).clamp(
              0.0,
              maxOffset,
            );
      final targetX = overview
          ? 0.0
          : ((widget.focusX ?? width / 2) - width / 2) * scale;
      final target = Offset(targetX, targetY);
      return ClipRect(
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(begin: target, end: target),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeInOutCubic,
          child: KeyedSubtree(key: _sceneKey, child: widget.child),
          builder: (context, offset, scene) => Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: (constraints.maxWidth - width) / 2 - offset.dx,
                width: width,
                top: -offset.dy,
                height: height,
                child: AnimatedScale(
                  scale: scale,
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
