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
      // 地址仍稳定；固定扰动打破等距叉阵列，椭圆映射避免冠顶长成矩形。
      final jitter = next == 0 ? Offset.zero : Offset(
        math.sin(next * 12.9898 + 1.7), math.sin(next * 7.233 + 4.1));
      final point = cell.center + Offset(jitter.dx * cell.width * .28,
          jitter.dy * cell.height * .28);
      final u = (point.dx - 500) / 380;
      final v = (point.dy - 530) / 350;
      final end = Offset(500 + 380 * u * math.sqrt(1 - v * v / 2),
          530 + 350 * v * math.sqrt(1 - u * u / 2));
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
