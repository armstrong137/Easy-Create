/// 魔树布局模型（2026-07-03 镜头窗口改版，用户定稿）：
/// - 整树 = 用户三张魔树摄影素材；章/节枝 = 素材裁出的真实卷须精灵图
/// - **章序沿树自上而下**：第一章在树顶方向，新章向土壤方向生长
///   （下滑=更多章，符合树的生长方向）
/// - **≤2 章**：整树可见；**>2 章**：镜头窗口模式——一屏恰好两章，
///   左滑章节时完整树图平移（首章见树顶、末章见土壤），
///   右滑小节时树背景不动
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/outline_chapter.dart';

/// 素材米白底色（帧序列角像素实测 253,247,235 ~ 253,246,236），页面底色与之一致
const kParchment = Color(0xFFFDF6EC);

/// 单帧原始尺寸（28 帧同尺寸）
const kStageImageWidth = 941.0;
const kStageImageHeight = 1672.0;

/// 生长帧序列目录
const kTreeFrameDir = 'assets/textures/tree_frames';

/// 只用 f05..f26 这 22 帧。逐帧实测：f01~f04 土堆**反向缩小**（最宽 0.276→0.139）、
/// f27/f28 植株**反而变矮**（0.721→0.719→0.702）；这两段素材修好后
/// 改这两个常量即可启用，代码无需其它改动。
const kTreeFrameFirst = 5;
const kTreeFrameLast = 26;

/// 节点数（章+节）→ 帧号：0 个节点用首帧，之后**每加一个节点正好前进一帧**，
/// 到末帧封顶。生长的连贯度因此等于素材本身的连贯度——不再有拉伸、不再有换档。
int treeFrameFor(int totalNodes) =>
    (kTreeFrameFirst + totalNodes).clamp(kTreeFrameFirst, kTreeFrameLast);

String treeFrameAsset(int frame) =>
    '$kTreeFrameDir/magic_tree_f${frame.toString().padLeft(2, '0')}.jpg';

/// 素材里土堆底边的位置（逐帧实测 0.875~0.904，取最低值），用来把土堆摆到贴屏底
const kFrameContentBottom = 0.904;

/// 每帧内容的横向占比（含叶与土堆，逐帧实测取最宽行）——放大时据此防止出画布
const _frameContentWidth = <int, double>{
  5: 0.148,
  6: 0.158,
  7: 0.168,
  8: 0.238,
  9: 0.239,
  10: 0.255,
  11: 0.282,
  12: 0.316,
  13: 0.336,
  14: 0.374,
  15: 0.414,
  16: 0.456,
  17: 0.494,
  18: 0.539,
  19: 0.582,
  20: 0.618,
  21: 0.661,
  22: 0.682,
  23: 0.718,
  24: 0.739,
  25: 0.762,
  26: 0.781,
};

/// 每帧内容占画布可用高度的目标比例：从首帧的 [kFrameFillFirst] 长到末帧的
/// [kFrameFillLast]。
///
/// 不能让所有帧共用"最大帧塞得进屏幕"的同一个画幅：素材从 f05 到 f26 内容高度
/// 差 5.9 倍，那样 2 章时树只占屏高 19%、上方 80% 全是空白，标签也挤在一截
/// 134px 的矮树干上（实测）。按帧自适应放大后，观感成长压到约 2 倍，
/// 但树永远不显小、树干一直有放标签的余量。等比放大、随帧单调递增，不会回弹。
const kFrameFillFirst = 0.45;
const kFrameFillLast = 0.92;

/// 画布上下留白
const _kFramePadTop = 12.0;
const _kFramePadBottom = 8.0;

/// 该帧的目标"屏上内容高度"占画布可用高度的比例（随帧线性上升）
double _fillFor(int frame) {
  final t = (frame - kTreeFrameFirst) / (kTreeFrameLast - kTreeFrameFirst);
  return kFrameFillFirst + (kFrameFillLast - kFrameFillFirst) * t;
}

