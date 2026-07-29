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

/// 素材米白底色（三张魔树图角像素实测），页面底色与之一致使整图无缝
const kParchment = Color(0xFFFDF6EC);

/// 素材原始尺寸（三张魔树图同尺寸）
const kStageImageWidth = 941.0;
const kStageImageHeight = 1672.0;

/// 土堆最高点（冒头处）在素材图中的纵向位置——第 1 档实测最顶端土色像素。
/// 枝丫不得低于这条线，否则会长进土里。
const kSoilCrestFrac = 0.807;

/// 树层 / 固定土层的**分界线**：此线以上画长高后的树，以下画原尺寸土堆。
///
/// 不能取土堆冒头处（0.807）：那一行土堆只有 63px 宽，而幼藤树干 150px、
/// 巨藤 292px，树干的平切口会整条露在土堆之上，整株看着浮在泥土上面
/// （用户 2026-07-29 截图实证）。取 0.845——实测该行土堆宽 0.403，
/// 宽过所有档最粗的树干（最宽 0.310），切口一定被土盖住。
const kSoilSplitFrac = 0.845;

/// 第 1 档土堆底边在素材图中的位置（土层贴屏底用）
const kSoilBottomFrac = 0.974;

/// **五档共用第 1 档的土堆**。五张照片的土堆其实各不相同（实测底边
/// 0.974/0.943/0.980/0.989/0.980，宽度 0.871/0.717/0.747/0.677/0.743），
/// 各画各的会在换档时让泥土当场变形跳动。第 1 档土堆最宽，盖得住所有档的树干。
const kSoilAsset = 'assets/textures/magic_tree_1.jpg';

/// 每档"整株最高点"在素材图中的位置（实测非背景像素的首行）。
///
/// 连续成长必须按**整株**（含枝叶）对齐，不能按茎干：两者在各档照片里差得远
/// （第 2 档叶顶 0.142 而茎顶 0.24，第 3 档叶顶 0.030 而茎顶 0.10）。
/// 早先按茎干对齐，结果换档时整株会缩 6~8%（实拍第 3→4 档实测 −7.2%）。
const _stageContentTop = <int, double>{
  1: 0.455,
  2: 0.142,
  3: 0.030,
  4: 0.025,
  5: 0.016,
};

/// 该档整株可见高度占图高的比例（土堆顶 → 整株最高点）
double _stageVisibleFrac(int stage) =>
    kSoilSplitFrac - _stageContentTop[stage]!;

/// 第 3 档之后素材本身几乎不再变高（整株 0.777/0.782/0.791，差不到 2%），
/// 只靠换图会让第 4 章往后每章只长 0.2%，等于又不长了。所以第 3 档起
/// 目标高度改为**继续按曲线上探**，最多把素材纵向拉到 [_kLateGrowMax]。
/// 真正要更大的成长量得靠更高的新素材，这里只是把现有素材榨到不失真的上限。
const _kLateGrowMax = 1.28;

/// 后期成长的饱和常数：q(n) = 1 − exp(−(n − 4) / _kLateGrowTau)
const _kLateGrowTau = 9.0;

/// 全生命周期最高的整株高度——用来反推基准尺寸，
/// 保证树长到最高时树冠仍留在画内（实拍里树冠被画布顶切掉就是缺了这一步）。
const _maxVisibleFrac = (kSoilSplitFrac - 0.030) * _kLateGrowMax;

/// 画布上下留白
const _kFramePadTop = 12.0;
const _kFramePadBottom = 8.0;

/// 基准画幅高度：**与章节数无关**，只由画布尺寸决定（止血红线：绝不按章数拉伸）。
///
/// 由两条约束反推：土堆底贴屏底、整株长到最高时树冠不出画；再受画布宽度封顶。
double _baseFrameHeight(Size size) => math.min(
  (size.height - _kFramePadTop - _kFramePadBottom) /
      (_maxVisibleFrac + (kSoilBottomFrac - kSoilSplitFrac)),
  size.width * (kStageImageHeight / kStageImageWidth),
);

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

