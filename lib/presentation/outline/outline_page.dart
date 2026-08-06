import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content_font.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import '../section/section_page.dart';
import '../shared/soft_toast.dart';
import 'label_layout.dart';
import 'magic_carpet.dart';
import 'magic_tree_model.dart';

/// 某小说的大纲流（章+节），魔树数据源
final outlineProvider = StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

/// 某小说下"已挂靠小节的灵感"，按 section_id 分组（新的在前）。
/// 大纲页在每个小节标签下显示最新几条。
final sectionInspirationsProvider =
    StreamProvider.family<Map<int, List<Inspiration>>, int>(
      (ref, novelId) =>
          ref.watch(novelRepositoryProvider).watchSectionInspirations(novelId),
    );

/// 某小说下"直接挂靠到章的灵感"，按 chapter_id 分组（新的在前）。
final chapterInspirationsProvider =
    StreamProvider.family<Map<int, List<Inspiration>>, int>(
      (ref, novelId) =>
          ref.watch(novelRepositoryProvider).watchChapterInspirations(novelId),
    );

/// 小节标签下最多显示的灵感条数（数量太多只显示最新三条）
const _maxSectionNotes = 3;

/// 墨色（配米白羊皮纸底）
const _ink = Color(0xFF3A2A18);

/// 大纲页｜魔树（2026-07-03 镜头窗口改版）
///
/// - 整树 = 用户魔树摄影素材；章/节枝 = 素材裁出的真实卷须，弹性生长
/// - 章序沿树自上而下（第一章树顶方向）；>2 章进入镜头窗口：一屏两章，
///   **左半屏上下滑动滚章节（树背景跟随平移）**，
///   **右半屏上下滑动滚当前章的小节（树背景不动）**，松手对齐整章
/// - 点左空白长章枝、点右空白给对应高度的章长节枝；
///   长按枝端标签重命名/剪掉；双击节进小节页；弹层全部 Cupertino 质感
class OutlinePage extends ConsumerStatefulWidget {
  const OutlinePage({super.key, required this.novelId, required this.title});

  final int novelId;
  final String title;

