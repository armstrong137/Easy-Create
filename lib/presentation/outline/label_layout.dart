import 'package:flutter/painting.dart';

import 'magic_tree_model.dart';

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
/// 字号 17/15：用户反馈"标签胶囊太小"，加大一档
TextStyle labelStyle({required bool bold}) => TextStyle(
      fontFamily: 'LXGWWenKai',
      fontSize: bold ? 17 : 15,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: const Color(0xFF3A2A18), // 深树皮色，配魔树
    );

/// 为魔树放置全部标签（含碰撞规避）：
/// 章标签在左枝端外侧、节标签在右枝端外侧；候选位依次为
/// 端部外上方 → 下方 → 更高 → 更低，取首个不重叠位置。
/// [canvasWidth] 非空时将标签水平钳制在画布内（防止贴边章枝把字挤出屏幕）；
/// [textScaler] 必须与渲染端一致（系统字体缩放），否则文字会被截断
List<PlacedLabel> placeMagicLabels(MagicTreeLayout layout,
    {double? canvasWidth, TextScaler textScaler = TextScaler.noScaling}) {
  final placed = <PlacedLabel>[];

  void place(VineBranch vine) {
    final bold = vine.isChapter;
    final painter = TextPainter(
      text: TextSpan(text: vine.title, style: labelStyle(bold: bold)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textScaler: textScaler,
    )..layout(maxWidth: 160);

    final anchor = vine.tip;
    // 章枝朝左 → 标签放端点左侧；节枝朝右 → 端点右侧
    var dx = vine.isChapter ? anchor.dx - painter.width - 6 : anchor.dx + 6;
    double clampX(double x) {
      if (canvasWidth == null) return x;
      final hi = canvasWidth - painter.width - 4;
      return hi > 4 ? x.clamp(4.0, hi) : 4.0;
    }

    dx = clampX(dx);
    // 密集时首列四个纵向槽位不够，再开一列"内侧列"（横向完全错开）
    final inner =
        clampX(dx + (vine.isChapter ? 1 : -1) * (painter.width + 22));
    final candidates = <Offset>[
      for (final col in [dx, inner]) ...[
        Offset(col, anchor.dy - painter.height - 16), // 端部上方（避开卷勾）
        Offset(col, anchor.dy + 8),
        Offset(col, anchor.dy - painter.height - 34),
        Offset(col, anchor.dy + 26),
      ],
    ];

    var pos = candidates.last;
    for (final c in candidates) {
      // inflate(8)：标签带羊皮纸胶囊底（加大版），留足间距防胶囊叠边
      final rect =
          Rect.fromLTWH(c.dx, c.dy, painter.width, painter.height).inflate(8);
      if (!placed.any((l) => l.rect.inflate(8).overlaps(rect))) {
        pos = c;
        break;
      }
    }
    placed.add(PlacedLabel(
      text: vine.title,
      // 宽度取整 +2 余量：胶囊边框与像素取整不吞字
      rect: Rect.fromLTWH(
          pos.dx, pos.dy, painter.width.ceilToDouble() + 2, painter.height),
      bold: bold,
      chapterId: vine.isChapter ? vine.id : null,
      sectionId: vine.isChapter ? null : vine.id,
    ));
  }

  // 章先占位，节随后避让
  layout.chapters.forEach(place);
  layout.sections.forEach(place);
  return placed;
}