/// 成长阶段 1..5（方案 A，2026-07-20 定稿）：每档一张完整树照片
/// （魔树1~5：破土嫩芽 → 幼藤 → 缠绕藤 → 参天藤 → 巨藤），加章跨档时
/// 整图淡换成更大的完整树——零拼接、零变形，真正"章多树长大"。
/// 阈值按创作量（章+节）铺开，使前十来章就能看到多次成长跨档。
int stageForNodes(int totalNodes) {
  if (totalNodes <= 0) return 1;
  if (totalNodes <= 3) return 2;
  if (totalNodes <= 7) return 3;
  if (totalNodes <= 13) return 4;
  return 5;
}

/// 各档覆盖的节点数区间（与 [stageForNodes] 一一对应）
const _stageSpans = <int, (int, int)>{
  1: (0, 0),
  2: (1, 3),
  3: (4, 7),
  4: (8, 13),
  5: (14, 14), // 末档没有"下一张更大的图"，恒定不再长
};

/// 章+节总数（树的"体量"，成长与档位都看它）
int totalTreeNodes(List<OutlineChapter> outline) =>
    outline.length + outline.fold<int>(0, (sum, c) => sum + c.sections.length);

/// 整株可见高度占画幅的比例，随节点数**连续**变化（方案乙，2026-07-28 用户定稿：
/// 泥土钉死不动，只有树连续长高）。
///
/// 档内从本档素材的整株高度线性长到下一档素材的整株高度，所以跨档换图那一刻
/// 两棵树**一样高**，换图动效才能读作生长而不是换幻灯片。
/// 唯一保留的跳变是 0 章 → 第 1 章（0.352→0.665），那是破土时刻，交给补间演。
double treeHeightFrac(int totalNodes) {
  final stage = stageForNodes(totalNodes);
  final here = _stageVisibleFrac(stage);
  // 第 3 档起（4 节点以上）素材高度已到顶，改走饱和曲线继续上探。
  // n=4 时正好等于第 3 档的自然高度，与第 2 档档尾无缝接上。
  if (stage >= 3) {
    final q = 1 - math.exp(-(totalNodes - 4) / _kLateGrowTau);
    return _stageVisibleFrac(3) * (1 + (_kLateGrowMax - 1) * q);
  }
  final (lo, hi) = _stageSpans[stage]!;
  if (hi <= lo) return here;
  final p = ((totalNodes - lo) / (hi - lo)).clamp(0.0, 1.0);
  return here + (_stageVisibleFrac(stage + 1) - here) * p;
}

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
  const WholeTreeImagePieces({
    required super.bounds,
    required this.asset,
    required this.soilBounds,
    required this.soilLineY,
  });

  final String asset;

  /// 固定土层的绘制区域（**不随成长缩放**的基准矩形）
  final Rect soilBounds;

  /// 分界线：此线以上画 [bounds]（放大后的树），以下画 [soilBounds]（原尺寸土堆）
  final double soilLineY;
}

TreeImagePieces layoutMagicTreeImagePieces(MagicTreeLayout layout) =>
    WholeTreeImagePieces(
      bounds: layout.imageRect,
      asset: 'assets/textures/magic_tree_${layout.stage}.jpg',
      soilBounds: layout.soilRect,
      soilLineY: layout.soilLineY,
    );

/// 换档时"这一波生长"扫到哪儿了：0=还在土里，1=已扫过树冠。
/// 用擦除而非交叉淡入淡出——两张不同照片对叠必出半透明双影，读作 PPT 翻页
/// （用户 2026-07-29 反馈"像 PPT 一样"）。擦除没有半透明，读作生长沿藤上行。
const kGrowWipeDuration = Duration(milliseconds: 1100);

/// 擦除线的软边高度（画布像素）：硬切会看出一条横线
const kGrowWipeFeather = 26.0;

/// 同档内加章/加节时树高补间的时长（跨档不补间，见 outline_page）
const kTreeGrowTween = Duration(milliseconds: 700);

/// 每阶段茎干轮廓（归一化到素材图：y 相对图高，半宽相对图宽）
class _Stalk {
  const _Stalk(this.topY, this.botY, this.topHalfW, this.botHalfW);

  final double topY;
  final double botY;
  final double topHalfW;
  final double botHalfW;
}

