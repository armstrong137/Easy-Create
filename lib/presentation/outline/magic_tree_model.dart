/// 魔树布局模型（2026-07-03 镜头窗口改版，用户定稿）：
/// - 整树 = 用户三张魔树摄影素材；章/节枝 = 素材裁出的真实卷须精灵图
/// - **章序沿树自上而下**：第一章在树顶方向，新章向土壤方向生长
///   （下滑=更多章，符合树的生长方向）
/// - **≤2 章**：整树可见；**>2 章**：镜头窗口模式——一屏恰好两章，
///   左滑章节时树背景跟随（首章见树顶、末章见土壤，虚拟树高随章数增长），
///   右滑小节时树背景不动
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/outline_chapter.dart';

/// 素材米白底色（三张魔树图角像素实测），页面底色与之一致使整图无缝
const kParchment = Color(0xFFFDF6EC);

/// 素材原始尺寸（三张魔树图同尺寸）
const kStageImageWidth = 941.0;
const kStageImageHeight = 1672.0;

/// 卷须精灵图（tendril_chapter.png 实测 130x106，节图为其镜像）：
/// 根茬在右缘 31% 高度处，螺旋端在左上角附近
const kTendrilAspect = 106 / 130;
const kTendrilRootYFrac = 0.31;
const kTendrilTipXFrac = 0.06;
const kTendrilTipYFrac = 0.22;

/// 窗口模式节行高（含间距）
const kSectionRowHeight = 46.0;

/// 每章带底部预留的空白"加节区"高度：恒有落在本章带内的空白可双击加节
/// （用户定稿：小节铺满时仍要能双击右侧空白给本章加节）
const kSectionAddZone = 96.0;

/// 小节标签下每条灵感小卡占的高度（有灵感的小节槽位据此加高）
/// 26：小卡加大内边距后需多留高度，避免最后一节的小卡冲出章带被裁
const kNoteRowHeight = 26.0;

/// 小节标签下最多显示的灵感条数
const kMaxSectionNotes = 2;

/// 树龄 [0,1]：随章节规模成长（保留用于尺寸微调）
double treeAge(int totalNodes) {
  if (totalNodes <= 0) return 0;
  return 1 - math.exp(-totalNodes / 12);
}

/// 成长阶段 1..3：幼苗（零创作）→ 缠绕藤 → 参天藤
int stageForNodes(int totalNodes) {
  if (totalNodes <= 0) return 1;
  return totalNodes < 12 ? 2 : 3;
}

/// 虚拟树高倍数：章越多树越高（镜头一次只看得到一段树干）。
/// 用户定稿"树的生长速度必须随着章节的增多而变化"
double treeGrowthFactor(int chapterCount) {
  if (chapterCount <= 2) return 1;
  return 1 + math.min(1.15, 0.09 * (chapterCount - 2));
}

/// 每阶段茎干轮廓（归一化到素材图：y 相对图高，半宽相对图宽）
class _Stalk {
  const _Stalk(this.topY, this.botY, this.topHalfW, this.botHalfW);

  final double topY;
  final double botY;
  final double topHalfW;
  final double botHalfW;
}

const _stalks = <int, _Stalk>{
  1: _Stalk(0.46, 0.83, 0.018, 0.028), // 幼苗细茎
  2: _Stalk(0.15, 0.86, 0.045, 0.100), // 缠绕藤
  3: _Stalk(0.045, 0.88, 0.050, 0.135), // 参天藤
};

/// 一根卷须枝（章或节共用）：精灵图矩形 + 根/端锚点
class VineBranch {
  const VineBranch({
    required this.id,
    required this.title,
    required this.isChapter,
    required this.root,
    required this.spriteRect,
    required this.tip,
    this.clipChapterId,
  });

  /// chapterId 或 sectionId
  final int id;
  final String title;
  final bool isChapter;

  /// 与茎干相接的根点（生长动画的缩放锚点）
  final Offset root;

  /// 精灵图显示区域（章图向左伸、节图向右伸）
  final Rect spriteRect;

  /// 螺旋端（标签锚点）
  final Offset tip;

  /// 非空 = 该节枝须裁剪在此章的高度带内（窗口模式滚动小节用）
  final int? clipChapterId;
}

/// 整棵魔树的布局
class MagicTreeLayout {
  const MagicTreeLayout({
    required this.age,
    required this.stage,
    required this.windowMode,
    required this.imageRect,
    required this.trunkRect,
    required this.chapters,
    required this.sections,
    required this.chapterBands,
    required this.maxChapterOffset,
    required this.sectionScrollMax,
  });

  final double age;

  /// 成长阶段 1..3（决定用哪张素材）
  final int stage;

  /// true = 镜头窗口模式（>2 章）
  final bool windowMode;

  /// 阶段素材整图的显示区域（窗口模式下高于画布，随章滚动上下平移）
  final Rect imageRect;

