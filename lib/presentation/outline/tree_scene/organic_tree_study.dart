import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
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
  // 拓扑及中心线固定；缓存只含这棵树有限的枝干，不缓存动态生长截面。
  static final _curves = <String, Path>{};
  static final _metrics = <Path, ui.PathMetric>{_trunk: _trunkMetric};
  static Path _curve(String key, Path Function() create) =>
      _curves.putIfAbsent(key, create);
  static ui.PathMetric _measure(Path path) =>
      _metrics.putIfAbsent(path, () => path.computeMetrics().first);

  static double chapterFraction(int index, int count) =>
      .14 + .72 * index / math.max(9, count - 1);

  static Offset trunkPoint(double fraction) => _trunkMetric
      .getTangentForOffset(_trunkMetric.length * fraction)!
      .position;

  OrganicTreeFrame(double age) {
    age = age.clamp(0.0, 1.0);
    final growth = .12 + age * .88;
    final trunk = _trunk;
    final metric = _trunkMetric;
    final trunkSections = OrganicBranchPainter.sampleStem(
      trunk,
      growth,
      14 + age * 78,
      tipRatio: .025,
      pathMetric: metric,
    );
    wood = OrganicBranchPainter.sectionPath(trunkSections);
    limbs.add((
      spine: trunk,
      growth: growth,
      radius: 14 + age * 78,
      tipRatio: .025,
      sections: trunkSections,
    ));
    _foliage(trunk, growth, 9999, sparse: true);
    // 幼龄细根先探索土壤，粗度仍跟随树龄，避免短粗根挤成星形尖片。
    final rootGrowth = .35 + age * .65;
    final rootRadius = (12 + age * 90) * math.sqrt(growth / rootGrowth);
    for (var index = 0; index < 6; index++) {
      // 根颈从主干内部向下分流，各根粗度不同，避免六条等粗扁片堆成底座。
      final radius = rootRadius * const [.62, .48, .38, .46, .58, .42][index];
      final end = const [
        Offset(115, 1450),
        Offset(255, 1510),
        Offset(450, 1570),
        Offset(625, 1530),
        Offset(790, 1480),
        Offset(850, 1430),
      ][index];
      final root = _curve(
        'root:$index',
        () => Path()
          ..moveTo(490, 1330)
          ..cubicTo(
            490 + (end.dx - 490) * .08,
            1420 + (index % 2) * 15,
            end.dx - (end.dx - 490) * .38,
            end.dy - 20,
            end.dx,
            end.dy,
          ),
      );
      _join(root, rootGrowth, radius);
      final rootMetric = _measure(root);
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
        final fork = _curve(
          'fork:$index:$forkIndex',
          () => Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(
              start.dx + tangent.vector.dx * 20,
              start.dy + tangent.vector.dy * 20,
              start.dx + direction.dx * .7,
              start.dy + direction.dy * .7,
              start.dx + direction.dx,
              start.dy + direction.dy,
            ),
        );
        final forkRadius = math.min(
          (10 + age * 12) * (1 - forkIndex * .3),
          OrganicBranchPainter.radiusAt(birth, rootGrowth, radius, .04) * .7,
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
      final branch = _curve(
        'branch:$index',
        () => Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + side * reach * .20,
            start.dy - 20,
            end.dx - side * reach * .35,
            end.dy - 45,
            end.dx,
            end.dy,
          ),
      );
      final parentRadius = OrganicBranchPainter.radiusAt(
        attachment,
        growth,
        14 + age * 78,
        .025,
      );
      final branchRadius = math.min(
        (12 + age * 40) * (1 - index * .07),
        parentRadius * .75,
      );
      _join(branch, branchGrowth, branchRadius);
      _foliage(branch, branchGrowth, index * 1000 + 900, sparse: true);
      final branchMetric = _measure(branch);
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
        // 分枝沿母枝交错展开；固定相位只决定形态，不随树龄或浏览改变。
        final phase = index * 2.17 + twigIndex * 1.43;
        final angle =
            math.atan2(tangent.vector.dy, tangent.vector.dx) +
            (twigIndex.isEven ? -.72 : .63) +
            .28 * math.sin(phase);
        final direction = Offset(math.cos(angle), math.sin(angle));
        final length = 95 + 35 * math.sin(phase + .8);
        final twig = _curve(
          'twig:$index:$twigIndex',
          () => Path()
            ..moveTo(anchor.dx, anchor.dy)
            ..cubicTo(
              anchor.dx + tangent.vector.dx * 35,
              anchor.dy + tangent.vector.dy * 35,
              anchor.dx + direction.dx * length * .7,
              anchor.dy + direction.dy * length * .7,
              anchor.dx + direction.dx * length,
              anchor.dy + direction.dy * length,
            ),
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
        final twigMetric = _measure(twig);
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
              const [-1.25, .75, -.7, 1.2, 0.0][sprayIndex] +
              .3 * math.sin(phase + sprayIndex * 1.71);
          final end =
              start +
              Offset(math.cos(angle), math.sin(angle)) *
                  (65 + 25 * math.sin(phase * .7 + sprayIndex * 2.13));
          final spray = _curve(
            'spray:$index:$twigIndex:$sprayIndex',
            () => Path()
              ..moveTo(start.dx, start.dy)
              ..quadraticBezierTo(
                start.dx + tangent.vector.dx * 25,
                start.dy + tangent.vector.dy * 25,
                end.dx,
                end.dy,
              ),
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
      pathMetric: _measure(spine),
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

  void _foliage(Path spine, double growth, int seed, {bool sparse = false}) {
    final metric = _measure(spine);
    final nodes = sparse ? 3 : (metric.length / 24).round().clamp(3, 7);
    for (var index = 0; index < nodes; index++) {
      final phase = seed * .37 + index * .83;
      final along =
          (sparse ? .14 : .22) +
          index / (nodes - 1) * .70 +
          .025 * math.sin(phase);
      if (growth <= along) continue;
      final tangent = metric.getTangentForOffset(metric.length * along)!;
      // 末级枝上疏密错落地对生阔叶，保留主枝负空间，避免五叶轮生重复成蕨片。
      for (var blade = 0; blade < 2; blade++) {
        final opening = ((growth - along - blade * .012) / .08).clamp(0.0, 1.0);
        if (opening == 0) continue;
        final angle =
            math.atan2(tangent.vector.dy, tangent.vector.dx) +
            (blade == 0 ? -.85 : .85) +
            .25 * math.sin(phase + blade);
        leaves.add((
          point: tangent.position,
          angle: angle + math.pi / 2,
          scale:
              (sparse ? .045 : .07) *
              (1 + .25 * math.sin(phase + blade * 2)) *
              opening,
        ));
      }
    }
  }
}

class OrganicTreeStudyPainter extends CustomPainter {
  static const _surfaceBatchSize = 128;
  static const _surfaceVertexCapacity =
      _surfaceBatchSize * (OrganicBranchPainter.stemSamples + 1) * 9;
  // Vertices.raw构造时复制输入；同步绘制批次可复用工作区，不保留各树龄缓冲。
  static final _surfacePoints = Float32List(_surfaceVertexCapacity * 2);
  static final _surfaceUV = Float32List(_surfaceVertexCapacity * 2);
  static final _surfaceColors = Int32List(_surfaceVertexCapacity);
  static final _surfaceIndices = (() {
    const rings = OrganicBranchPainter.stemSamples;
    const slices = 8;
    final indices = Uint16List(
      _surfaceBatchSize * rings * (2 * (slices + 1) + 2) - 2,
    );
    var face = 0;
    for (var limb = 0; limb < _surfaceBatchSize; limb++) {
      final base = limb * (rings + 1) * (slices + 1);
      for (var ring = 0; ring < rings; ring++) {
        // 重复端点形成零面积连接，不在相邻环或不同枝干之间生成可见三角形。
        if (face > 0) {
          indices[face] = indices[face - 1];
          face++;
          indices[face++] = base + ring * (slices + 1);
        }
        for (var slice = 0; slice <= slices; slice++) {
          final here = base + ring * (slices + 1) + slice;
          indices[face++] = here;
          indices[face++] = here + slices + 1;
        }
      }
    }
    return indices;
  })();
  // 截面方向固定，不在每帧的每个顶点上重复求三角函数。
  static final _surfaceProfile = List.generate(9, (slice) {
    final angle = -math.pi / 2 + math.pi * slice / 8;
    return (
      cross: math.sin(angle),
      facingLight: .8 * math.cos(angle),
      arc: angle + math.pi / 2,
    );
  });
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
    // 每批最多 128×49×9=56448 个顶点，低于 16 位索引上限，保持原枝干顺序。
    for (
      var start = 0;
      start < frame.limbs.length;
      start += _surfaceBatchSize
    ) {
      _surface(
        canvas,
        frame.limbs.sublist(
          start,
          math.min(start + _surfaceBatchSize, frame.limbs.length),
        ),
      );
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

  void _surface(Canvas canvas, List<OrganicTreeLimb> limbs) {
    // 表面与外轮廓共用截面位置，弯曲处不露出另一套树皮的尖角。
    const rings = OrganicBranchPainter.stemSamples;
    const slices = 8;
    final vertexCount = limbs.length * (rings + 1) * (slices + 1);
    final points = Float32List.sublistView(_surfacePoints, 0, vertexCount * 2);
    final uv = Float32List.sublistView(_surfaceUV, 0, vertexCount * 2);
    final colors = Int32List.sublistView(_surfaceColors, 0, vertexCount);
    final textureResolution = bark.width / 512;
    // 只有一个完整批次的索引表；尾批使用零拷贝视图，不随树龄积累缓存。
    final triangles = Uint16List.sublistView(
      _surfaceIndices,
      0,
      limbs.length * rings * (2 * (slices + 1) + 2) - 2,
    );
    var vertex = 0;
    for (final limb in limbs) {
      final collarLength = limb.radius * 2;
      for (var ring = 0; ring <= rings; ring++) {
        final section = limb.sections[ring];
        final normal = section.normal;
        final radius = section.radius;
        final lightX = -.7 * normal.dx;
        final lightY = .55 * normal.dy;
        final collar = (section.distance / collarLength).clamp(0.0, 1.0);
        final coverage = collar * collar * (3 - 2 * collar);
        final alpha = (255 * coverage).round() << 24;
        final textureY = section.distance * .8 * textureResolution;
        for (var slice = 0; slice <= slices; slice++) {
          final profile = _surfaceProfile[slice];
          final cross = profile.cross;
          points[vertex * 2] = section.center.dx + normal.dx * (radius * cross);
          points[vertex * 2 + 1] =
              section.center.dy + normal.dy * (radius * cross);
          // 纹理随截面周长取样，细枝不能横向塞入整张粗树皮。
          uv[vertex * 2] = profile.arc * radius * textureResolution;
          uv[vertex * 2 + 1] = textureY;
          final light =
              .18 +
              .82 *
                  math.max(
                    0.0,
                    lightX * cross - lightY * cross + profile.facingLight,
                  );
          colors[vertex] =
              alpha |
              ((255 * light).clamp(0, 255).round() << 16) |
              ((245 * light).clamp(0, 255).round() << 8) |
              (220 * light).clamp(0, 255).round();
          vertex++;
        }
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
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