const _stalks = <int, _Stalk>{
  1: _Stalk(0.46, 0.83, 0.018, 0.028), // 破土嫩芽（细茎，占下半幅）
  2: _Stalk(0.24, 0.86, 0.035, 0.080), // 幼藤
  3: _Stalk(0.10, 0.87, 0.045, 0.110), // 缠绕藤
  4: _Stalk(0.045, 0.89, 0.052, 0.140), // 参天藤
  5: _Stalk(0.03, 0.90, 0.058, 0.155), // 巨藤（几乎撑满全幅）
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
    required this.stage,
    required this.windowMode,
    required this.viewportHeight,
    required this.imageRect,
    required this.soilRect,
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

  /// 当前视口高度；固定土壤层需要脱离虚拟树高来对齐屏幕底部。
  final double viewportHeight;

  /// 阶段素材整图的显示区域（窗口模式下高于画布，随章滚动上下平移）；
  /// 随成长以土壤线为锚点放大，所以枝条/标签坐标自动跟着树长
  final Rect imageRect;

  /// 同一张素材在**成长倍数=1** 时的矩形——固定土层照此画，泥土永不动
  final Rect soilRect;

  /// 树层与土层的分界线（画布坐标），恒等于两个矩形的 [kSoilSplitFrac] 处
  double get soilLineY => soilRect.top + kSoilSplitFrac * soilRect.height;

  /// 土堆底边（画布坐标）。土层矩形是整张素材的画幅，底边在它的
  /// [kSoilBottomFrac] 处；这条线才是"泥土贴屏底"的判据。
  double get soilBottomY => soilRect.top + kSoilBottomFrac * soilRect.height;

  /// 土堆冒头处（画布坐标）：枝丫的下界，低于它就长进土里了
  double get soilCrestY => soilRect.top + kSoilCrestFrac * soilRect.height;

  /// **整株**（含枝叶）当前的可见高度：土堆顶 → 树冠。
  /// 连续成长按这个量对齐——不是茎干，因为眼睛看的是整株。
  double get visibleTreeHeight => imageRect.height * _stageVisibleFrac(stage);

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
  double? visualHeightFrac,
}) {
  final n = outline.length;
  final totalNodes = totalTreeNodes(outline);
  final age = treeAge(totalNodes);
  final stage = stageForNodes(totalNodes);
  // 成长倍数 = 目标树高 ÷ 当前这张素材自带的树高。
  // 跨档时高度瞬间就位（页面不补间），所以这个倍数在换档前后都贴合各自素材，
  // 旧照片绝不会被抻长、新照片也不会被压扁——过渡全交给擦除。
  final growth =
      (visualHeightFrac ?? treeHeightFrac(totalNodes)) /
      _stageVisibleFrac(stage);

  return n == 1
      ? _layoutSingleChapter(
          size,
          outline.single,
          stage,
          age,
          growth,
          sectionScrolls,
          sectionNoteCounts,
        )
      : n > 2
      ? _layoutWindow(
          size,
          outline,
          stage,
          age,
          growth,
          chapterOffset,
          sectionScrolls,
          sectionNoteCounts,
        )
      : _layoutWholeTree(
          size,
          outline,
          stage,
          age,
          growth,
          sectionScrolls,
          sectionNoteCounts,
        );
}

/// 整树模式共用的画幅几何：**土壤线钉死**，树以它为锚点按 [growth] **只长高**。
///
/// 横向恒定不放大——这不是偷懒，是接缝所迫：土层永远是原尺寸，
/// 若树层等比放大，树干在分界线上宽下窄会露出台阶（实测 1.24 倍时肉眼可见，
/// 加渐变融合也只能糊成一团雾）。只拉高则分界线两侧宽度天然一致，接缝为零。
///
/// 返回 (树层矩形, 土层基准矩形)。growth=1 时两者相等，且与改造前完全一致。
(Rect, Rect) _stageRects({required Size size, required double growth}) {
  final baseH = _baseFrameHeight(size);
  final baseW = baseH * (kStageImageWidth / kStageImageHeight);
  // 土堆底贴屏底（第 1 档土堆是唯一的土层，所以按它的底边定位）
  final baseTop = size.height - _kFramePadBottom - kSoilBottomFrac * baseH;
  final left = (size.width - baseW) / 2;
  final soil = Rect.fromLTWH(left, baseTop, baseW, baseH);
  final soilLineY = baseTop + kSoilSplitFrac * baseH;
  final h = baseH * growth;
  final tree = Rect.fromLTWH(left, soilLineY - kSoilSplitFrac * h, baseW, h);
  return (tree, soil);
}

