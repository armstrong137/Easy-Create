import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'organic_branch.dart';
import 'organic_bark.dart';
import 'organic_tree_projection.dart';

typedef OrganicTreeLeaf = ({Offset point, double angle, double scale});
typedef _OrganicLeafBud = ({double along, double delay, OrganicTreeLeaf leaf});
typedef OrganicTreeLimb = ({
  Path spine,
  double growth,
  double radius,
  double tipRatio,
  List<OrganicStemSection> sections,
});

/// 连续生长的二维几何；实验大纲运行时与独立美术验收共用。
class OrganicTreeFrame {
  static final _trunk = Path()
    ..moveTo(490, 1410)
    ..cubicTo(430, 1180, 575, 840, 500, 410);
  static final _trunkMetric = _trunk.computeMetrics().first;
  static final _extensionStart = Path()
    ..moveTo(500, 410)
    ..cubicTo(495.3, 383.3, 487, 356.7, 487, 330);
  static final _extensionMetric = _extensionStart.computeMetrics().first;
  // 根颈沿真实主干弧长取点，幼干变细时也不会露出偏置的平切截面。
  static final _rootStart = trunkPoint(.08);
  // 按章节追加固定中心线；只缓存枝干，不缓存动态生长截面或阶段画面。
  static final _curves = <String, Path>{};
  static final _metrics = <Path, ui.PathMetric>{_trunk: _trunkMetric};
  static final _leafBuds = <Path, List<_OrganicLeafBud>>{};
  static Path _curve(String key, Path Function() create) =>
      _curves.putIfAbsent(key, create);
  static ui.PathMetric _measure(Path path) =>
      _metrics.putIfAbsent(path, () => path.computeMetrics().first);

  // 以最初主干弧长为单位，可超过 1；已有章锚点不随章节总量重排。
  static double chapterFraction(int index, int count) => .14 + .08 * index;
  static double get trunkLength => _trunkMetric.length;
  static final chapterSpacing = List.generate(
    12,
    (index) =>
        (trunkPoint(chapterFraction(index + 1, 0)).dy -
                trunkPoint(chapterFraction(index, 0)).dy)
            .abs(),
  ).reduce((a, b) => math.min(a, b));

  static double upperExtentFor(double chapters) =>
      math.max(0.0, chapters - 10) * .08 * _trunkMetric.length;

  static Offset trunkPoint(double fraction) {
    if (fraction <= 1) {
      return _trunkMetric
          .getTangentForOffset(_trunkMetric.length * fraction)!
          .position;
    }
    final distance = (fraction - 1) * _trunkMetric.length;
    if (distance <= _extensionMetric.length) {
      return _extensionMetric.getTangentForOffset(distance)!.position;
    }
    return Offset(487, 330 - distance + _extensionMetric.length);
  }

