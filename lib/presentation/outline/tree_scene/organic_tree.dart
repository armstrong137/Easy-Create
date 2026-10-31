import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'organic_tree_study.dart';

/// 连续主树的运行时容器；树龄只由创作进度传入，与浏览镜头无关。
class OrganicTree extends StatefulWidget {
  const OrganicTree({super.key, required this.age, this.foregroundBuilder});

  final double age;
  // 前景只借用树皮；图片生命周期由树体管理，不能由枝条释放。
  final Widget Function(BuildContext, OrganicTreeFrame, ui.Image)?
      foregroundBuilder;

  @override
  State<OrganicTree> createState() => _OrganicTreeState();
}

class _OrganicTreeState extends State<OrganicTree> {
  late final Future<List<ui.Image>> _materials;
  List<ui.Image> _images = [];

  @override
  void initState() {
    super.initState();
    _materials = _loadMaterials();
  }

  Future<List<ui.Image>> _loadMaterials() async {
    final images = await Future.wait([
      _load('assets/tree_scene/illustrated/bark_detail.png', 1024),
      _load('assets/tree_scene/illustrated/leaf_detail.png', 512),
    ], cleanUp: (image) => image.dispose());
    if (mounted) {
      _images = images;
    } else {
      for (final image in images) {
        image.dispose();
      }
    }
    return images;
  }

  Future<ui.Image> _load(String asset, int width) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: width,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  void dispose() {
    for (final image in _images) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ui.Image>>(
    future: _materials,
    builder: (context, snapshot) {
      if (snapshot.hasError) throw snapshot.error!;
      if (!snapshot.hasData) {
        return const ColoredBox(color: Color(0xFFF4D9A5));
      }
      final materials = snapshot.requireData;
      final age = widget.age.clamp(0.0, 1.0);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: age, end: age),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1400),
        curve: Curves.easeInOutCubic,
        builder: (context, currentAge, _) {
          final painter = OrganicTreeStudyPainter(
            currentAge,
            materials[0],
            materials[1],
          );
          final foreground = widget.foregroundBuilder?.call(
            context,
            painter.frame,
            materials[0],
          );
          return RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: currentAge != age,
              painter: painter,
              child: foreground == null
                  ? const SizedBox.expand()
                  : RepaintBoundary(child: foreground),
            ),
          );
        },
      );
    },
  );
}