/// 单章：整棵树仍随小节数量成长，但小节始终只在右侧一列中向下生长。
/// 超出可见容量时默认滚到最新小节，用户可在右半屏下拉回看更早小节。
MagicTreeLayout _layoutSingleChapter(
  Size size,
  OutlineChapter outline,
  int stage,
  double age,
  double growth,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final (imageRect, soilRect) = _stageRects(size: size, growth: growth);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

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

  final attachTop = topY + span * 0.14;
  final attachBot = botY - span * 0.10;
  // 枝丫下界：离树干底留 12%，且**绝不低于土堆冒头处**——分界线在土堆内部，
  // 只按树干底算会把枝根放进土里（用户截图里"第一章"的卷须贴在土堆边上）
  final soilSafeBottom = math.min(
    botY - span * 0.12,
    soilRect.top + kSoilCrestFrac * soilRect.height - 10,
  );
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
    stage: stage,
    windowMode: true,
    viewportHeight: size.height,
    imageRect: imageRect,
    soilRect: soilRect,
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
  int stage,
  double age,
  double growth,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final (imageRect, soilRect) = _stageRects(size: size, growth: growth);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

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
  // 枝丫下界：离树干底留 12%，且**绝不低于土堆冒头处**——分界线在土堆内部，
  // 只按树干底算会把枝根放进土里（用户截图里"第一章"的卷须贴在土堆边上）
  final soilSafeBottom = math.min(
    botY - span * 0.12,
    soilRect.top + kSoilCrestFrac * soilRect.height - 10,
  );
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
    stage: stage,
    windowMode: outline.isNotEmpty,
    viewportHeight: size.height,
    imageRect: imageRect,
    soilRect: soilRect,
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
  int stage,
  double age,
  double growth,
  double chapterOffset,
  Map<int, double> sectionScrolls,
  Map<int, int> sectionNoteCounts,
) {
  final n = outline.length;
  final maxOffset = (n - 2).toDouble();
  final offset = chapterOffset.clamp(0.0, maxOffset);

  // 方案 B 止血：画幅由 _baseFrameHeight 按画布尺寸算死，**与章数无关**，
  // 不再按章数拉伸或切片平铺；树背景也不再平移（三种布局共用同一基准）。
  final (imageRect, soilRect) = _stageRects(size: size, growth: growth);
  final dispW = imageRect.width;
  final dispH = imageRect.height;

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

  final trunkSpan = stalkBotY - stalkTopY;
  final branchTop = math.max(trunkRect.top, stalkTopY + trunkSpan * 0.06);
  // 同上：枝丫不得低于土堆冒头处
  final soilSafeBottom = math.min(
    trunkRect.bottom - trunkRect.height * 0.12,
    soilRect.top + kSoilCrestFrac * soilRect.height - 10,
  );
  final branchBottom = math.min(soilSafeBottom, stalkBotY - trunkSpan * 0.06);

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
    final rootY = (bandTop + 40).clamp(branchTop, branchBottom);
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
    // 小节区顶端：落在"章根之下"，且相对带顶至少留 kSectionAddZone 的空白。
    // 这条带顶空白（[bandTop, contentTop]）恒落在本章带内，双击即可给本章加节
    // （用户定稿：保留双击空白加节；底部对齐后加节区从"带底"移到"带顶"）。
    final contentTop = math.max(
      math.max(bandTop + kSectionAddZone, rootY + kSectionRowHeight * 0.5),
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
    stage: stage,
    windowMode: true,
    viewportHeight: size.height,
    imageRect: imageRect,
    soilRect: soilRect,
    trunkRect: trunkRect,
    chapters: chapters,
    sections: sections,
    chapterBands: bands,
    maxChapterOffset: maxOffset,
    sectionScrollMax: scrollMax,
  );
}