/// 全序列**统一**的收缩系数：窄画布上后段几帧植株很宽，按目标比例放大会横向
/// 出画布。逐帧各自缩会破坏单调（实测 f25→f26 屏上高度反降 0.7%），
/// 所以取"所有帧都不出画布"的统一系数，整条曲线等比压低，单调性不受影响。
double _fillShrink(Size size) {
  final avail = size.height - _kFramePadTop - _kFramePadBottom;
  const aspect = kStageImageHeight / kStageImageWidth;
  var k = 1.0;
  for (var f = kTreeFrameFirst; f <= kTreeFrameLast; f++) {
    final desired =
        _fillFor(f) * avail / (kFrameContentBottom - _stalks[f]!.topY);
    final maxH = size.width / _frameContentWidth[f]! * aspect;
    if (maxH < desired) k = math.min(k, maxH / desired);
  }
  return k;
}

/// 某一帧的画幅：等比放大到目标占屏比例，土堆底贴屏底。
/// **绝不做非等比拉伸**——生长由序列自己表达。
Rect _frameRect(Size size, int frame) {
  final avail = size.height - _kFramePadTop - _kFramePadBottom;
  final contentH = kFrameContentBottom - _stalks[frame]!.topY;
  final h = _fillFor(frame) * _fillShrink(size) * avail / contentH;
  final w = h * (kStageImageWidth / kStageImageHeight);
  return Rect.fromLTWH(
    (size.width - w) / 2,
    size.height - _kFramePadBottom - kFrameContentBottom * h,
    w,
    h,
  );
}

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
const kMaxSectionNotes = 3;

/// 右下速记按钮占用约 56px + 24px 边距，再多留一点呼吸区。
const _kQuickCaptureBottomGuard = 96.0;

/// 树龄 [0,1]：随章节规模成长（保留用于尺寸微调）
double treeAge(int totalNodes) {
  if (totalNodes <= 0) return 0;
  return 1 - math.exp(-totalNodes / 12);
}

/// 章+节总数（树的"体量"，成长与档位都看它）
int totalTreeNodes(List<OutlineChapter> outline) =>
    outline.length + outline.fold<int>(0, (sum, c) => sum + c.sections.length);

/// 新增章节的视觉流程：先让新枝生长，再移动镜头。
enum ChapterGrowthStep { growBranch, panCamera }

/// 新增章节的动作计划：枝条长完后镜头才平滑跟随（不同时发生，
/// 否则用户看到的不是树枝长出来，而是整棵树和土壤一起滑动）。
class ChapterGrowthMotionPlan {
  const ChapterGrowthMotionPlan({
    required this.targetOffset,
    required this.steps,
    required this.panDelay,
  });

  /// 镜头最终档位（新章所在档）
  final double targetOffset;

  /// 按序执行的动作
  final List<ChapterGrowthStep> steps;

  /// 枝条生长到镜头启动之间的间隔
  final Duration panDelay;
}

ChapterGrowthMotionPlan chapterGrowthMotionPlan({
  required int oldCount,
  required int newCount,
  required double currentOffset,
}) {
  final target = newCount > 2 ? (newCount - 2).toDouble() : 0.0;
  final shouldPan = (target - currentOffset).abs() > 0.01;
  return ChapterGrowthMotionPlan(
    targetOffset: target,
    steps: shouldPan
        ? const [ChapterGrowthStep.panCamera, ChapterGrowthStep.growBranch]
        : const [ChapterGrowthStep.growBranch],
    panDelay: const Duration(milliseconds: 620),
  );
}

sealed class TreeImagePieces {
  const TreeImagePieces({required this.bounds});

  final Rect bounds;
}

class WholeTreeImagePieces extends TreeImagePieces {
  const WholeTreeImagePieces({required super.bounds, required this.asset});

  final String asset;
}