  /// 茎干柱区域（枝根吸附范围）
  final Rect trunkRect;

  /// 可见章枝（向左）
  final List<VineBranch> chapters;

  /// 可见节枝（向右）
  final List<VineBranch> sections;

  /// 可见章的高度带：chapterId → (bandTop, bandBottom)。
  /// 点击右侧空白时按点击 y 落在哪个带决定节挂到哪一章
  final Map<int, (double, double)> chapterBands;

  /// 章镜头最大偏移（= max(0, 章数-2)；≤2 章恒为 0）
  final double maxChapterOffset;

  /// 各章小节列表的最大滚动量（0 = 全部放得下不用滚）
  final Map<int, double> sectionScrollMax;

  /// 点击右侧空白的 y → 对应章 id（无章时 null）
  int? chapterForY(double y) {
    if (chapterBands.isEmpty) return null;
    for (final e in chapterBands.entries) {
      if (y >= e.value.$1 && y <= e.value.$2) return e.key;
    }
    // 超出所有带：章序自上而下 → 之上归最早的章、之下归最晚的章
    final sorted = chapterBands.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    return y < sorted.first.value.$1 ? sorted.first.key : sorted.last.key;
  }
}

/// 布局整棵魔树。
/// [chapterOffset]：窗口模式镜头位置（0=首章顶端，maxChapterOffset=末章）；
/// [sectionScrolls]：各章小节列表当前滚动量（窗口模式）。
MagicTreeLayout layoutMagicTree({
  required Size size,
  required List<OutlineChapter> outline,
  double chapterOffset = 0,
  Map<int, double> sectionScrolls = const {},
  Map<int, int> sectionNoteCounts = const {},
}) {
  final n = outline.length;
  final totalNodes =
      n + outline.fold<int>(0, (sum, c) => sum + c.sections.length);
  final age = treeAge(totalNodes);
  final stage = stageForNodes(totalNodes);

  return n > 2
      ? _layoutWindow(
          size,
          outline,
          stage,
          age,
          chapterOffset,
          sectionScrolls,
          sectionNoteCounts,
        )
      : _layoutWholeTree(size, outline, stage, age);
}

/// ≤2 章：整树可见，章枝直接锚在照片茎干上（第一章靠上）
MagicTreeLayout _layoutWholeTree(
  Size size,
  List<OutlineChapter> outline,
  int stage,
  double age,
) {
  // 阶段素材：整树占画布高 84%、贴底居中，左右留米白呼吸区
  final scale = math.min(
    size.width / kStageImageWidth,
    size.height * 0.84 / kStageImageHeight,
  );
  final dispW = kStageImageWidth * scale;
  final dispH = kStageImageHeight * scale;
  final imageRect = Rect.fromLTWH(
    (size.width - dispW) / 2,
    size.height - 8 - dispH,
    dispW,
    dispH,
  );

  final stalk = _stalks[stage]!;
  final topY = imageRect.top + stalk.topY * dispH;
  final botY = imageRect.top + stalk.botY * dispH;
  final span = botY - topY;
  final cx = imageRect.center.dx;
  final trunkRect = Rect.fromLTRB(
    cx - stalk.botHalfW * dispW,
    topY,
    cx + stalk.botHalfW * dispW,
    botY,
  );

  double halfWAt(double y) {
    final t = ((y - topY) / span).clamp(0.0, 1.0);
    return (stalk.topHalfW + (stalk.botHalfW - stalk.topHalfW) * t) * dispW;
  }

  // 枝根吸附段（避开顶部细梢与底部土堆）
  final attachTop = topY + span * 0.14;
  final attachBot = botY - span * 0.10;
  final attachRange = attachBot - attachTop;

  final n = outline.length;
  final chapters = <VineBranch>[];
  final sections = <VineBranch>[];
  final bands = <int, (double, double)>{};
  final chSpacing = n <= 1 ? attachRange : attachRange / (n - 1);
  // 章序自上而下：第一章在树梢方向
  final rootYs = <double>[
    for (var i = 0; i < n; i++)
      attachTop + attachRange * (n == 1 ? 0.15 : i / (n - 1)),
  ];

  for (var i = 0; i < n; i++) {
    final chapter = outline[i].chapter;
    final rootY = rootYs[i];
    final root = Offset(cx - halfWAt(rootY) + dispW * 0.006, rootY);

    var len = math.min(root.dx - 10, size.width * 0.28);
    len = math.min(len, size.shortestSide * 0.25);
    len = math.min(len, math.max(52.0, chSpacing * 1.1));
    len = math.max(len, 48.0);
    final h = len * kTendrilAspect;
    final spriteRect = Rect.fromLTWH(
      root.dx - len,
      root.dy - h * kTendrilRootYFrac,
      len,
      h,
    );
    chapters.add(
      VineBranch(
        id: chapter.id,
        title: chapter.title,
        isChapter: true,
        root: root,
        spriteRect: spriteRect,
        tip: Offset(
          spriteRect.left + len * kTendrilTipXFrac,
          spriteRect.top + h * kTendrilTipYFrac,
        ),
      ),
    );

    // 高度带：相邻章根中线分界（首章向上到树梢、末章向下到茎底）
    final bandTop = i == 0
        ? attachTop - span * 0.10
        : (rootYs[i - 1] + rootY) / 2;
    final bandBottom = i == n - 1 ? botY : (rootY + rootYs[i + 1]) / 2;
    bands[chapter.id] = (bandTop, bandBottom);

    // 节枝：向右，带内自上而下 = 第一节最高（阅读顺序）
    final sectionList = outline[i].sections;
    final m = sectionList.length;
    final secSpacing = (bandBottom - bandTop) / (m + 1);
    for (var j = 0; j < m; j++) {
      final sy = bandTop + secSpacing * (j + 1);
      final sRoot = Offset(cx + halfWAt(sy) - dispW * 0.006, sy);
      var sLen = math.min(size.width - sRoot.dx - 10, size.width * 0.21);
      sLen = math.min(sLen, size.shortestSide * 0.18);
      sLen = math.min(sLen, math.max(38.0, secSpacing * 1.2));
      sLen = math.max(sLen, 34.0);
      final sh = sLen * kTendrilAspect;
      final sRect = Rect.fromLTWH(
        sRoot.dx,
        sy - sh * kTendrilRootYFrac,
        sLen,
        sh,
      );
      sections.add(
        VineBranch(
          id: sectionList[j].id,
          title: sectionList[j].title,
          isChapter: false,
          root: sRoot,
          spriteRect: sRect,
          tip: Offset(
            sRect.right - sLen * kTendrilTipXFrac,
            sRect.top + sh * kTendrilTipYFrac,
          ),
        ),
      );
    }
  }

  return MagicTreeLayout(
    age: age,
    stage: stage,
    windowMode: false,
    imageRect: imageRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: bands,
    maxChapterOffset: 0,
    sectionScrollMax: const {},
  );
}

