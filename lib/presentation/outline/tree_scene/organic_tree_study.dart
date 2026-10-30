import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'organic_branch.dart';
import 'organic_bark.dart';
import 'organic_tree_projection.dart';

typedef OrganicTreeLeaf = ({Offset point, double angle, double scale});
typedef OrganicTreeLimb = ({
  Path spine,
  double growth,
  double radius,
  double tipRatio,
  List<OrganicStemSection> sections,
});

/// 同一拓扑在连续树龄下的二维几何；当前仅用于独立美术验证。
class OrganicTreeFrame {
  static final _trunk = Path()
    ..moveTo(490, 1410)
    ..cubicTo(430, 1180, 575, 840, 500, 410);
  static final _trunkMetric = _trunk.computeMetrics().first;

  static double chapterFraction(int index, int count) =>
      .14 + .72 * index / math.max(9, count - 1);

  static Offset trunkPoint(double fraction) => _trunkMetric
      .getTangentForOffset(_trunkMetric.length * fraction)!
      .position;

  OrganicTreeFrame(double age) {
    age = age.clamp(0.0, 1.0);
    final growth = .12 + age * .88;
    final trunk = _trunk;
    final metric = trunk.computeMetrics().first;
    final trunkSections = OrganicBranchPainter.sampleStem(
      trunk,
      growth,
      14 + age * 78,
      tipRatio: .025,
    );
    wood = OrganicBranchPainter.sectionPath(trunkSections);
    limbs.add((
      spine: trunk,
      growth: growth,
      radius: 14 + age * 78,
      tipRatio: .025,
      sections: trunkSections,
    ));
    _foliage(trunk, growth, 9999);
    // 幼龄细根先探索土壤，粗度仍跟随树龄，避免短粗根挤成星形尖片。
    final rootGrowth = .35 + age * .65;
    final rootRadius = (12 + age * 90) * math.sqrt(growth / rootGrowth);
    for (var index = 0; index < 6; index++) {
      final end = const [
        Offset(115, 1450),
        Offset(255, 1510),
        Offset(450, 1570),
        Offset(625, 1530),
        Offset(790, 1480),
        Offset(850, 1430),
      ][index];
      final root = Path()
        ..moveTo(490, 1380)
        ..cubicTo(
          490 + (end.dx - 490) * .12,
          1470 + (index % 2) * 15,
          end.dx - (end.dx - 490) * .38,
          end.dy - 20,
          end.dx,
          end.dy,
        );
      _join(root, rootGrowth, rootRadius);
      final rootMetric = root.computeMetrics().first;
      for (var forkIndex = 0; forkIndex < 2; forkIndex++) {
        final birth = .3 + forkIndex * .3;
        final forkGrowth = ((rootGrowth - birth) / (1 - birth)).clamp(0.0, 1.0);
        if (forkGrowth == 0) continue;
        final tangent = rootMetric.getTangentForOffset(
          rootMetric.length * birth,
        )!;
        final start = tangent.position;
        final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
        final direction =
            tangent.vector * 65 + normal * (forkIndex.isEven ? 35 : -28);
        final fork = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + tangent.vector.dx * 20,
            start.dy + tangent.vector.dy * 20,
            start.dx + direction.dx * .7,
            start.dy + direction.dy * .7,
            start.dx + direction.dx,
            start.dy + direction.dy,
          );
        final forkRadius = math.min(
          (10 + age * 12) * (1 - forkIndex * .3),
          OrganicBranchPainter.radiusAt(birth, rootGrowth, rootRadius, .04) *
              .7,
        );
        _join(fork, forkGrowth, forkRadius);
      }
    }
    for (var index = 0; index < 7; index++) {
      final attachment = [.22, .34, .43, .53, .65, .76, .88][index];
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
        Offset(170, 1030),
        Offset(760, 930),
        Offset(170, 790),
        Offset(760, 650),
        Offset(220, 510),
        Offset(680, 420),
        Offset(450, 300),
      ][index];
      final reach = (end.dx - start.dx).abs();
      final branch = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + side * reach * .20,
          start.dy + 20,
          end.dx - side * reach * .35,
          end.dy - 45,
          end.dx,
          end.dy,
        );
      final parentRadius = OrganicBranchPainter.radiusAt(
        attachment,
        growth,
        14 + age * 78,
        .025,
      );
      final branchRadius = math.min(
        (12 + age * 20) * (1 - index * .07),
        parentRadius * .75,
      );
      _join(branch, branchGrowth, branchRadius);
      _foliage(branch, branchGrowth, index * 1000 + 900);
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
        final twigRadius = math.min(
          4 + age * 6,
          OrganicBranchPainter.radiusAt(
                birth,
                branchGrowth,
                branchRadius,
                .04,
              ) *
              .75,
        );
        _join(twig, twigGrowth, twigRadius);
        final twigMetric = twig.computeMetrics().first;
        for (var sprayIndex = 0; sprayIndex < 5; sprayIndex++) {
          final birth = .2 + sprayIndex * .16;
          final sprayGrowth = ((twigGrowth - birth) / (1 - birth)).clamp(
            0.0,
            1.0,
          );
          if (sprayGrowth == 0) continue;
          final tangent = twigMetric.getTangentForOffset(
            twigMetric.length * birth,
          )!;
          final start = tangent.position;
          final angle =
              math.atan2(tangent.vector.dy, tangent.vector.dx) +
              const [-1.25, .75, -.7, 1.2, 0.0][sprayIndex];
          final end =
              start +
              Offset(math.cos(angle), math.sin(angle)) * (60 + sprayIndex * 8);
          final spray = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(
              start.dx + tangent.vector.dx * 25,
              start.dy + tangent.vector.dy * 25,
              end.dx,
              end.dy,
            );
          final sprayRadius = math.min(
            2 + age * 2,
            OrganicBranchPainter.radiusAt(birth, twigGrowth, twigRadius, .04) *
                .75,
          );
          _join(spray, sprayGrowth, sprayRadius);
          _foliage(
            spray,
            sprayGrowth,
            index * 1000 + twigIndex * 100 + sprayIndex * 20,
          );
        }
      }
    }
  }

  late Path wood;
  final leaves = <OrganicTreeLeaf>[];
  final limbs = <OrganicTreeLimb>[];

  /// 章枝沿真实主干弧长连接，已有叶节和枝干不会因浏览窗口变化搬动。
  /// 未长到的连接位置不投影，避免把牌面挂在尚未出现的树干上。
  Offset? chapterAnchor(int chapterIndex, int chapterCount) {
    return anchorAt(chapterFraction(chapterIndex, chapterCount));
  }

  double trunkRadiusAt(double fraction) => OrganicBranchPainter.radiusAt(
    fraction,
    limbs.first.growth,
    limbs.first.radius,
    limbs.first.tipRatio,
  );

  Offset? anchorAt(double fraction) =>
      fraction > limbs.first.growth ? null : trunkPoint(fraction);

  void _join(Path spine, double growth, double radius) {
    final sections = OrganicBranchPainter.sampleStem(
      spine,
      growth,
      radius,
      tipRatio: .04,
    );
    limbs.add((
      spine: spine,
      growth: growth,
      radius: radius,
      tipRatio: .04,
      sections: sections,
    ));
    // 同向闭合轮廓使用非零填充合并，避免密集枝叉反复布尔运算的精度问题。
    wood.addPath(OrganicBranchPainter.sectionPath(sections), Offset.zero);
  }

  void _foliage(Path spine, double growth, int seed) {
    final metric = spine.computeMetrics().first;
    final nodes = (metric.length / 18).round().clamp(3, 24);
    final bladeScale = metric.length < 100 ? .055 : .025;
    for (var index = 0; index < nodes; index++) {
      final along = .18 + index / (nodes - 1) * .78;
      if (growth <= along) continue;
      final anchor = metric
          .getTangentForOffset(metric.length * along)!
          .position;
      final phase = seed * .37 + index * .83;
      // 叶柄固定在同一叶节，叶片逐枚展开；不再把散点叶片撒在枝条周围。
      for (var blade = 0; blade < 5; blade++) {
        final opening = ((growth - along - blade * .004) / .06).clamp(0.0, 1.0);
        if (opening == 0) continue;
        final angle = phase + blade * math.pi * 2 / 5;
        leaves.add((
          point: anchor,
          angle: angle + math.pi / 2,
          scale: bladeScale * (1 + .2 * math.sin(phase + blade)) * opening,
        ));
      }
    }
  }
}