TreeImagePieces layoutMagicTreeImagePieces(MagicTreeLayout layout) =>
    WholeTreeImagePieces(
      bounds: layout.imageRect,
      asset: treeFrameAsset(layout.frame),
    );

/// 换帧时"这一波生长"扫到哪儿了：0=还在土里，1=已扫过树冠。
///
/// 用擦除而非交叉淡入淡出：相邻帧各 50% 混合时叶子会半透明重叠（实测 f19/f20
/// 明显鬼影），读作 PPT 翻页。擦除没有半透明，且相邻帧差异本就小，
/// 擦除线扫过几乎看不出来，读作一波生长沿藤上行。
const kGrowWipeDuration = Duration(milliseconds: 700);

/// 擦除线的软边高度（画布像素）：硬切会看出一条横线
const kGrowWipeFeather = 26.0;

/// 每帧的茎干轮廓（归一化到素材图：y 相对图高，半宽相对图宽）。
/// 枝丫锚点全靠它——章/节枝要挂在**这一帧实际的树干**上。
class _Stalk {
  const _Stalk(this.topY, this.botY, this.topHalfW, this.botHalfW);

  /// 植株最高点
  final double topY;

  /// 土堆冒头处（树干扎进土里的位置）——枝丫下界据此算，不会长进土里
  final double botY;
  final double topHalfW;
  final double botHalfW;
}

/// 逐帧实测（脚本量中轴连通段：顶部取 12% 处、底部取土堆上方 6% 处）。
/// 半宽经**保序回归 + 3 点平滑**：原始测量在 0.006~0.020 之间来回跳（量到叶子
/// 还是量到藤的差别），直接用会让枝丫锚点逐帧左右抖。
const _stalks = <int, _Stalk>{
  5: _Stalk(0.777, 0.882, 0.0032, 0.0135),
  6: _Stalk(0.756, 0.880, 0.0037, 0.0161),
  7: _Stalk(0.732, 0.879, 0.0059, 0.0259),
  8: _Stalk(0.708, 0.868, 0.0081, 0.0352),
  9: _Stalk(0.678, 0.868, 0.0097, 0.0428),
  10: _Stalk(0.646, 0.867, 0.0105, 0.0478),
  11: _Stalk(0.614, 0.866, 0.0112, 0.0605),
  12: _Stalk(0.578, 0.861, 0.0145, 0.0728),
  13: _Stalk(0.542, 0.859, 0.0176, 0.0838),
  14: _Stalk(0.500, 0.857, 0.0215, 0.0901),
  15: _Stalk(0.471, 0.854, 0.0232, 0.1093),
  16: _Stalk(0.435, 0.850, 0.0268, 0.1282),
  17: _Stalk(0.401, 0.847, 0.0310, 0.1436),
  18: _Stalk(0.355, 0.840, 0.0346, 0.1587),
  19: _Stalk(0.314, 0.839, 0.0360, 0.1748),
  20: _Stalk(0.281, 0.833, 0.0360, 0.1980),
  21: _Stalk(0.249, 0.831, 0.0360, 0.2087),
  22: _Stalk(0.231, 0.825, 0.0438, 0.2157),
  23: _Stalk(0.209, 0.823, 0.0515, 0.2157),
  24: _Stalk(0.188, 0.819, 0.0593, 0.2222),
  25: _Stalk(0.169, 0.818, 0.0593, 0.2286),
  26: _Stalk(0.156, 0.816, 0.0593, 0.2351),
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
    this.showTendril = true,
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

  /// false = 只保留标签/热区，不绘制枝丫（用于靠近泥土的节）
  final bool showTendril;

  /// 非空 = 该节枝须裁剪在此章的高度带内（窗口模式滚动小节用）
  final int? clipChapterId;
}

/// 整棵魔树的布局
class MagicTreeLayout {
  const MagicTreeLayout({
    required this.age,
    required this.frame,
    required this.windowMode,
    required this.viewportHeight,
    required this.imageRect,
    required this.trunkRect,
    required this.chapters,
    required this.sections,
    required this.chapterBands,
    required this.maxChapterOffset,
    required this.sectionScrollMax,
  });

