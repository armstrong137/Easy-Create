import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tree_model.dart';

/// 黑白铅笔手绘树 painter
///
/// 手绘感：每条线拆成小段并加固定种子的微抖动，叠两遍半透明描线
/// 模拟铅笔笔触；岁月痕迹随 [TreeGeometry.age] 增加——
/// 树干边线加重、内部排线阴影加密、出现结疤。
class PencilTreePainter extends CustomPainter {
  PencilTreePainter({required this.tree});

  final TreeGeometry tree;

  @override
  void paint(Canvas canvas, Size size) {
    // 纯白背景（定稿）
    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.white);

    if (tree.branches.isEmpty && tree.age <= 0) {
      // 空状态：无干无叶（定稿），纯白画布即全部
      return;
    }

    final rng = math.Random(7); // 固定种子：笔触形态稳定不闪烁

    _drawTrunk(canvas, rng);
    // 已放置标签的占位矩形，用于碰撞规避
    final placed = <Rect>[];
    for (final branch in tree.branches) {
      _drawPencilLine(canvas, branch.start, branch.end,
          width: 1.6 + 1.2 * tree.age, rng: rng);
      for (final twig in branch.twigs) {
        _drawPencilLine(canvas, twig.start, twig.end, width: 1.1, rng: rng);
      }
      // 章标题先画（优先占位），节标签随后自动避让
      _drawLabel(canvas, placed, branch.title, branch.end, branch.leftSide,
          bold: true);
      for (final twig in branch.twigs) {
        _drawLabel(canvas, placed, twig.title, twig.end, branch.leftSide);
      }
    }
  }

  /// 树干：两条边缘线围出下宽上窄的锥形 + 树龄排线阴影 + 结疤
  void _drawTrunk(Canvas canvas, math.Random rng) {
    final base = tree.trunkBase;
    final top = tree.trunkTop;
    final halfW = tree.trunkWidth / 2;

    // 左右边缘线（带抖动的锥形）
    _drawPencilLine(
        canvas, Offset(base.dx - halfW, base.dy), Offset(top.dx - 0.8, top.dy),
        width: 1.4 + 0.8 * tree.age, rng: rng);
    _drawPencilLine(
        canvas, Offset(base.dx + halfW, base.dy), Offset(top.dx + 0.8, top.dy),
        width: 1.4 + 0.8 * tree.age, rng: rng);

    // 岁月排线：树龄越大内部斜排线越密（0~14 条）
    final hatchCount = (tree.age * 14).round();
    final trunkHeight = base.dy - top.dy;
    for (var i = 0; i < hatchCount; i++) {
      final t = (i + 0.5) / hatchCount;
      final y = base.dy - trunkHeight * t;
      final w = halfW * (1 - t * 0.7); // 越往上树干越窄
      _drawPencilLine(
        canvas,
        Offset(base.dx - w * 0.8, y + 3),
        Offset(base.dx + w * 0.8, y - 3),
        width: 0.7,
        alpha: 0.35,
        rng: rng,
      );
    }

    // 结疤：老树（age>0.45）在树干上长出小椭圆节疤
    final knotCount = tree.age > 0.45 ? ((tree.age - 0.45) * 5).ceil() : 0;
    for (var i = 0; i < knotCount; i++) {
      final t = 0.3 + 0.4 * rng.nextDouble();
      final y = base.dy - trunkHeight * t;
      final cx = base.dx + (rng.nextBool() ? 1 : -1) * halfW * 0.35;
      final knotPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.black.withValues(alpha: 0.6);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, y), width: halfW * 0.9, height: halfW * 1.5),
          knotPaint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, y), width: halfW * 0.45, height: halfW * 0.8),
          knotPaint);
    }
  }

  /// 铅笔线：拆段 + 微抖动 + 双层半透明叠描
  void _drawPencilLine(
    Canvas canvas,
    Offset from,
    Offset to, {
    required double width,
    required math.Random rng,
    double alpha = 0.85,
  }) {
    final distance = (to - from).distance;
    final segments = math.max(4, distance ~/ 14);

    for (var pass = 0; pass < 2; pass++) {
      final path = Path()..moveTo(from.dx, from.dy);
      for (var i = 1; i <= segments; i++) {
        final t = i / segments;
        final p = Offset.lerp(from, to, t)!;
        // 中段抖动大、两端收敛，第二遍笔触偏移更松
        final wobble = math.sin(t * math.pi) * (pass == 0 ? 1.2 : 2.0);
        path.lineTo(
          p.dx + (rng.nextDouble() - 0.5) * wobble,
          p.dy + (rng.nextDouble() - 0.5) * wobble,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = pass == 0 ? width : width * 0.6
          ..color = Colors.black
              .withValues(alpha: pass == 0 ? alpha : alpha * 0.4),
      );
    }
  }

  /// 枝端标题：黑色小字，向枝伸展方向外侧排布
  ///
  /// 碰撞规避：依次尝试 枝端上方 → 下方 → 更高 → 更低 → 再外侧，
  /// 取第一个不与 [placed] 中已放置标签重叠的位置（树密时兜底最后一个）
  void _drawLabel(Canvas canvas, List<Rect> placed, String text, Offset anchor,
      bool leftSide,
      {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'LXGWWenKai',
          fontSize: bold ? 14 : 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);

    final dx = leftSide ? anchor.dx - painter.width - 6 : anchor.dx + 6;
    final sideDx = leftSide ? -14.0 : 14.0;
    final candidates = <Offset>[
      Offset(dx, anchor.dy - painter.height - 2), // 枝端上方（首选）
      Offset(dx, anchor.dy + 4), // 枝端下方
      Offset(dx, anchor.dy - painter.height - 18), // 更高
      Offset(dx, anchor.dy + 20), // 更低
      Offset(dx + sideDx, anchor.dy - painter.height - 34), // 再外侧更高
    ];

    var pos = candidates.last;
    for (final c in candidates) {
      final rect =
          Rect.fromLTWH(c.dx, c.dy, painter.width, painter.height).inflate(2);
      if (!placed.any((r) => r.overlaps(rect))) {
        pos = c;
        break;
      }
    }
    placed.add(
        Rect.fromLTWH(pos.dx, pos.dy, painter.width, painter.height));
    painter.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(PencilTreePainter oldDelegate) =>
      oldDelegate.tree != tree;
}
