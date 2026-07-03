import 'package:flutter/painting.dart';

import 'tree_model.dart';

/// 一枚已放置的枝端标签：几何 + 归属（交互热区与绘制共用）
class PlacedLabel {
  const PlacedLabel({
    required this.text,
    required this.rect,
    required this.bold,
    this.chapterId,
    this.sectionId,
  });

  final String text;

  /// 标签实际占位（已经过碰撞规避）
  final Rect rect;

  /// 章标签加粗
  final bool bold;

  /// 二选一：章标签带 chapterId，节标签带 sectionId
  final int? chapterId;
  final int? sectionId;
}

/// 标签文字样式（绘制与测量必须一致）
TextStyle labelStyle({required bool bold}) => TextStyle(
      fontFamily: 'LXGWWenKai',
      fontSize: bold ? 14 : 12,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: const Color(0xFF000000),
    );

/// 为整棵树放置全部标签（含碰撞规避），布局/绘制/交互共享
///
/// 规则：章标题先占位；候选位依次为 枝端上方 → 下方 → 更高 → 更低 →
/// 再外侧更高，取第一个不与已放置标签重叠者（密集时兜底最后一个）。
List<PlacedLabel> placeLabels(TreeGeometry tree) {
  final placed = <PlacedLabel>[];

  void place(String text, Offset anchor, bool leftSide,
      {bool bold = false, int? chapterId, int? sectionId}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle(bold: bold)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);

    final dx = leftSide ? anchor.dx - painter.width - 6 : anchor.dx + 6;
    final sideDx = leftSide ? -14.0 : 14.0;
    final candidates = <Offset>[
      Offset(dx, anchor.dy - painter.height - 2),
      Offset(dx, anchor.dy + 4),
      Offset(dx, anchor.dy - painter.height - 18),
      Offset(dx, anchor.dy + 20),
      Offset(dx + sideDx, anchor.dy - painter.height - 34),
    ];

    var pos = candidates.last;
    for (final c in candidates) {
      final rect =
          Rect.fromLTWH(c.dx, c.dy, painter.width, painter.height).inflate(2);
      if (!placed.any((l) => l.rect.inflate(2).overlaps(rect))) {
        pos = c;
        break;
      }
    }
    placed.add(PlacedLabel(
      text: text,
      rect: Rect.fromLTWH(pos.dx, pos.dy, painter.width, painter.height),
      bold: bold,
      chapterId: chapterId,
      sectionId: sectionId,
    ));
  }

  for (final branch in tree.branches) {
    // 章标题先占位，节标签随后避让（与原 painter 行为一致）
    place(branch.title, branch.end, branch.leftSide,
        bold: true, chapterId: branch.chapterId);
    for (final twig in branch.twigs) {
      place(twig.title, twig.end, branch.leftSide, sectionId: twig.sectionId);
    }
  }
  return placed;
}