  final double age;

  /// 当前生长帧号（决定用哪一帧素材）
  final int frame;

  /// true = 镜头窗口模式（>2 章）
  final bool windowMode;

  /// 当前视口高度
  final double viewportHeight;

  /// 帧素材整图的显示区域。**对所有帧完全相同**——序列自己表达生长，
  /// 代码一律照原样画，所以换帧时植株不会整体上下跳。
  final Rect imageRect;

  /// 土堆冒头处（画布坐标）：枝丫的下界，低于它就长进土里了
  double get soilCrestY =>
      imageRect.top + _stalks[frame]!.botY * imageRect.height;

  /// 植株最高点（画布坐标）：生长擦除扫到这儿就结束，再往上素材里只有米白底
  double get plantTopY =>
      imageRect.top + _stalks[frame]!.topY * imageRect.height;

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
  int? visualFrameOverride,
}) {
  final n = outline.length;
  final totalNodes = totalTreeNodes(outline);
  final age = treeAge(totalNodes);
  final frame = visualFrameOverride ?? treeFrameFor(totalNodes);

  return n == 1
      ? _layoutSingleChapter(
          size,
          outline.single,
          frame,
          age,
          sectionScrolls,
          sectionNoteCounts,
        )
      : n > 2
      ? _layoutWindow(
          size,
          outline,
          frame,
          age,
          chapterOffset,
          sectionScrolls,
          sectionNoteCounts,
        )
      : _layoutWholeTree(
          size,
          outline,
          frame,
          age,
          sectionScrolls,
          sectionNoteCounts,
        );
}

/// 单章：整棵树仍随小节数量成长，但小节始终只在右侧一列中向下生长。
/// 超出可见容量时默认滚到最新小节，用户可在右半屏下拉回看更早小节。
MagicTreeLayout _layoutSingleChapter(
  Size size,
  OutlineChapter outline,
  int frame,
  double age,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final imageRect = _frameRect(size, frame);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

  final stalk = _stalks[frame]!;
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

  final attachTop = topY + span * 0.14;
  final attachBot = botY - span * 0.10;
  // 枝丫下界：离树干底留 12%，且**绝不低于土堆冒头处**——分界线在土堆内部，
  // 只按树干底算会把枝根放进土里（用户截图里"第一章"的卷须贴在土堆边上）
  // botY 就是这一帧土堆的冒头处，离它留 12% 即可，枝丫不会长进土里
  final soilSafeBottom = botY - span * 0.12;
  final rootY = attachTop + (attachBot - attachTop) * 0.15;
  final chapter = outline.chapter;
  final root = Offset(cx - halfWAt(rootY) + dispW * 0.006, rootY);

  var len = math.min(root.dx - 10, size.width * 0.28);
  len = math.min(len, size.shortestSide * 0.25);
  len = math.max(len, 48.0);
  final h = len * kTendrilAspect;
  final spriteRect = Rect.fromLTWH(
    root.dx - len,
    root.dy - h * kTendrilRootYFrac,
    len,
    h,
  );
  final chapters = [
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
  ];

  final bandTop = 0.0;
  final bandBottom = size.height;
  final contentTop = math.max(rootY + kSectionRowHeight * 0.5, topY);
  final labelBottom = math.min(
    math.min(size.height - _kQuickCaptureBottomGuard, botY),
    attachBot,
  );
  final availH = math.max(0.0, labelBottom - contentTop);

  final rawTops = <double>[];
  var raw = 0.0;
  for (final section in outline.sections) {
    rawTops.add(raw);
    final notes = math.min(
      sectionNoteCounts[section.id] ?? 0,
      kMaxSectionNotes,
    );
    raw += kSectionRowHeight + notes * kNoteRowHeight;
  }

  final overflow = math.max(0.0, raw - availH);
  final scroll = (sectionScrolls[chapter.id] ?? overflow).clamp(0.0, overflow);
  final fixedTipX = math.min(size.width - 96, cx + dispW * 0.19);
  final sections = <VineBranch>[];

  for (var j = 0; j < outline.sections.length; j++) {
    final section = outline.sections[j];
    final sy = contentTop + rawTops[j] + kSectionRowHeight / 2 - scroll;
    if (sy < contentTop - kSectionRowHeight || sy > labelBottom) {
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
        id: section.id,
        title: section.title,
        isChapter: false,
        root: sRoot,
        spriteRect: sRect,
        tip: Offset(fixedTipX, sRect.top + sh * kTendrilTipYFrac),
        showTendril: sRect.bottom <= soilSafeBottom,
        clipChapterId: chapter.id,
      ),
    );
  }

  return MagicTreeLayout(
    age: age,
    frame: frame,
    windowMode: true,
    viewportHeight: size.height,
    imageRect: imageRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: {chapter.id: (bandTop, bandBottom)},
    maxChapterOffset: 0,
    sectionScrollMax: {chapter.id: overflow},
  );
}