  @override
  ConsumerState<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends ConsumerState<OutlinePage>
    with TickerProviderStateMixin {
  /// 枝丫生长动画（新建章/节时从根部弹性展开）
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// 章镜头位置（0=首章树顶，max=末章土壤；连续值，松手对齐整数）
  late final AnimationController _camera = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 各章小节列表滚动量
  final Map<int, double> _sectionScrolls = {};

  /// 右半空白双击落点 y（onDoubleTapDown 记录 → onDoubleTap 用）
  double _rightDoubleTapY = 0;

  /// 本帧放置好的标签（磁吸落点计算用）
  List<PlacedLabel> _labels = const [];

  /// 当前被磁吸高亮的目标标签（拖拽灵感时最近的章/节）
  PlacedLabel? _magnetLabel;

  /// 树画布的 key（把拖拽全局坐标换算到画布本地坐标）
  final _treeKey = GlobalKey();

  /// 正在生长的枝（章/节分开记，避免章节撞 id）
  ({bool isChapter, int id})? _growing;

  /// 树干生长期间枝丫层沿用旧大纲，避免新节点一入库就带着旧枝/标签抢先重排。
  List<OutlineChapter>? _branchOutlineOverride;

  /// 正在等待进入页面的新树节点数。树干换帧必须等新大纲进入 build，
  /// 再等魔树图层报告目标帧已经 settle，不能用固定 Timer 猜。
  int? _trunkAwaitTargetNodes;
  int? _trunkAwaitTargetFrame;
  int _settledTreeFrame = treeFrameFor(0);
  Completer<void>? _trunkOutlineReady;
  Completer<void>? _trunkFrameReady;

  /// 最近一次布局（手势换算用）
  MagicTreeLayout? _layout;
  Size _bodySize = Size.zero;

  /// 上次设给魔毯的缩边栏状态（避免每帧重复设）
  bool _lastTuck = false;

  @override
  void dispose() {
    carpetTucked.value = false; // 离开大纲页恢复完整魔毯球
    final outlineReady = _trunkOutlineReady;
    if (outlineReady != null && !outlineReady.isCompleted) {
      outlineReady.complete();
    }
    final frameReady = _trunkFrameReady;
    if (frameReady != null && !frameReady.isCompleted) frameReady.complete();
    _grow.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _beginAwaitingTrunkOutline(int targetNodes) {
    _trunkAwaitTargetNodes = targetNodes;
    _trunkAwaitTargetFrame = treeFrameFor(targetNodes);
    _trunkOutlineReady = Completer<void>();
    _trunkFrameReady = Completer<void>();
  }

  void _markTrunkOutlineReady(List<OutlineChapter> outline) {
    final target = _trunkAwaitTargetNodes;
    final ready = _trunkOutlineReady;
    if (target == null || ready == null || ready.isCompleted) return;
    if (totalTreeNodes(outline) < target) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ready.isCompleted || _trunkAwaitTargetNodes != target) {
        return;
      }
      ready.complete();
      _completeTrunkFrameIfReady();
    });
  }

  void _markTreeFrameSettled(int frame) {
    _settledTreeFrame = frame;
    _completeTrunkFrameIfReady();
  }

  void _completeTrunkFrameIfReady() {
    final targetFrame = _trunkAwaitTargetFrame;
    final outlineReady = _trunkOutlineReady;
    final frameReady = _trunkFrameReady;
    if (targetFrame == null || frameReady == null || frameReady.isCompleted) {
      return;
    }
    if (outlineReady != null && !outlineReady.isCompleted) return;
    if (_settledTreeFrame < targetFrame) return;
    frameReady.complete();
  }

  /// 给新枝占位并**先藏起来**：`_growing` 一置上，该枝的卷须与标签就按
  /// `_grow.value`（此刻为 0）渲染，即完全不可见。
  void _holdGrow({required bool isChapter, required int id}) {
    _grow.value = 0;
    setState(() {
      _branchOutlineOverride = null;
      _growing = (isChapter: isChapter, id: id);
    });
  }

  Future<void> _playGrow() async {
    await _grow.forward(from: 0);
    if (mounted) setState(() => _growing = null);
  }

  /// 点左侧空白：长出章枝（仓库按新序号原子命名：引子 → 第一章 → …），镜头滑到新章
  Future<void> _addChapter(List<OutlineChapter> outline) async {
    HapticFeedback.lightImpact();
    final oldCount = outline.length;
    _beginAwaitingTrunkOutline(totalTreeNodes(outline) + 1);
    setState(() => _branchOutlineOverride = outline);
    final chapter = await ref
        .read(novelRepositoryProvider)
        .createChapter(novelId: widget.novelId);

    final motion = chapterGrowthMotionPlan(
      oldCount: oldCount,
      newCount: oldCount + 1,
      currentOffset: _camera.value,
    );

    if (!mounted) return;
    await _trunkOutlineReady?.future;
    if (!mounted) return;
    await _trunkFrameReady?.future;
    if (!mounted) return;
    _holdGrow(isChapter: true, id: chapter.id);

    for (final step in motion.steps) {
      if (!mounted) return;
      switch (step) {
        case ChapterGrowthStep.panCamera:
          await _camera.animateTo(
            motion.targetOffset,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeInOutCubic,
          );
        case ChapterGrowthStep.growBranch:
          await _playGrow();
      }
    }
  }

  /// 点右侧空白：按点击高度找对应章，长出节枝
  Future<void> _addSection(
    List<OutlineChapter> outline,
    MagicTreeLayout layout,
    double y,
  ) async {
    if (outline.isEmpty) {
      showSoftToast(context, '先点左边空白，长出第一根章枝吧');
      return;
    }
    final chapterId = layout.chapterForY(y);
    if (chapterId == null) return;
    HapticFeedback.lightImpact();
    _beginAwaitingTrunkOutline(totalTreeNodes(outline) + 1);
    setState(() => _branchOutlineOverride = outline);
    final section = await ref
        .read(novelRepositoryProvider)
        .createSection(chapterId: chapterId);
    // 新节加入后回到默认自动滚动：从第一节向下长，放不下时显示最新一段
    _sectionScrolls.remove(chapterId);
    if (!mounted) return;
    await _trunkOutlineReady?.future;
    if (!mounted) return;
    await _trunkFrameReady?.future;
    if (!mounted) return;
    _holdGrow(isChapter: false, id: section.id);
    await _playGrow();
  }

  // ── 镜头与小节滚动手势 ──────────────────────────────

  double get _bandH => (_bodySize.height - 12) / 2;

  /// 左半屏纵向拖动：滚章节（树背景跟随）
  void _onChapterDrag(DragUpdateDetails d) {
    final layout = _layout;
    if (layout == null || !layout.windowMode) return;
    _camera.stop();
    _camera.value = (_camera.value - d.delta.dy / _bandH).clamp(
      0.0,
      layout.maxChapterOffset,
    );
  }

  /// 松手：按甩动速度惯性投射若干章，再对齐到整章
  void _onChapterDragEnd(DragEndDetails d) {
    final layout = _layout;
    if (layout == null || !layout.windowMode) return;
    final v = d.velocity.pixelsPerSecond.dy;
    final projected = _camera.value - v * 0.35 / _bandH;
    final target = projected.roundToDouble().clamp(
      0.0,
      layout.maxChapterOffset,
    );
    final distance = (target - _camera.value).abs();
    _camera.animateTo(
      target,
      duration: Duration(
        milliseconds: (200 + 90 * distance).clamp(200, 550).round(),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  /// 右半屏纵向拖动：滚起点所在章的小节（树背景不动）
  int? _sectionDragChapter;

  void _onSectionDragStart(DragStartDetails d) {
    _sectionDragChapter = _layout?.chapterForY(d.localPosition.dy);
  }

  void _onSectionDrag(DragUpdateDetails d) {
    final layout = _layout;
    final ch = _sectionDragChapter;
    if (layout == null || !layout.windowMode || ch == null) return;
    final max = layout.sectionScrollMax[ch] ?? 0;
    if (max <= 0) return;
    setState(() {
      // 自上而下：默认在末尾；下拉（delta.dy>0）回看更早的小节
      final current = _sectionScrolls[ch] ?? max;
      _sectionScrolls[ch] = (current - d.delta.dy).clamp(0.0, max);
    });
  }

  // ── Cupertino 弹层 ──────────────────────────────

  /// Cupertino 弹层文字统一用楷体
  TextStyle _dlgStyle({double size = 17, FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: 'LXGWWenKai',
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  /// 重命名弹窗（章/节共用，iOS 质感）
  Future<void> _rename(PlacedLabel label) async {
    final controller = TextEditingController(text: label.text);
    final newTitle = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          label.chapterId != null ? '重命名这一章' : '重命名这一节',
          style: _dlgStyle(weight: FontWeight.w600),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            key: const Key('重命名输入框'),
            controller: controller,
            autofocus: true,
            style: _dlgStyle(size: 15, color: _ink),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('重命名确认按钮'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('保存', style: _dlgStyle(weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == label.text) return;
    final repo = ref.read(novelRepositoryProvider);
    if (label.chapterId != null) {
      await repo.renameChapter(label.chapterId!, title);
    } else {
      await repo.renameSection(label.sectionId!, title);
    }
  }

  /// 删除（带确认；删章级联删节、灵感放回魔毯）
  Future<void> _delete(PlacedLabel label) async {
    final isChapter = label.chapterId != null;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          '剪掉「${label.text}」？',
          style: _dlgStyle(weight: FontWeight.w600),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            isChapter
                ? '这一章和它的所有小节都会被剪掉；挂在上面的灵感会放回灵感卷轴。'
                : '这一节会被剪掉；挂在上面的灵感会放回灵感卷轴。',
            style: _dlgStyle(size: 13),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('删除确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '剪掉',
              style: _dlgStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final repo = ref.read(novelRepositoryProvider);
    if (isChapter) {
      await repo.deleteChapter(label.chapterId!);
    } else {
      await repo.deleteSection(label.sectionId!);
    }
  }

  /// 长按枝端标签：iOS 动作面板（重命名 / 剪掉）
  Future<void> _showBranchMenu(PlacedLabel label) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(label.text, style: _dlgStyle(size: 14)),
        actions: [
          CupertinoActionSheetAction(
            key: const Key('菜单重命名'),
            onPressed: () => Navigator.of(context).pop('rename'),
            child: Text(
              label.chapterId != null ? '重命名这一章' : '重命名这一节',
              style: _dlgStyle(),
            ),
          ),
          CupertinoActionSheetAction(
            key: const Key('菜单删除'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('delete'),
            child: Text(
              '剪掉这根枝丫',
              style: _dlgStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: _dlgStyle(weight: FontWeight.w600)),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(label);
    if (action == 'delete') await _delete(label);
  }

  /// 单击节标签 → 直接进小节页（用户定稿：单击即进）
  Future<void> _openSection(PlacedLabel label) async {
    if (label.sectionId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SectionPage(sectionId: label.sectionId!, initialTitle: label.text),
      ),
    );
  }

  /// 双击：章 → 重命名（节的进入改为单击，见 _openSection）
  Future<void> _onDoubleTap(PlacedLabel label) async {
    if (label.sectionId != null) {
      await _openSection(label);
    } else {
      await _rename(label);
    }
  }

  /// 极简自绘头部（替代 Material AppBar）。
  /// 标题用 Stack 相对**整屏**居中（Row+Expanded 会因左箭头/右留白
  /// 不对称而偏移，用户反馈"名字要左右居中"）；两侧对称避让魔毯球。
  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 104),
              child: Text(
                widget.title,
                key: const Key('大纲页书名'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(CupertinoIcons.back, color: _ink, size: 26),
            ),
          ),
        ),
      ],
    ),
  );

  /// 生长中枝的当前比例（未在生长的枝恒为 1）
  double _growthFor({required bool isChapter, required int id}) {
    final g = _growing;
    if (g == null || g.isChapter != isChapter || g.id != id) return 1;
    return Curves.easeOutCubic.transform(_grow.value);
  }

  /// 标签透明度：生长后段（60% 起）才浮现
  double _labelOpacity(PlacedLabel label) {
    final g = _growing;
    if (g == null) return 1;
    final matches = g.isChapter
        ? label.chapterId == g.id
        : label.sectionId == g.id;
    if (!matches) return 1;
    return ((_grow.value - 0.6) / 0.4).clamp(0.0, 1.0);
  }

  /// 卷须根部树皮压痕：先画它再画卷须，让枝根像被树干咬住。
  Widget _branchSocket(VineBranch b, Offset shift) {
    if (_growthFor(isChapter: b.isChapter, id: b.id) <= 0.02) {
      return const SizedBox.shrink();
    }
    final center = b.root - shift;
    final size = b.isChapter ? 30.0 : 24.0;
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: center,
        width: size,
        height: size * 0.72,
      ),
      child: CustomPaint(painter: _BranchSocketPainter(isChapter: b.isChapter)),
    );
  }

  /// 一根卷须精灵（shift：在裁剪层内渲染时的坐标平移）
  Widget _tendril(VineBranch b, Offset shift) {
    final fullRect = b.spriteRect.shift(-shift);
    final growth = _growthFor(isChapter: b.isChapter, id: b.id).clamp(0.0, 1.0);
    final align = b.isChapter ? Alignment.centerRight : Alignment.centerLeft;
    final visibleWidth = fullRect.width * growth;
    final visibleLeft = b.isChapter
        ? fullRect.right - visibleWidth
        : fullRect.left;

    return Positioned.fromRect(
      rect: Rect.fromLTWH(
        visibleLeft,
        fullRect.top,
        visibleWidth,
        fullRect.height,
      ),
      child: Opacity(
        opacity: growth <= 0.02 ? 0 : (0.25 + growth * 0.75).clamp(0.0, 1.0),
        child: ClipRect(
          child: OverflowBox(
            alignment: align,
            minWidth: fullRect.width,
            maxWidth: fullRect.width,
            minHeight: fullRect.height,
            maxHeight: fullRect.height,
            child: Align(
              alignment: align,
              widthFactor: growth,
              child: SizedBox(
                width: fullRect.width,
                height: fullRect.height,
                child: Image.asset(
                  b.isChapter
                      ? 'assets/textures/tendril_chapter.png'
                      : 'assets/textures/tendril_section.png',
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 该标签是否正被磁吸高亮
  bool _isMagnet(PlacedLabel label) {
    final m = _magnetLabel;
    return m != null &&
        m.chapterId == label.chapterId &&
        m.sectionId == label.sectionId;
  }

  /// 拖拽全局坐标 → 最近的标签（磁吸目标）
  PlacedLabel? _nearestLabel(Offset global) {
    final box = _treeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _labels.isEmpty) return null;
    final local = box.globalToLocal(global);
    PlacedLabel? best;
    var bestD = double.infinity;
    for (final l in _labels) {
      final d = (l.rect.center - local).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }

  /// 拖拽移动：磁吸到最近章/节并高亮
  void _onMagnetMove(Offset global) {
    final nearest = _nearestLabel(global);
    if (nearest == null) return;
    if (!_isMagnet(nearest)) {
      HapticFeedback.selectionClick(); // 吸附到新目标时轻震
      setState(() => _magnetLabel = nearest);
    }
  }

  void _clearMagnet() {
    if (_magnetLabel != null) setState(() => _magnetLabel = null);
  }

  /// 松手：挂靠到磁吸中的目标
  Future<void> _onMagnetDrop(
    Inspiration inspiration,
    List<OutlineChapter> outline,
  ) async {
    final target = _magnetLabel;
    _clearMagnet();
    if (target == null) return;
    await _dropInspiration(inspiration, target, outline);
  }

  /// 小节标签下方的灵感小卡（最多 3 条最新，每条单行省略）
  Widget _sectionNotes(
    PlacedLabel label,
    List<Inspiration> notes,
    Offset shift,
    double canvasWidth,
  ) {
    final shown = notes.take(_maxSectionNotes).toList();
    // 卡宽钳制在到右缘的可用空间内（防止冲出屏幕右侧）
    final maxW = (canvasWidth - label.rect.left - 6).clamp(60.0, 168.0);
    return Positioned(
      left: label.rect.left - shift.dx,
      top: label.rect.bottom + 2 - shift.dy,
      child: Opacity(
        opacity: _labelOpacity(label),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 长按拖起：可把这条灵感移到别的小节/章（挂靠点仍是整树磁吸 DragTarget）。
            // 用户定稿：章下灵感可拖到该章某节；节下灵感可拖到其他节/其他章/其他章的节。
            for (final n in shown)
              LongPressDraggable<Inspiration>(
                data: n,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                onDragStarted: HapticFeedback.selectionClick,
                feedback: _noteFeedback(n),
                childWhenDragging: Opacity(
                  opacity: 0.25,
                  child: _noteChip(n, maxW),
                ),
                child: _noteChip(n, maxW),
              ),
          ],
        ),
      ),
    );
  }

  /// 小节/章标签下的一枚灵感小卡（单行省略，楷体墨字）
  Widget _noteChip(Inspiration n, double maxW) => Container(
    margin: const EdgeInsets.only(top: 3),
    constraints: BoxConstraints(maxWidth: maxW),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xCCFFFCF4),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0x22C9A050)),
    ),
    child: Text(
      n.content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // 行高留 1.3，避免楷体字底被容器裁掉（用户反馈"部分内容被遮住"）
      style: TextStyle(
        fontFamily: contentFontFamily(n.content) ?? 'LXGWWenKai',
        fontStyle: contentUsesBrandFont(n.content)
            ? FontStyle.italic
            : FontStyle.normal,
        fontSize: 11,
        height: 1.3,
        color: const Color(0xCC3A2A18),
      ),
    ),
  );

  /// 拖起灵感小卡时的浮影：金边微光羊皮纸卡
  Widget _noteFeedback(Inspiration n) => Material(
    color: Colors.transparent,
    child: Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC9A050), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x59C9A050), blurRadius: 12)],
      ),
      child: Text(
        n.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: contentFontFamily(n.content) ?? 'LXGWWenKai',
          fontStyle: contentUsesBrandFont(n.content)
              ? FontStyle.italic
              : FontStyle.normal,
          fontSize: 12,
          color: _ink,
        ),
      ),
    ),
  );

  /// 一枚枝端标签胶囊（热区：长按菜单/双击；磁吸时染金放大）
  Widget _labelCapsule(PlacedLabel label, Offset shift) {
    final magnet = _isMagnet(label);
    return Positioned.fromRect(
      rect: label.rect.inflate(13).shift(-shift),
      child: GestureDetector(
        key: Key(
          label.chapterId != null
              ? '章热区_${label.chapterId}'
              : '节热区_${label.sectionId}',
        ),
        behavior: HitTestBehavior.opaque,
        // 单击：节 → 进小节页（章单击不响应，避免误触；章重命名走双击）
        onTap: label.sectionId != null ? () => _openSection(label) : null,
        onLongPress: () => _showBranchMenu(label),
        onDoubleTap: () => _onDoubleTap(label),
        child: Opacity(
          opacity: _labelOpacity(label),
          child: Center(
            child: AnimatedScale(
              scale: magnet ? 1.16 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutBack,
              // 羊皮纸胶囊底：压在照片绿叶上也可读；磁吸时染金发光
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: magnet
                      ? const Color(0xF2E9B84C)
                      : const Color(0xE8FDF6EC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: magnet
                        ? const Color(0xFFB8860B)
                        : const Color(0x1A3A2A18),
                    width: magnet ? 1.5 : 1,
                  ),
                  boxShadow: magnet
                      ? const [
                          BoxShadow(color: Color(0x99E9B84C), blurRadius: 14),
                        ]
                      : const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                ),
                child: SizedBox(
                  width: label.rect.width,
                  child: Text(
                    label.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle(bold: label.bold, text: label.text),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outline =
        ref.watch(outlineProvider(widget.novelId)).value ??
        const <OutlineChapter>[];
    _markTrunkOutlineReady(outline);

    // 章节多（>2 = 进入窗口模式）时把魔毯球缩到右边栏，避免挡住右上角小节标签；
    // 章少时恢复完整球。只在状态变化时设，避免每帧刷。
    final wantTuck = outline.length > 2;
    if (_lastTuck != wantTuck) {
      _lastTuck = wantTuck;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => carpetTucked.value = wantTuck,
      );
    }
    // 各小节/章已挂靠的灵感（新的在前），用于在标签下显示最新几条
    final sectionInsp =
        ref.watch(sectionInspirationsProvider(widget.novelId)).value ??
        const <int, List<Inspiration>>{};
    final chapterInsp =
        ref.watch(chapterInspirationsProvider(widget.novelId)).value ??
        const <int, List<Inspiration>>{};
    final noteCounts = {
      for (final e in sectionInsp.entries) e.key: e.value.length,
    };

    return Scaffold(
      backgroundColor: kParchment,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header(context)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                _bodySize = size;

                return ClipRect(
                  // 画幅与节点数无关：生长由帧序列自己表达，代码不缩放不拉伸，
                  // 所以这里不再需要任何高度补间
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_grow, _camera]),
                    builder: (context, _) {
                      final treeLayout = layoutMagicTree(
                        size: size,
                        outline: outline,
                        chapterOffset: _camera.value,
                        sectionScrolls: _sectionScrolls,
                        sectionNoteCounts: noteCounts,
                      );
                      final branchOutline = _branchOutlineOverride ?? outline;
                      final layout = layoutMagicTree(
                        size: size,
                        outline: branchOutline,
                        chapterOffset: _camera.value,
                        sectionScrolls: _sectionScrolls,
                        sectionNoteCounts: noteCounts,
                      );
                      _layout = layout;
                      final labels = placeMagicLabels(
                        layout,
                        canvasWidth: size.width,
                        textScaler: MediaQuery.textScalerOf(context),
                      );
                      _labels = labels;
                      // 窗口模式：节按章分组，滚动时裁剪在本章高度带内
                      final secClip = {
                        for (final s in layout.sections) s.id: s.clipChapterId,
                      };
                      final clipRects = <int, Rect>{
                        if (layout.windowMode)
                          for (final e in layout.chapterBands.entries)
                            // 上边缘只留 2px（原 20px 会切掉第一节的上置标签），
                            // 与上一章带的裁剪下沿恰好错开、互不重叠
                            e.key: Rect.fromLTRB(
                              0,
                              e.value.$1 + 2,
                              size.width,
                              e.value.$2 - 2,
                            ),
                      };

                      Widget clipped(int chapterId, List<Widget> children) {
                        final rect = clipRects[chapterId]!;
                        return Positioned.fromRect(
                          rect: rect,
                          child: ClipRect(child: Stack(children: children)),
                        );
                      }

                      // 整棵树 = 一个大磁吸落点：灵感拖到附近即吸附到最近章/节，
                      // 松手挂靠（用户定稿：小标签太难精准命中，改磁吸）
                      return DragTarget<Inspiration>(
                        onWillAcceptWithDetails: (_) => outline.isNotEmpty,
                        onMove: (d) => _onMagnetMove(d.offset),
                        onLeave: (_) => _clearMagnet(),
                        onAcceptWithDetails: (d) =>
                            _onMagnetDrop(d.data, outline),
                        builder: (context, candidates, rejected) => Stack(
                          key: _treeKey,
                          children: [
                            // 魔树本体。过渡期整个不建（见 kMagicTreeArtEnabled）：
                            // 布局几何、枝丫锚点、热区照常，只是不画底图
                            if (kMagicTreeArtEnabled)
                              _MagicTreeImage(
                                layout: treeLayout,
                                onFrameSettled: _markTreeFrameSettled,
                              ),
                            // 左半空白：双击长章枝（用户定稿：改双击避免误建）；
                            // 纵向拖动滚章节（树背景跟随）
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: size.width / 2,
                              child: GestureDetector(
                                key: const Key('左空白区'),
                                behavior: HitTestBehavior.opaque,
                                onDoubleTap: () => _addChapter(outline),
                                onVerticalDragUpdate: _onChapterDrag,
                                onVerticalDragEnd: _onChapterDragEnd,
                              ),
                            ),
                            // 右半空白：双击给对应高度的章长节枝；
                            // 纵向拖动滚小节（树背景不动）
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: size.width / 2,
                              child: GestureDetector(
                                key: const Key('右空白区'),
                                behavior: HitTestBehavior.opaque,
                                onDoubleTapDown: (d) =>
                                    _rightDoubleTapY = d.localPosition.dy,
                                onDoubleTap: () => _addSection(
                                  outline,
                                  layout,
                                  _rightDoubleTapY,
                                ),
                                onVerticalDragStart: _onSectionDragStart,
                                onVerticalDragUpdate: _onSectionDrag,
                              ),
                            ),
                            // 卷须与标签（窗口模式的节裁剪在本章带内）
                            IgnorePointer(
                              child: Stack(
                                children: [
                                  for (final b in layout.chapters)
                                    _branchSocket(b, Offset.zero),
                                  for (final b in layout.sections)
                                    if (b.clipChapterId == null &&
                                        b.showTendril)
                                      _branchSocket(b, Offset.zero),
                                  for (final e in clipRects.entries)
                                    clipped(e.key, [
                                      for (final b in layout.sections)
                                        if (b.clipChapterId == e.key &&
                                            b.showTendril)
                                          _branchSocket(b, e.value.topLeft),
                                    ]),
                                  for (final b in layout.chapters)
                                    _tendril(b, Offset.zero),
                                  for (final b in layout.sections)
                                    if (b.clipChapterId == null &&
                                        b.showTendril)
                                      _tendril(b, Offset.zero),
                                  for (final e in clipRects.entries)
                                    clipped(e.key, [
                                      for (final b in layout.sections)
                                        if (b.clipChapterId == e.key &&
                                            b.showTendril)
                                          _tendril(b, e.value.topLeft),
                                    ]),
                                ],
                              ),
                            ),
                            // 章标签下直接挂靠的灵感小卡（章不裁剪，直接放）
                            for (final label in labels)
                              if (label.chapterId != null)
                                _sectionNotes(
                                  label,
                                  chapterInsp[label.chapterId] ?? const [],
                                  Offset.zero,
                                  size.width,
                                ),
                            // 小节标签下的灵感小卡（与标签同裁剪规则）
                            for (final label in labels)
                              if (label.sectionId != null &&
                                  secClip[label.sectionId] == null)
                                _sectionNotes(
                                  label,
                                  sectionInsp[label.sectionId] ?? const [],
                                  Offset.zero,
                                  size.width,
                                ),
                            for (final e in clipRects.entries)
                              clipped(e.key, [
                                for (final label in labels)
                                  if (label.sectionId != null &&
                                      secClip[label.sectionId] == e.key)
                                    _sectionNotes(
                                      label,
                                      sectionInsp[label.sectionId] ?? const [],
                                      e.value.topLeft,
                                      size.width,
                                    ),
                              ]),
                            // 标签热区：章与整树模式的节直接放；窗口模式的节按带裁剪
                            for (final label in labels)
                              if (label.chapterId != null ||
                                  secClip[label.sectionId] == null)
                                _labelCapsule(label, Offset.zero),
                            for (final e in clipRects.entries)
                              clipped(e.key, [
                                for (final label in labels)
                                  if (label.sectionId != null &&
                                      secClip[label.sectionId] == e.key)
                                    _labelCapsule(label, e.value.topLeft),
                              ]),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 拖拽落点：磁吸到小节 → 挂小节；磁吸到章 → 直接挂到该章下
  Future<void> _dropInspiration(
    Inspiration inspiration,
    PlacedLabel label,
    List<OutlineChapter> outline,
  ) async {
    final repo = ref.read(inspirationRepositoryProvider);
    if (label.sectionId != null) {
      await repo.assignToSection(inspiration.id, label.sectionId!);
    } else if (label.chapterId != null) {
      await repo.assignToChapter(inspiration.id, label.chapterId!);
    } else {
      return;
    }
    magicCarpetKey.currentState?.collapse();
  }
}

class _BranchSocketPainter extends CustomPainter {
  const _BranchSocketPainter({required this.isChapter});

  final bool isChapter;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final shadow = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0x88302310),
          Color(0x442F4A19),
          Color(0x00000000),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawOval(rect, shadow);

    final slit = Paint()
      ..color = const Color(0x8A1E2D12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(isChapter ? size.width * 0.68 : size.width * 0.32, center.dy)
      ..quadraticBezierTo(
        center.dx,
        center.dy - size.height * 0.24,
        isChapter ? size.width * 0.28 : size.width * 0.72,
        center.dy + size.height * 0.08,
      );
    canvas.drawPath(path, slit);
  }

  @override
  bool shouldRepaint(covariant _BranchSocketPainter oldDelegate) =>
      oldDelegate.isChapter != isChapter;
}

/// 魔树画面 = 生长帧序列的一帧。
///
/// 每加一个节点前进一帧，靠**自下而上的擦除**换帧：相邻帧各 50% 混合会让叶子
/// 半透明重叠（实测 f19/f20 明显鬼影），读作 PPT 翻页；擦除没有半透明，
/// 而相邻帧差异本就小，擦除线扫过几乎看不出来，读作一波生长沿藤上行。
class _MagicTreeImage extends StatefulWidget {
  const _MagicTreeImage({required this.layout, required this.onFrameSettled});

  final MagicTreeLayout layout;
  final ValueChanged<int> onFrameSettled;

  @override
  State<_MagicTreeImage> createState() => _MagicTreeImageState();
}

class _MagicTreeImageState extends State<_MagicTreeImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wipe = AnimationController(
    vsync: this,
    duration: kGrowWipeDuration,
    value: 1,
  );

  /// 正在被新帧盖掉的旧帧
  int? _fromFrame;
  late int _frame = widget.layout.frame;

  /// 已请求预解码的帧。整帧解码后是 941×1672×4 ≈ 6.3MB，22 帧全预解码要 138MB，
  /// 所以只预解码当前帧附近的窗口，且按显示宽度解码（cacheWidth）。
  final _decoded = <int>{};
  int? _notifiedSettledFrame;

  @override
  void initState() {
    super.initState();
    _notifyFrameSettled();
  }

  @override
  void dispose() {
    _wipe.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MagicTreeImage old) {
    super.didUpdateWidget(old);
    if (widget.layout.frame == _frame) return;
    _fromFrame = _frame;
    _frame = widget.layout.frame;
    _wipe.forward(from: 0).whenComplete(_notifyFrameSettled);
  }

  void _notifyFrameSettled() {
    if (!mounted || _notifiedSettledFrame == _frame) return;
    _notifiedSettledFrame = _frame;
    widget.onFrameSettled(_frame);
  }

  void _decodeWindow(int cacheWidth) {
    final want = <int>[];
    for (var f = _frame - 1; f <= _frame + 2; f++) {
      if (f < kTreeFrameFirst || f > kTreeFrameLast) continue;
      if (_decoded.add(f)) want.add(f);
    }
    if (want.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final f in want) {
        precacheImage(
          ResizeImage(AssetImage(treeFrameAsset(f)), width: cacheWidth),
          context,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.layout.imageRect;
    // 按显示尺寸解码：原图 941 宽在手机上只画到 ~430 逻辑像素，
    // 整幅解码等于白烧 5 倍内存与采样开销
    final cacheWidth = (rect.width * MediaQuery.devicePixelRatioOf(context))
        .round();
    _decodeWindow(cacheWidth);

    final wiping = _fromFrame != null && _wipe.value < 1;
    // 擦除线从土堆底扫到本帧树冠：这两条线之外素材里只有米白底，扫过去是空转
    final startY =
        rect.top + kFrameContentBottom * rect.height + kGrowWipeFeather;
    final endY = widget.layout.plantTopY;

    Widget layer(int frame, {bool wiped = false}) {
      Widget img = Image.asset(
        treeFrameAsset(frame),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheWidth,
      );
      if (wiped) {
        final y = startY - (startY - endY) * _wipe.value;
        final f = (kGrowWipeFeather / rect.height).clamp(0.02, 0.5);
        final t = (y - rect.top) / rect.height;
        img = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
            stops: [(t - f).clamp(0.0, 1.0), t.clamp(0.0, 1.0)],
          ).createShader(r),
          child: img,
        );
      }
      return Positioned.fromRect(rect: rect, child: img);
    }

    // RepaintBoundary：窗口模式滚章节时树背景完全不动（画幅与镜头档位无关），
    // 但标签每帧重建会带着整帧照片一起重栅格化。隔离后平移只重绘标签。
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          key: const Key('魔树完整图'),
          animation: _wipe,
          builder: (context, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              if (wiping) layer(_fromFrame!),
              layer(_frame, wiped: wiping),
            ],
          ),
        ),
      ),
    );
  }
}
