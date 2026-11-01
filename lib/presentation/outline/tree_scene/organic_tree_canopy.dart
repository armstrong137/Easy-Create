import 'dart:math' as math;
import 'dart:ui';

/// 章节按固定四叉地址进入冠层；追加只生成新枝，不移动既有节点。
class OrganicCanopyBranch {
  OrganicCanopyBranch._(this.cell, this.spine, this.metric, this.parent);

  final Rect cell;
  final Path spine;
  final PathMetric metric;
  final int? parent;
  static const attachment = .8;
  static const tipRatio = .85;
  static const rootRatio = .8;
  static final _branches = <OrganicCanopyBranch>[];

  Offset get anchor =>
      metric.getTangentForOffset(metric.length * attachment)!.position;

  static OrganicCanopyBranch at(int index, Offset root) {
    while (_branches.length <= index) {
      final next = _branches.length;
      final parent = next == 0 ? null : (next - 1) ~/ 4;
      final mother = parent == null ? null : _branches[parent];
      final quadrant = (next - 1) % 4;
      final cell = mother == null
          ? const Rect.fromLTWH(120, 180, 760, 700)
          : Rect.fromLTWH(
              mother.cell.left + (quadrant % 2) * mother.cell.width / 2,
              mother.cell.top + (quadrant ~/ 2) * mother.cell.height / 2,
              mother.cell.width / 2,
              mother.cell.height / 2,
            );
      final start = mother?.anchor ?? root;
      final end = cell.center;
      final delta = end - start;
      final lift = math.min(delta.distance * .16, 35.0);
      final spine = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + delta.dx * .25,
          start.dy + delta.dy * .25 - lift,
          end.dx - delta.dx * .25,
          end.dy - lift,
          end.dx,
          end.dy,
        );
      _branches.add(
        OrganicCanopyBranch._(
          cell,
          spine,
          spine.computeMetrics().first,
          parent,
        ),
      );
    }
    return _branches[index];
  }
}