/// ≤2 章：整树可见，章枝直接锚在照片茎干上（第一章靠上）
MagicTreeLayout _layoutWholeTree(
  Size size,
  List<OutlineChapter> outline,
  int frame,
  double age,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final imageRect = _frameRect(size, frame);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

  final stalk = _stalks[frame]!;
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
  // 枝丫下界：离树干底留 12%，且**绝不低于土堆冒头处**——分界线在土堆内部，
  // 只按树干底算会把枝根放进土里（用户截图里"第一章"的卷须贴在土堆边上）
  // botY 就是这一帧土堆的冒头处，离它留 12% 即可，枝丫不会长进土里
  final soilSafeBottom = botY - span * 0.12;
  final attachRange = attachBot - attachTop;

  final n = outline.length;
  final chapters = <VineBranch>[];
  final sections = <VineBranch>[];
  final bands = <int, (double, double)>{};
  final scrollMax = <int, double>{};
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

    // 节枝：向右，带内始终单列；放不下时默认滚到最新小节。
    final sectionList = outline[i].sections;
    final contentTop = math.max(
      bandTop + 12,
      math.min(rootY + kSectionRowHeight * 0.45, bandBottom - 80),
    );
    final labelBottom = math.min(
      math.min(bandBottom - 10, size.height - _kQuickCaptureBottomGuard),
      botY,
    );
    final availH = math.max(0.0, labelBottom - contentTop);
    final rawTops = <double>[];
    var raw = 0.0;
    for (final section in sectionList) {
      rawTops.add(raw);
      final notes = math.min(
        sectionNoteCounts[section.id] ?? 0,
        kMaxSectionNotes,
      );
      raw += kSectionRowHeight + notes * kNoteRowHeight;
    }
    final overflow = math.max(0.0, raw - availH);
    scrollMax[chapter.id] = overflow;
    final scroll = (sectionScrolls[chapter.id] ?? overflow).clamp(
      0.0,
      overflow,
    );
    final fixedTipX = math.min(size.width - 96, cx + dispW * 0.19);

    for (var j = 0; j < sectionList.length; j++) {
      final sy = contentTop + rawTops[j] + kSectionRowHeight / 2 - scroll;
      if (sy < contentTop - kSectionRowHeight || sy > labelBottom) {
        continue;
      }
      final sRoot = Offset(cx + halfWAt(sy) - dispW * 0.006, sy);
      var sLen = math.min(size.width - sRoot.dx - 10, size.width * 0.21);
      sLen = math.min(sLen, size.shortestSide * 0.18);
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
          tip: Offset(fixedTipX, sRect.top + sh * kTendrilTipYFrac),
          showTendril: sRect.bottom <= soilSafeBottom,
          clipChapterId: chapter.id,
        ),
      );
    }
  }

  return MagicTreeLayout(
    age: age,
    frame: frame,
    windowMode: outline.isNotEmpty,
    viewportHeight: size.height,
    imageRect: imageRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: bands,
    maxChapterOffset: 0,
    sectionScrollMax: scrollMax,
  );
}

