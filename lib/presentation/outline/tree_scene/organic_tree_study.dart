import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'organic_branch.dart';

typedef OrganicTreeLeaf = ({Offset point, double angle, double scale});

/// 同一拓扑在连续树龄下的二维几何；当前仅用于独立美术验证。
class OrganicTreeFrame {
  OrganicTreeFrame(double age) {
    age = age.clamp(0.0, 1.0);
    final growth = .12 + age * .88;
    final trunk = Path()
      ..moveTo(490, 1410)
      ..cubicTo(430, 1180, 575, 840, 500, 410);
    final metric = trunk.computeMetrics().first;
    wood = OrganicBranchPainter.stem(
      trunk,
      growth,
      14 + age * 78,
      tipRatio: .025,
    );
    for (var index = 0; index < 9; index++) {
      final side = index.isEven ? -1 : 1;
      final reach = 80 + index * 28.0;
      final root = Path()
        ..moveTo(490, 1405)
        ..cubicTo(
          490 + side * reach * .35,
          1460,
          490 + side * reach * .7,
          1460 + index % 3 * 9,
          490 + side * reach,
          1490 + index % 3 * 9,
        );
      _join(root, growth, 18 + age * 25);
    }
    for (var index = 0; index < 7; index++) {
      final attachment = [.30, .39, .48, .59, .69, .8, .9][index];
      final branchGrowth = ((growth - attachment) / (1 - attachment)).clamp(
        0.0,
        1.0,
      );
      if (branchGrowth == 0) continue;
      final start = metric
          .getTangentForOffset(metric.length * attachment)!
          .position;
      final side = index.isEven ? -1 : 1;
      final reach = [290.0, 255.0, 365.0, 325.0, 280.0, 215.0, 135.0][index];
      final rise = [205.0, 170.0, 290.0, 245.0, 280.0, 250.0, 180.0][index];
      final branch = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + side * reach * .32,
          start.dy - 20,
          start.dx + side * reach * .8,
          start.dy - rise * .7,
          start.dx + side * reach,
          start.dy - rise,
        );
      _join(branch, branchGrowth, (12 + age * 20) * (1 - index * .07));
      _foliage(branch, branchGrowth, index * 100);
      final branchMetric = branch.computeMetrics().first;
      for (var twigIndex = 0; twigIndex < 4; twigIndex++) {
        final birth = .25 + twigIndex * .2;
        final twigGrowth = ((branchGrowth - birth) / (1 - birth)).clamp(
          0.0,
          1.0,
        );
        if (twigGrowth == 0) continue;
        final anchor = branchMetric
            .getTangentForOffset(branchMetric.length * birth)!
            .position;
        final twig = Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..cubicTo(
            anchor.dx + side * 15,
            anchor.dy - 35,
            anchor.dx + side * 40,
            anchor.dy - 100,
            anchor.dx + side * 85,
            anchor.dy - 130,
          );
        _join(twig, twigGrowth, 9 + age * 10);
        _foliage(twig, twigGrowth, index * 100 + twigIndex * 20 + 10);
      }
    }
  }

  late Path wood;
  final leaves = <OrganicTreeLeaf>[];

  void _join(Path spine, double growth, double radius) => wood = Path.combine(
    PathOperation.union,
    wood,
    OrganicBranchPainter.stem(spine, growth, radius, tipRatio: .04),
  );

  void _foliage(Path spine, double growth, int seed) {
    final metric = spine.computeMetrics().first;
    for (var index = 0; index < 60; index++) {
      final along = .4 + index / 60 * .59;
      if (growth <= along) continue;
      final opening = ((growth - along) / .16).clamp(0.0, 1.0);
      final anchor = metric
          .getTangentForOffset(metric.length * along)!
          .position;
      final phase = (seed + index) * 2.39996;
      leaves.add((
        point: anchor + Offset(math.cos(phase) * 55, math.sin(phase) * 42),
        angle: math.sin(phase) * 1.9,
        scale: (.07 + .012 * math.cos(phase * 3)) * opening,
      ));
    }
  }
}

class OrganicTreeStudyPainter extends CustomPainter {
  OrganicTreeStudyPainter(this.age, this.bark, this.leaf);
  final double age;
  final ui.Image bark;
  final ui.Image leaf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.3),
          radius: 1.2,
          colors: [Color(0xFFFFF1CE), Color(0xFFF4D9A5)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    final scale = math.min(size.width / 941, size.height / 1672);
    canvas.translate(
      (size.width - 941 * scale) / 2,
      (size.height - 1672 * scale) / 2,
    );
    canvas.scale(scale);
    final frame = OrganicTreeFrame(age);
    canvas.drawPath(
      frame.wood,
      Paint()
        ..shader = ImageShader(
          bark,
          TileMode.repeated,
          TileMode.repeated,
          (Matrix4.identity()..scaleByDouble(.7, .7, 1, 1)).storage,
        ),
    );
    canvas.drawPath(
      frame.wood,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x88E5B85D), Color(0x004E351C), Color(0x99432E17)],
        ).createShader(frame.wood.getBounds()),
    );
    canvas.drawAtlas(
      leaf,
      frame.leaves
          .map(
            (item) => ui.RSTransform.fromComponents(
              rotation: item.angle,
              scale: item.scale,
              anchorX: leaf.width / 2,
              anchorY: leaf.height * .82,
              translateX: item.point.dx,
              translateY: item.point.dy,
            ),
          )
          .toList(),
      List.filled(
        frame.leaves.length,
        Rect.fromLTWH(0, 0, leaf.width.toDouble(), leaf.height.toDouble()),
      ),
      null,
      null,
      null,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(
          Color(0xFFE8D88E),
          BlendMode.modulate,
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OrganicTreeStudyPainter oldDelegate) =>
      oldDelegate.age != age ||
      oldDelegate.bark != bark ||
      oldDelegate.leaf != leaf;
}