class OrganicTreeStudyPainter extends CustomPainter {
  OrganicTreeStudyPainter(this.age, this.bark, this.leaf)
    : frame = OrganicTreeFrame(age);
  final double age;
  final ui.Image bark;
  final ui.Image leaf;
  final OrganicTreeFrame frame;

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
    final projection = OrganicTreeProjection(size);
    canvas.translate(projection.origin.dx, projection.origin.dy);
    canvas.scale(projection.scale);
    canvas.drawPath(
      frame.wood,
      Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = organicBarkTint
        ..shader = ImageShader(
          bark,
          TileMode.repeated,
          TileMode.repeated,
          (Matrix4.identity()..scaleByDouble(
                .7 * 512 / bark.width,
                .7 * 512 / bark.width,
                1,
                1,
              ))
              .storage,
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
          colors: [Color(0x22E5B85D), Color(0x004E351C), Color(0x66432E17)],
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
        ..colorFilter = const ColorFilter.matrix([
          1.4,
          0,
          0,
          0,
          5,
          0,
          1.3,
          0,
          0,
          5,
          0,
          0,
          .9,
          0,
          2,
          0,
          0,
          0,
          1,
          0,
        ]),
    );
    canvas.restore();
  }

  void _surface(Canvas canvas, OrganicTreeLimb limb) {
    final points = <Offset>[];
    final uv = <Offset>[];
    final colors = <Color>[];
    final triangles = <int>[];
    // 表面与外轮廓共用截面位置，弯曲处不露出另一套树皮的尖角。
    const rings = OrganicBranchPainter.stemSamples;
    const slices = 8;
    for (var ring = 0; ring <= rings; ring++) {
      final section = limb.sections[ring];
      final normal = section.normal;
      final radius = section.radius;
      final collar = (section.distance / (limb.radius * 2)).clamp(0.0, 1.0);
      final coverage = collar * collar * (3 - 2 * collar);
      for (var slice = 0; slice <= slices; slice++) {
        final angle = -math.pi / 2 + math.pi * slice / slices;
        final cross = math.sin(angle);
        points.add(section.center + normal * radius * cross);
        // 纹理随截面周长取样，细枝不能横向塞入整张粗树皮。
        uv.add(
          Offset((angle + math.pi / 2) * radius, section.distance * .8) *
              (bark.width / 512),
        );
        final light =
            .18 +
            .82 *
                math.max(
                  0.0,
                  -.7 * normal.dx * cross -
                      .55 * normal.dy * cross +
                      .8 * math.cos(angle),
                );
        colors.add(
          Color.fromARGB(
            (255 * coverage).round(),
            (255 * light).clamp(0, 255).round(),
            (245 * light).clamp(0, 255).round(),
            (220 * light).clamp(0, 255).round(),
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
        ..filterQuality = FilterQuality.high
        ..shader = ImageShader(
          bark,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..colorFilter = organicBarkTint,
    );
    vertices.dispose();
  }

  @override
  bool shouldRepaint(OrganicTreeStudyPainter oldDelegate) =>
      oldDelegate.age != age ||
      oldDelegate.bark != bark ||
      oldDelegate.leaf != leaf;
}