/// >2 章：镜头窗口模式——一屏两章，树背景随章滚动平移
MagicTreeLayout _layoutWindow(
  Size size,
  List<OutlineChapter> outline,
  int frame,
  double age,
  double chapterOffset,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final n = outline.length;
  final maxOffset = (n - 2).toDouble();
  final offset = chapterOffset.clamp(0.0, maxOffset);

  // 方案 B 止血：画幅由 _baseFrameHeight 按画布尺寸算死，**与章数无关**，
  // 不再按章数拉伸或切片平铺；树背景也不再平移（三种布局共用同一基准）。
  final imageRect = _frameRect(size, frame);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

  final stalk = _stalks[frame]!;
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

  final trunkSpan = stalkBotY - stalkTopY;
  final branchTop = math.max(trunkRect.top, stalkTopY + trunkSpan * 0.06);
  // trunkRect.bottom 即这一帧土堆的冒头处，离它留 12%
  final soilSafeBottom = trunkRect.bottom - trunkRect.height * 0.12;
  final branchBottom = math.min(soilSafeBottom, stalkBotY - trunkSpan * 0.06);

  // 高度带：一屏恰好两章，且**跟着树干走**而不是按整屏切。
  // 帧序列在节点少时树干很短（6 个节点只占画幅 25%），按整屏切会让章带远高于
  // 树干，枝根被钳到树干外、小节全部落到画外。跟着树干走则一切随树一起长大。
  final topPad = math.max(6.0, trunkRect.top);
  final bandH = math.max(kSectionRowHeight, trunkRect.height / 2);

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
    final rootY = (bandTop + math.min(40.0, bandH * 0.18)).clamp(
      branchTop,
      branchBottom,
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
    // 小节区顶端：落在"章根之下"，且相对带顶留出加节空白（按带高取比例——
    // 固定 96px 在矮树干上会把整条带吃光，小节一个都放不下）。
    // 这条带顶空白（[bandTop, contentTop]）恒落在本章带内，双击即可给本章加节
    // （用户定稿：保留双击空白加节；底部对齐后加节区从"带底"移到"带顶"）。
    final contentTop = math.max(
      math.max(
        bandTop + math.min(kSectionAddZone, bandH * 0.35),
        rootY + kSectionRowHeight * 0.5,
      ),
      branchTop,
    );
    final labelBottom = math.min(
      bandBottom - 12,
      size.height - _kQuickCaptureBottomGuard,
    );
    final availH = math.max(0.0, labelBottom - contentTop);

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
    final overflow = math.max(0.0, raw - availH);
    scrollMax[chapter.id] = overflow;
    // 默认自动滚到末尾：小节从上往下生长，放不下时隐藏最早的小节。
    final scroll = (sectionScrolls[chapter.id] ?? overflow).clamp(
      0.0,
      overflow,
    );

    for (var j = 0; j < m; j++) {
      // 自上而下：第一节在上，后续小节向下生长；scroll 增大表示向下看更新的小节。
      final sy = contentTop + rawTops[j] + kSectionRowHeight / 2 - scroll;
      if (sy < branchTop ||
          sy < contentTop - kSectionRowHeight ||
          sy > labelBottom) {
        continue;
      }
      final showTendril = sy <= branchBottom;
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
          showTendril: showTendril,
          clipChapterId: chapter.id,
        ),
      );
    }
  }

  return MagicTreeLayout(
    age: age,
    frame: frame,
    windowMode: true,
    viewportHeight: size.height,
    imageRect: imageRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: bands,
    maxChapterOffset: maxOffset,
    sectionScrollMax: scrollMax,
  );
}