/// >2 章：镜头窗口模式——一屏两章，树背景随章滚动平移
MagicTreeLayout _layoutWindow(
  Size size,
  List<OutlineChapter> outline,
  int stage,
  double age,
  double chapterOffset,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final n = outline.length;
  final maxOffset = (n - 2).toDouble();
  final offset = chapterOffset.clamp(0.0, maxOffset);

  // 虚拟树高随章数增长；树干撑满全屏（镜头贴近，只见一段树干）
  final k = treeGrowthFactor(n);
  final dispH = size.height * k;
  final dispW = dispH * (kStageImageWidth / kStageImageHeight);
  // 镜头平移：offset 0 → 见树顶；offset 最大 → 见土壤
  final panT = maxOffset == 0 ? 0.0 : offset / maxOffset;
  final imageTop = -(dispH - size.height) * panT;
  final imageRect = Rect.fromLTWH(
    (size.width - dispW) / 2,
    imageTop,
    dispW,
    dispH,
  );

  final stalk = _stalks[stage]!;
  final stalkTopY = imageRect.top + stalk.topY * dispH;
  final stalkBotY = imageRect.top + stalk.botY * dispH;
  final cx = imageRect.center.dx;
  final trunkRect = Rect.fromLTRB(
    cx - stalk.botHalfW * dispW,
    math.max(0, stalkTopY),
    cx + stalk.botHalfW * dispW,
    math.min(size.height, stalkBotY),
  );

  double halfWAt(double y) {
    final t = ((y - stalkTopY) / (stalkBotY - stalkTopY)).clamp(0.0, 1.0);
    return (stalk.topHalfW + (stalk.botHalfW - stalk.topHalfW) * t) * dispW;
  }

  // 高度带：一屏恰好两章
  const topPad = 6.0;
  final bandH = (size.height - topPad * 2) / 2;

  final chapters = <VineBranch>[];
  final sections = <VineBranch>[];
  final bands = <int, (double, double)>{};
  final scrollMax = <int, double>{};

  // 一屏严格只显两章：当前镜头档 iStart 与其下一章。
  // 用户定稿：左侧不能同时看到三章，否则不清楚新加的小节归到哪一章。
  final iStart = offset.floor();
  for (var i = 0; i < n; i++) {
    if (i < iStart || i > iStart + 1) continue;
    final bandTop = topPad + (i - offset) * bandH;
    final bandBottom = bandTop + bandH;
    final chapter = outline[i].chapter;
    bands[chapter.id] = (bandTop, bandBottom);

    // 章枝锚点：带顶往下一行，但**必须钳制在可见树干范围内**——
    // 否则首章的枝根会落在树顶细梢上方的空白区、与树脱离
    // （用户反馈"引子的树枝都和大树脱离了"）。
    final trunkSpan = stalkBotY - stalkTopY;
    final rootY = (bandTop + 40).clamp(
      stalkTopY + trunkSpan * 0.06,
      stalkBotY - trunkSpan * 0.06,
    );
    // 根深埋进树干（宽度 42% 处而非边缘），进一步防止与弯曲树干有缝
    final root = Offset(cx - halfWAt(rootY) * 0.42, rootY);
    var len = math.min(root.dx - 10, size.width * 0.26);
    len = math.max(math.min(len, size.shortestSide * 0.22), 48.0);
    final h = len * kTendrilAspect;
    final spriteRect = Rect.fromLTWH(
      root.dx - len,
      rootY - h * kTendrilRootYFrac,
      len,
      h,
    );
    chapters.add(
      VineBranch(
        id: chapter.id,
        title: chapter.title,
        isChapter: true,
        root: root,
        spriteRect: spriteRect,
        tip: Offset(
          spriteRect.left + len * kTendrilTipXFrac,
          spriteRect.top + h * kTendrilTipYFrac,
        ),
      ),
    );

    // 节行：带内自上而下排列，放不下时可滚（右滑），树背景不动。
    // 起点必须落在"章根之下 + 可见树干之内"：章根 rootY 已被钳进树干范围，
    // 若仍用带几何顶(bandTop+34)，首章带顶高过树干时小节会飘到章的上方、
    // 甚至窜到树顶魔毯球旁（用户反馈：章节多了之后小节错位）。
    // 终点也钳在树干底之内，末章小节不落到土壤上。
    final sectionList = outline[i].sections;
    final m = sectionList.length;
    final contentTop = math.max(bandTop + 34, rootY + kSectionRowHeight * 0.5);
    // 带内底部预留一条空白"加节区"：小节区终点上抬 kSectionAddZone，
    // 使 [contentBottom, 带底] 恒为落在本章带内的空白，双击即可给本章加节，
    // 不会因小节铺到带边界而把双击落到下一章（用户定稿：保留双击右侧空白加节）。
    final trunkFloor = math.min(bandBottom - 10, stalkBotY - trunkSpan * 0.04);
    final contentBottom = math.max(
      contentTop + kSectionRowHeight,
      trunkFloor - kSectionAddZone,
    );
    final availH = math.max(0.0, contentBottom - contentTop);

    // 预算各节槽位顶部（累加变高槽位）
    final rawTops = <double>[];
    var raw = 0.0;
    for (var j = 0; j < m; j++) {
      rawTops.add(raw);
      final notes = math.min(
        sectionNoteCounts[sectionList[j].id] ?? 0,
        kMaxSectionNotes,
      );
      raw += kSectionRowHeight + notes * kNoteRowHeight;
    }
    // 末尾预留空白"加节区"：无论小节多满，右滑到底都能露出可双击加节的空白
    // （用户定稿：维持一屏两章 + 右侧滚动看全 + 双击右侧空白加节，需保证总有空白可点）
    raw += kSectionRowHeight * 2.5;
    final overflow = math.max(0.0, raw - availH);
    scrollMax[chapter.id] = overflow;
    final scroll = (sectionScrolls[chapter.id] ?? 0).clamp(0.0, overflow);

    for (var j = 0; j < m; j++) {
      final sy = contentTop + rawTops[j] + kSectionRowHeight / 2 - scroll;
      // 行滚出带外就不布局（带内边缘由页面按带裁剪）
      if (sy < contentTop - kSectionRowHeight ||
          sy > contentBottom + kSectionRowHeight) {
        continue;
      }
      final sRoot = Offset(cx + halfWAt(sy) * 0.42, sy);
      var sLen = math.min(size.width - sRoot.dx - 10, size.width * 0.18);
      sLen = math.max(math.min(sLen, size.shortestSide * 0.16), 34.0);
      final sh = sLen * kTendrilAspect;
      final sRect = Rect.fromLTWH(
        sRoot.dx,
        sy - sh * kTendrilRootYFrac,
        sLen,
        sh,
      );
      sections.add(
        VineBranch(
          id: sectionList[j].id,
          title: sectionList[j].title,
          isChapter: false,
          root: sRoot,
          spriteRect: sRect,
          tip: Offset(
            sRect.right - sLen * kTendrilTipXFrac,
            sRect.top + sh * kTendrilTipYFrac,
          ),
          clipChapterId: chapter.id,
        ),
      );
    }
  }

  return MagicTreeLayout(
    age: age,
    stage: stage,
    windowMode: true,
    imageRect: imageRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: bands,
    maxChapterOffset: maxOffset,
    sectionScrollMax: scrollMax,
  );
}
