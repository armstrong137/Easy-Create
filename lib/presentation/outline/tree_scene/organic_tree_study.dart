import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'organic_branch.dart';

typedef OrganicTreeLeaf = ({Offset point, double angle, double scale});
typedef OrganicTreeLimb = ({
  Path spine,
  double growth,
  double radius,
  double tipRatio,
});

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
    limbs.add((
      spine: trunk,
      growth: growth,
      radius: 14 + age * 78,
      tipRatio: .025,
    ));
    for (var index = 0; index < 9; index++) {
      final end = const [
        Offset(90, 1450),
        Offset(210, 1510),
        Offset(330, 1550),
        Offset(430, 1570),
        Offset(560, 1540),
        Offset(690, 1500),
        Offset(820, 1480),
        Offset(870, 1420),
        Offset(310, 1460),
      ][index];
      final root = Path()
        ..moveTo(490 + (index - 4) * 6, 1405)
        ..cubicTo(
          490 + (end.dx - 490) * .25,
          1470,
          end.dx - (end.dx - 490) * .15,
          end.dy - 18,
          end.dx,
          end.dy,
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
      final end = const [
        Offset(200, 870),
        Offset(740, 820),
        Offset(190, 580),
        Offset(740, 470),
        Offset(280, 280),
        Offset(690, 220),
        Offset(450, 180),
      ][index];
      final reach = (end.dx - start.dx).abs();
      final branch = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + side * reach * .32,
          start.dy - 20,
          end.dx - side * reach * .1,
          end.dy + 80,
          end.dx,
          end.dy,
        );
      _join(branch, branchGrowth, (12 + age * 20) * (1 - index * .07));
      final branchMetric = branch.computeMetrics().first;
      for (var twigIndex = 0; twigIndex < 4; twigIndex++) {
        final birth = .25 + twigIndex * .2;
        final twigGrowth = ((branchGrowth - birth) / (1 - birth)).clamp(
          0.0,
          1.0,
        );
        if (twigGrowth == 0) continue;
        final tangent = branchMetric.getTangentForOffset(
          branchMetric.length * birth,
        )!;
        final anchor = tangent.position;
        final angle = -math.pi / 2 + side * (.25 + twigIndex * .19);
        final direction = Offset(math.cos(angle), math.sin(angle));
        final length = 70 + twigIndex * 10.0;
        final twig = Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..cubicTo(
            anchor.dx + tangent.vector.dx * 35,
            anchor.dy + tangent.vector.dy * 35,
            anchor.dx + direction.dx * length * .7,
            anchor.dy + direction.dy * length * .7,
            anchor.dx + direction.dx * length,
            anchor.dy + direction.dy * length,
          );
        _join(twig, twigGrowth, 4 + age * 6);
        _foliage(twig, twigGrowth, index * 100 + twigIndex * 20 + 10);
      }
    }
  }

  late Path wood;
  final leaves = <OrganicTreeLeaf>[];
  final limbs = <OrganicTreeLimb>[];

  void _join(Path spine, double growth, double radius) {
    limbs.add((spine: spine, growth: growth, radius: radius, tipRatio: .04));
    // 同向闭合轮廓使用非零填充合并，避免密集枝叉反复布尔运算的精度问题。
    wood.addPath(
      OrganicBranchPainter.stem(spine, growth, radius, tipRatio: .04),
      Offset.zero,
    );
  }

  void _foliage(Path spine, double growth, int seed) {
    final metric = spine.computeMetrics().first;
    for (var index = 0; index < 180; index++) {
      final along = .35 + index / 180 * .64;
      if (growth <= along) continue;
      final opening = ((growth - along) / .16).clamp(0.0, 1.0);
      final anchor = metric
          .getTangentForOffset(metric.length * along)!
          .position;
      final phase = (seed + index) * 2.39996;
      final spread = math.sqrt(((index * 73 + seed) % 181) / 181);
      leaves.add((
        point:
            anchor +
            Offset(
              math.cos(phase) * 90 * spread,
              math.sin(phase) * 65 * spread,
            ),
        angle: math.sin(phase) * 1.9,
        scale: (.045 + .012 * math.cos(phase * 3)) * opening,
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
    // 沿每条枝干的方向铺设树皮，并由圆截面法向形成体积光照。
    for (final limb in frame.limbs) {
      _surface(canvas, limb);
    }
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

  void _surface(Canvas canvas, OrganicTreeLimb limb) {
    final metric = limb.spine.computeMetrics().first;
    final points = <Offset>[];
    final uv = <Offset>[];
    final colors = <Color>[];
    final triangles = <int>[];
    const rings = 36;
    const slices = 8;
    for (var ring = 0; ring <= rings; ring++) {
      final along = limb.growth * ring / rings;
      final tangent = metric.getTangentForOffset(metric.length * along)!;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final radius = OrganicBranchPainter.radiusAt(
        along,
        limb.growth,
        limb.radius,
        limb.tipRatio,
      );
      for (var slice = 0; slice <= slices; slice++) {
        final angle = -math.pi / 2 + math.pi * slice / slices;
        final cross = math.sin(angle);
        points.add(tangent.position + normal * radius * cross);
        uv.add(
          Offset(slice / slices * bark.width, metric.length * along * 1.8),
        );
        final light =
            .3 +
            .7 *
                math.max(
                  0.0,
                  -.42 * normal.dx * cross -
                      .55 * normal.dy * cross +
                      .72 * math.cos(angle),
                );
        colors.add(
          Color.fromARGB(
            (255 * math.min(1.0, along * 12 + .15)).round(),
            (255 * light).clamp(0, 255).round(),
            (235 * light).clamp(0, 255).round(),
            (185 * light).clamp(0, 255).round(),
          ),
        );
        if (ring < rings && slice < slices) {
          final here = ring * (slices + 1) + slice;
          triangles.addAll([
            here,
            here + 1,
            here + slices + 1,
            here + 1,
            here + slices + 2,
            here + slices + 1,
          ]);
        }
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      points,
      textureCoordinates: uv,
      colors: colors,
      indices: triangles,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      Paint()
        ..shader = ImageShader(
          bark,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
    vertices.dispose();
  }

  @override
  bool shouldRepaint(OrganicTreeStudyPainter oldDelegate) =>
      oldDelegate.age != age ||
      oldDelegate.bark != bark ||
      oldDelegate.leaf != leaf;
}
