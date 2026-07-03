/// 铅笔树的生态模型与枝丫布局（纯函数，便于单测）
///
/// 树的生命历程（用户定稿 2026-07-02）：章节少 = 细嫩小树；
/// 章节越多树越成长变老（粗干、密枝、排线阴影、年轮结疤）。
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/outline_chapter.dart';

/// 树龄 [0,1]：0 = 幼苗，1 = 老树。指数饱和，约 12 个章节节点近成熟
double treeAge(int totalNodes) {
  if (totalNodes <= 0) return 0;
  return 1 - math.exp(-totalNodes / 12);
}

/// 一根节枝（小说的"节"）
class TwigGeometry {
  const TwigGeometry({
    required this.sectionId,
    required this.title,
    required this.start,
    required this.end,
  });

  final int sectionId;
  final String title;
  final Offset start;
  final Offset end;
}

/// 一根章枝（小说的"章"），含其上节枝
class BranchGeometry {
  const BranchGeometry({
    required this.chapterId,
    required this.title,
    required this.start,
    required this.end,
    required this.leftSide,
    required this.twigs,
  });

  final int chapterId;
  final String title;

  /// 枝根（长在树干上的点）
  final Offset start;

  /// 枝端（章标题锚点）
  final Offset end;

  /// 枝伸向左侧还是右侧（章按顺序左右交替）
  final bool leftSide;

  final List<TwigGeometry> twigs;
}

/// 整棵树的几何
class TreeGeometry {
  const TreeGeometry({
    required this.age,
    required this.trunkBase,
    required this.trunkTop,
    required this.trunkWidth,
    required this.branches,
  });

  /// 树龄 [0,1]，painter 据此加重笔触/排线/结疤
  final double age;

  /// 树干底部中点（地面）
  final Offset trunkBase;

  /// 树干顶端
  final Offset trunkTop;

  /// 树干底部宽度（随树龄变粗）
  final double trunkWidth;

  final List<BranchGeometry> branches;
}

/// 由大纲数据布局整棵树（画布坐标，原点左上）
///
/// 布局规则：
/// - 树干立于画布中央，高度/粗细随树龄增长（细长风格，禁宽版）
/// - 章枝沿树干自下而上、左右交替伸出（第一章最低）
/// - 节枝沿所属章枝均匀分布的上扬短枝
TreeGeometry layoutTree({
  required Size size,
  required List<OutlineChapter> outline,
}) {
  final totalNodes = outline.length +
      outline.fold<int>(0, (sum, c) => sum + c.sections.length);
  final age = treeAge(totalNodes);

  final centerX = size.width / 2;
  final baseY = size.height * 0.88;
  // 幼苗矮小 → 老树高大（仍保持细长，不占满屏）
  final trunkHeight = size.height * (0.22 + 0.44 * age);
  final topY = baseY - trunkHeight;
  final trunkWidth = 3.0 + 11.0 * age;

  final branches = <BranchGeometry>[];
  final n = outline.length;
  for (var i = 0; i < n; i++) {
    final chapter = outline[i].chapter;
    final sections = outline[i].sections;
    final leftSide = i.isEven;

    // 章枝根：树干高度 25%~92% 区间自下而上分布（第一章最低）
    final t = n == 1 ? 0.55 : 0.25 + 0.67 * (i / (n - 1));
    final rootY = baseY - trunkHeight * t;
    final root = Offset(centerX, rootY);

    // 枝长随树龄略增，上扬约 30°
    final length = size.width * (0.20 + 0.08 * age);
    final dir = leftSide ? -1.0 : 1.0;
    final end = Offset(
      centerX + dir * length * math.cos(0.52),
      rootY - length * math.sin(0.52),
    );

    // 节枝：沿章枝 35%~90% 均匀分布的上扬短枝；
    // 长短交替让标签自然岔开（否则节多时文字互相重叠）
    final twigs = <TwigGeometry>[];
    final m = sections.length;
    for (var j = 0; j < m; j++) {
      final tt = m == 1 ? 0.65 : 0.35 + 0.55 * (j / (m - 1));
      final twigStart = Offset.lerp(root, end, tt)!;
      final twigLength = size.width * (j.isEven ? 0.09 : 0.15);
      // 角度也交替（陡/缓），与长短交替配合让末端标签上下岔开
      final twigAngle = j.isEven ? 1.15 : 0.7;
      twigs.add(TwigGeometry(
        sectionId: sections[j].id,
        title: sections[j].title,
        start: twigStart,
        end: Offset(
          twigStart.dx + dir * twigLength * math.cos(twigAngle),
          twigStart.dy - twigLength * math.sin(twigAngle),
        ),
      ));
    }

    branches.add(BranchGeometry(
      chapterId: chapter.id,
      title: chapter.title,
      start: root,
      end: end,
      leftSide: leftSide,
      twigs: twigs,
    ));
  }

  return TreeGeometry(
    age: age,
    trunkBase: Offset(centerX, baseY),
    trunkTop: Offset(centerX, topY),
    trunkWidth: trunkWidth,
    branches: branches,
  );
}
