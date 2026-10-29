import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 枝梢沿曲线延伸并增厚；树皮只是填充材质，不缩放整张枝条图片。
class OrganicBranch extends StatefulWidget {
  const OrganicBranch({super.key, required this.progress, required this.right});
  final double progress;
  final bool right;

  @override
  State<OrganicBranch> createState() => _OrganicBranchState();
}

class _OrganicBranchState extends State<OrganicBranch> {
  ui.Image? _bark;

  @override
  void initState() {
    super.initState();
    _loadBark();
  }

  Future<void> _loadBark() async {
    final bytes = await rootBundle.load(
      'assets/tree_scene/illustrated/bark_detail.png',
    );
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 256,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _bark = frame.image);
  }

  @override
  void dispose() {
    _bark?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: OrganicBranchPainter(widget.progress, widget.right, _bark),
  );
}

class OrganicBranchPainter extends CustomPainter {
  const OrganicBranchPainter(this.progress, this.right, this.bark);
  final double progress;
  final bool right;
  final ui.Image? bark;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    canvas.save();
    if (right) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final spine = Path()
      ..moveTo(size.width * .88, size.height * .7)
      ..cubicTo(
        size.width * .68,
        size.height * .86,
        size.width * .38,
        size.height * .8,
        size.width * .22,
        size.height * .63,
      );
    final metric = spine.computeMetrics().first;
    var silhouette = _stem(spine, progress, size.height * .052);
    final leaves = <({Offset point, double angle, double opening})>[];
    for (final birth in [.38, .64]) {
      final growth = ((progress - birth) / (1 - birth)).clamp(0.0, 1.0);
      if (growth == 0) continue;
      final start = metric.getTangentForOffset(metric.length * birth)!.position;
      final twig = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx - size.width * .035,
          start.dy - size.height * .035,
          start.dx - size.width * .07,
          start.dy - size.height * .2,
          start.dx - size.width * .13,
          start.dy - size.height * .23,
        );
      silhouette = Path.combine(
        PathOperation.union,
        silhouette,
        _stem(twig, growth, size.height * .023),
      );
      final twigMetric = twig.computeMetrics().first;
      for (var leaf = 0; leaf < 4; leaf++) {
        final distance = .55 + leaf * .13;
        if (growth < distance) continue;
        leaves.add((
          point: twigMetric
              .getTangentForOffset(twigMetric.length * distance)!
              .position,
          angle: leaf.isEven ? -.8 : .8,
          opening: ((growth - distance) / .18).clamp(0.0, 1.0),
        ));
      }
    }
    canvas.drawShadow(silhouette, const Color(0x663A2515), 3, false);
    final paint = Paint()..color = const Color(0xFF6B4B2A);
    if (bark != null) {
      paint.shader = ImageShader(
        bark!,
        TileMode.repeated,
        TileMode.repeated,
        (Matrix4.identity()..scaleByDouble(.4, .4, 1, 1)).storage,
      );
      paint.colorFilter = const ColorFilter.mode(
        Color(0xFFB59B58),
        BlendMode.modulate,
      );
    }
    canvas.drawPath(silhouette, paint);
    canvas.drawPath(
      silhouette,
      Paint()
        ..color = const Color(0x88543819)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    for (final leaf in leaves) {
      canvas.save();
      canvas.translate(leaf.point.dx, leaf.point.dy);
      canvas.rotate(leaf.angle);
      final length = size.height * .065 * leaf.opening;
      final shape = Path()
        ..quadraticBezierTo(-length * .45, -length * .5, 0, -length)
        ..quadraticBezierTo(length * .45, -length * .5, 0, 0);
      canvas.drawPath(
        shape,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF48501C), Color(0xFFA59B3F)],
          ).createShader(Rect.fromLTWH(-length / 2, -length, length, length)),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  Path _stem(Path spine, double growth, double rootRadius) {
    final metric = spine.computeMetrics().first;
    final upper = <Offset>[];
    final lower = <Offset>[];
    const samples = 48;
    for (var index = 0; index <= samples; index++) {
      final along = growth * index / samples;
      final tangent = metric.getTangentForOffset(metric.length * along)!;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final taper = math.min(1.0, (growth - along) * 18 + .06);
      final radius =
          rootRadius *
          (1 - along * .52) *
          math.sqrt(growth) *
          taper *
          (1 + .06 * math.sin(along * 37));
      upper.add(tangent.position + normal * radius);
      lower.add(tangent.position - normal * radius);
    }
    return Path()..addPolygon([...upper, ...lower.reversed], true);
  }

  @override
  bool shouldRepaint(OrganicBranchPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.right != right ||
      oldDelegate.bark != bark;
}
