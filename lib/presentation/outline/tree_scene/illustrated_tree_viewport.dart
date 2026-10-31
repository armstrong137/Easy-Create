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
    this.sceneTopInset = 0,
  }) : assert(sceneHeight > 0);

  final double sceneHeight;
  final double focusY;
  final Widget child;
  final double? sceneWidth;
  final bool overview;
  final double chapterScale;
  final double? focusX;
  // 新增顶部空间的场景像素；镜头补间保留稳定世界坐标。
  final double sceneTopInset;

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
      final verticalFade = widget.sceneTopInset == 0
          ? .08
          : .08 * (height - widget.sceneTopInset) / height;
      final overviewScale = math.min(
        constraints.maxWidth / width,
        constraints.maxHeight / height,
      );
      final scale = overview ? overviewScale : widget.chapterScale;
      final maxOffset = math.max(0.0, height * scale - constraints.maxHeight);
      final absoluteY = overview
          ? -(constraints.maxHeight - height * overviewScale) / 2
          : (focusY * scale - constraints.maxHeight * 0.5).clamp(
              0.0,
              maxOffset,
            );
      final targetY = absoluteY - widget.sceneTopInset * scale;
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
                  child: Transform.translate(
                    offset: Offset(0, -widget.sceneTopInset),
                    child: overview
                        ? ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: const [
                                Colors.transparent,
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0, verticalFade, 1 - verticalFade, 1],
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
              ),
            ],
          ),
        ),
      );
    },
  );
}