  OrganicTreeFrame(double age, {double? chapterCount, OrganicTreeFrame? previous})
    : chapterCount = chapterCount ?? age.clamp(0.0, 1.0) * 10 {
    // 只借用上一帧仍完全相同的截面，不保留历史帧链或近似生长参数。
    final previousLimbs = {
      if (previous != null)
        for (final limb in previous.limbs) limb.spine: limb,
    };
    void join(Path spine, double growth, double radius) =>
        _join(spine, growth, radius, previousLimbs[spine]);
    age = age.clamp(0.0, 1.0);
    this.age = age;
    // 空书从已扎根的完整幼树起步，随后真实延伸到相同的成年中心线末端。
    final ageGrowth = .32 + age * .68;
    final growth = math.max(ageGrowth, math.min(1.0, this.chapterCount / 10));
    _originalGrowth = growth;
    final extra = upperExtentFor(this.chapterCount);
    _stemExtent = 1 + extra / _trunkMetric.length;
    _growthExtent = growth + extra / _trunkMetric.length;
    final trunk = _trunk;
    final metric = _trunkMetric;
    var trunkSections = OrganicBranchPainter.sampleStem(
      trunk,
      growth,
      14 + age * 78,
      tipRatio: .025,
      pathMetric: metric,
    );
    if (extra > 0) {
      trunkSections = [
        for (final section in trunkSections)
          (
            center: section.center,
            normal: section.normal,
            radius: trunkRadiusAt(section.distance / _trunkMetric.length),
            distance: section.distance,
          ),
      ];
    }
    wood = OrganicBranchPainter.sectionPath(trunkSections);
    limbs.add((
      spine: trunk,
      growth: growth,
      radius: 14 + age * 78,
      tipRatio: .025,
      sections: trunkSections,
    ));
    trunkWood = Path.from(wood);
    if (extra > 0) {
      // 原主干保持原位，沿顶端切线继续长出几何，不拉长既有贴图或枝条。
      final extension = _extensionMetric.extractPath(
        0,
        math.min(extra, _extensionMetric.length),
      );
      if (extra > _extensionMetric.length) {
        final end = trunkPoint(_stemExtent);
        extension.lineTo(end.dx, end.dy);
      }
      final extensionMetrics = extension.computeMetrics().iterator;
      if (extensionMetrics.moveNext()) {
        final metric = extensionMetrics.current;
        // 固定弧长分段保持截面精度；纹理沿全主干累计距离连续铺设。
        for (
          var segment = 0;
          segment < (extra / _trunkMetric.length).ceil();
          segment++
        ) {
          final startDistance = segment * _trunkMetric.length;
          final spine = metric.extractPath(
            startDistance,
            math.min(extra, startDistance + _trunkMetric.length),
          );
          final segmentMetrics = spine.computeMetrics().iterator;
          if (!segmentMetrics.moveNext()) continue;
          final spineMetric = segmentMetrics.current;
          final sections = [
            for (final section in OrganicBranchPainter.sampleStem(
              spine,
              1,
              1,
              pathMetric: spineMetric,
            ))
              (
                center: section.center,
                normal: section.normal,
                radius: trunkRadiusAt(
                  1 + (startDistance + section.distance) / _trunkMetric.length,
                ),
                distance:
                    _trunkMetric.length + startDistance + section.distance,
              ),
          ];
          final shape = OrganicBranchPainter.sectionPath(sections);
          wood.addPath(shape, Offset.zero);
          trunkWood.addPath(shape, Offset.zero);
          limbs.add((
            spine: spine,
            growth: 1,
            radius: trunkRadiusAt(1 + startDistance / _trunkMetric.length),
            tipRatio: .025,
            sections: sections,
          ));
        }
      }
    }
    _foliage(trunk, growth, 9999, sparse: true);
    // 延伸主干的叶节也绑定固定弧长，不在动态截取的路径上积累芽叶缓存。
    final leaderSpan = _trunkMetric.length * .16;
    for (var index = 0; index < (extra / leaderSpan).ceil(); index++) {
      final startDistance = index * leaderSpan;
      final leader = _curve('leader:$index', () {
        if (index == 0) {
          final path = _extensionMetric.extractPath(
            0,
            math.min(leaderSpan, _extensionMetric.length),
          );
          if (leaderSpan > _extensionMetric.length) {
            final end = trunkPoint(1 + leaderSpan / _trunkMetric.length);
            path.lineTo(end.dx, end.dy);
          }
          return path;
        }
        final start = trunkPoint(1 + startDistance / _trunkMetric.length);
        final end = trunkPoint(1 + (startDistance + leaderSpan) / _trunkMetric.length);
        return Path()..moveTo(start.dx, start.dy)..lineTo(end.dx, end.dy);
      });
      _foliage(
        leader,
        ((extra - startDistance) / leaderSpan).clamp(0.0, 1.0),
        20000 + index * 100,
        sparse: true,
      );
    }
    // 幼龄细根先探索土壤，粗度仍跟随树龄，避免短粗根挤成星形尖片。
    final rootGrowth = .35 + age * .65;
    final rootRadius = (12 + age * 90) * math.sqrt(growth / rootGrowth);
    for (var index = 0; index < 12; index++) {
      // 后侧细根先绘制，前侧粗根随后覆盖；长短交错而非沿同一扇缘排齐。
      final radius = rootRadius * const [
        .30, .28, .45, .34, .56, .48, .30, .36, .46, .38, .58, .42,
      ][index];
      // 根梢靠近同一地面，保留前后层次，避免左右平伸而前根过长。
      final end = const [
        Offset(205, 1460),
        Offset(760, 1455),
        Offset(310, 1488),
        Offset(675, 1490),
        Offset(150, 1508),
        Offset(825, 1500),
        Offset(395, 1510),
        Offset(565, 1517),
        Offset(285, 1538),
        Offset(700, 1520),
        Offset(445, 1540),
        Offset(530, 1545),
      ][index];
      final root = _curve(
        'root:$index',
        () => Path()
          ..moveTo(_rootStart.dx, _rootStart.dy)
          ..cubicTo(
            _rootStart.dx + (end.dx - _rootStart.dx) * .08,
            1420 + (index % 2) * 15,
            end.dx - (end.dx - _rootStart.dx) * .30 + (index.isEven ? 20 : -16),
            end.dy - 4 - (index % 3) * 8,
            end.dx,
            end.dy,
          ),
      );
      join(root, rootGrowth, radius);
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
            tangent.vector * 35 + normal * (forkIndex.isEven ? 14 : -12);
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
        join(fork, forkGrowth, forkRadius);
      }
    }
    rootBounds = wood.getBounds();
    // 早生细枝沿幼干交错形成树冠，避免叶簇集中在根颈而顶部裸露。
    for (var index = 0; index < 4; index++) {
      final attachment = const [.14, .23, .30, .39][index];
      final sproutGrowth = ((growth - attachment) / .08).clamp(0.0, 1.0);
      if (sproutGrowth == 0) continue;
      final start = trunkPoint(attachment);
      final side = index.isEven ? -1 : 1;
      final sprout = _curve(
        'sprout:$index',
        () => Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + side * 25,
            start.dy - 5,
            start.dx + side * 70,
            start.dy - 55,
            start.dx + side * 85,
            start.dy - 80,
          ),
      );
      final radius = math.min(2 + age * 2, trunkRadiusAt(attachment) * .65);
      join(sprout, sproutGrowth, radius);
      _foliage(sprout, sproutGrowth, 30000 + index * 100);
    }
    final upperBranches = (extra / (_trunkMetric.length * .16)).ceil();
    for (var index = 0; index < 7 + upperBranches; index++) {
      final attachment = index < 7
          ? [.22, .34, .43, .53, .65, .76, .88][index]
          : 1 + (index - 7) * .16;
      final branchGrowth =
          ((index < 7 ? growth : _growthExtent) - attachment) /
          (index < 7 ? 1 - attachment : .16);
      final growingBranch = branchGrowth.clamp(0.0, 1.0);
      if (growingBranch == 0) continue;
      final start = trunkPoint(attachment);
      final side = index.isEven ? -1 : 1;
      final end = index < 7
          ? const [
              Offset(170, 1030),
              Offset(760, 930),
              Offset(170, 790),
              Offset(760, 650),
              Offset(220, 510),
              Offset(680, 420),
              Offset(450, 300),
            ][index]
          : Offset(
              start.dx + side * (160 + 40 * math.sin(index * 1.73)),
              start.dy - 180 - 40 * math.sin(index * 2.11),
            );
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
      final parentRadius = trunkRadiusAt(attachment);
      final branchRadius = math.min(
        (12 + age * 40) * (index < 7 ? 1 - index * .07 : .65),
        parentRadius * .75,
      );
      join(branch, growingBranch, branchRadius);
      _foliage(branch, growingBranch, index * 1000 + 900, sparse: true);
      final branchMetric = _measure(branch);
      for (var twigIndex = 0; twigIndex < 4; twigIndex++) {
        final birth = .12 + twigIndex * .22;
        // 早发细枝先伸展展叶，母枝继续生长；后发细枝仍在母枝末态前长成。
        final twigGrowth = ((growingBranch - birth) / math.min(.4, 1 - birth))
            .clamp(0.0, 1.0);
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
                growingBranch,
                branchRadius,
                .04,
              ) *
              .75,
        );
        join(twig, twigGrowth, twigRadius);
        _foliage(
          twig,
          twigGrowth,
          index * 1000 + twigIndex * 100 + 95,
          sparse: true,
        );
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
          join(spray, sprayGrowth, sprayRadius);
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
  late final Path trunkWood;
  final double chapterCount;
  late final double age;
  late final double _originalGrowth;
  late final double _growthExtent;
  late final double _stemExtent;
  late final Rect rootBounds;
  final leaves = <OrganicTreeLeaf>[];
  final limbs = <OrganicTreeLimb>[];

  /// 章枝沿真实主干弧长连接，已有叶节和枝干不会因浏览窗口变化搬动。
  /// 未长到的连接位置不投影，避免把牌面挂在尚未出现的树干上。
  Offset? chapterAnchor(int chapterIndex, int chapterCount) {
    return anchorAt(chapterFraction(chapterIndex, chapterCount));
  }

  double trunkRadiusAt(double fraction) {
    if (_stemExtent == 1) {
      return OrganicBranchPainter.radiusAt(
        fraction,
        _originalGrowth,
        14 + age * 78,
        .025,
      );
    }
    return (14 + age * 78) *
        (1 - fraction / _stemExtent * .975) *
        math.sqrt(_originalGrowth) *
        math.min(1.0, (_growthExtent - fraction) * 18 + .06) *
        (1 + .06 * math.sin(fraction * 37));
  }

  Offset? anchorAt(double fraction) =>
      fraction > _growthExtent ? null : trunkPoint(fraction);

  void _join(Path spine, double growth, double radius, OrganicTreeLimb? previous) {
    final sections = previous != null &&
            previous.growth == growth &&
            previous.radius == radius &&
            previous.tipRatio == .04
        ? previous.sections
        : OrganicBranchPainter.sampleStem(
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
    // 每条固定枝线只有一套叶节；仅预计算位置与完全展开形态，不缓存树龄画面。
    final buds = _leafBuds.putIfAbsent(spine, () {
      final result = <_OrganicLeafBud>[];
      final metric = _measure(spine);
      // 主枝较早展叶且缩短叶节空档，末级枝仍保留原有疏密。
      final nodes = sparse ? 5 : (metric.length / 24).round().clamp(3, 7);
      for (var index = 0; index < nodes; index++) {
        final phase = seed * .37 + index * .83;
        final along =
            (sparse ? .08 : .22) +
            index / (nodes - 1) * (sparse ? .80 : .70) +
            .025 * math.sin(phase);
        final tangent = metric.getTangentForOffset(metric.length * along)!;
        // 末级枝上疏密错落地对生阔叶，保留主枝负空间，避免五叶轮生重复成蕨片。
        for (var blade = 0; blade < 2; blade++) {
          final angle =
              math.atan2(tangent.vector.dy, tangent.vector.dx) +
              (blade == 0 ? -.85 : .85) +
              .25 * math.sin(phase + blade);
          result.add((
            along: along,
            delay: blade * .012,
            leaf: (
              point: tangent.position,
              angle: angle + math.pi / 2,
              scale:
                  (sparse ? .045 : .07) *
                  (1 + .25 * math.sin(phase + blade * 2)),
            ),
          ));
        }
      }
      return result;
    });
    for (final bud in buds) {
      if (growth <= bud.along) continue;
      final opening = ((growth - bud.along - bud.delay) / (sparse ? .04 : .08))
          .clamp(0.0, 1.0);
      if (opening == 0) continue;
      leaves.add((
        point: bud.leaf.point,
        angle: bud.leaf.angle,
        scale: bud.leaf.scale * opening,
      ));
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
  OrganicTreeStudyPainter(
    this.age,
    this.bark,
    this.leaf, {
    double? chapterCount,
    double? projectionExtent,
    OrganicTreeFrame? geometry,
  }) : frame = geometry ?? OrganicTreeFrame(age, chapterCount: chapterCount),
       projectionExtent =
           projectionExtent ??
           OrganicTreeFrame.upperExtentFor(chapterCount ?? 10),
       barkTint = organicBarkTintForAge(age);
  final double age;
  final ui.Image bark;
  final ui.Image leaf;
  final OrganicTreeFrame frame;
  final ColorFilter barkTint;
  final double projectionExtent;

  @override
  void paint(Canvas canvas, Size size) {
    // 页面持有羊皮纸背景，树体画布保持透明，避免全景缩放后显出矩形底色。
    canvas.save();
    final projection = OrganicTreeProjection(
      size,
      upperExtent: projectionExtent,
    );
    canvas.translate(projection.origin.dx, projection.origin.dy);
    canvas.scale(projection.scale);
    // 接地阴影跟随真实根幅展开，不随章节镜头单独缩放或使用树龄阶段图。
    final ground = frame.rootBounds;
    final shadowHeight = ground.width * .17;
    canvas.save();
    canvas.translate(ground.center.dx, ground.bottom - shadowHeight * .4);
    canvas.scale(ground.width * .56, shadowHeight / 2);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x3D4D321B), Color(0x204D321B), Color(0x004D321B)],
          stops: [0, .5, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    );
    canvas.restore();
    canvas.drawPath(
      frame.wood,
      Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = barkTint
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
    // 512母版的透明边界保留至少32像素滤波余量，减少空白覆盖，不缩小叶片。
    final leafSource = Rect.fromLTRB(
      leaf.width * 128 / 512,
      leaf.height * 48 / 512,
      leaf.width * 400 / 512,
      leaf.height * 472 / 512,
    );
    canvas.drawAtlas(
      leaf,
      frame.leaves
          .map(
            (item) => ui.RSTransform.fromComponents(
              rotation: item.angle,
              scale: item.scale,
              anchorX: leaf.width / 2 - leafSource.left,
              anchorY: leaf.height * .82 - leafSource.top,
              translateX: item.point.dx,
              translateY: item.point.dy,
            ),
          )
          .toList(),
      List.filled(
        frame.leaves.length,
        leafSource,
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
          // 光照至少为0.18；正数先取整再截上限与原夹取后取整等价。
          final red = (255 * light).round();
          final green = (245 * light).round();
          final blue = (220 * light).round();
          colors[vertex] =
              alpha |
              ((red > 255 ? 255 : red) << 16) |
              ((green > 255 ? 255 : green) << 8) |
              (blue > 255 ? 255 : blue);
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
        ..colorFilter = barkTint,
    );
    vertices.dispose();
  }

  @override
  bool shouldRepaint(OrganicTreeStudyPainter oldDelegate) =>
      oldDelegate.age != age ||
      oldDelegate.frame.chapterCount != frame.chapterCount ||
      oldDelegate.projectionExtent != projectionExtent ||
      oldDelegate.bark != bark ||
      oldDelegate.leaf != leaf;
}
