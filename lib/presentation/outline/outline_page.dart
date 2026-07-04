import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chinese_numbers.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import '../section/section_page.dart';
import '../shared/soft_toast.dart';
import 'label_layout.dart';
import 'magic_carpet.dart';
import 'magic_tree_model.dart';

/// 某小说的大纲流（章+节），魔树数据源
final outlineProvider =
    StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

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
  late final AnimationController _camera =
      AnimationController.unbounded(vsync: this, value: 0);

  /// 各章小节列表滚动量
  final Map<int, double> _sectionScrolls = {};

  /// 右半空白双击落点 y（onDoubleTapDown 记录 → onDoubleTap 用）
  double _rightDoubleTapY = 0;

  /// 正在生长的枝（章/节分开记，避免章节撞 id）
  ({bool isChapter, int id})? _growing;

  /// 最近一次布局（手势换算用）
  MagicTreeLayout? _layout;
  Size _bodySize = Size.zero;

  @override
  void dispose() {
    _grow.dispose();
    _camera.dispose();
    super.dispose();
  }

  Future<void> _playGrow({required bool isChapter, required int id}) async {
    setState(() => _growing = (isChapter: isChapter, id: id));
    await _grow.forward(from: 0);
    if (mounted) setState(() => _growing = null);
  }

  /// 点左侧空白：长出章枝（自动命名：引子 → 第一章 → …），镜头滑到新章
  Future<void> _addChapter(List<OutlineChapter> outline) async {
    HapticFeedback.lightImpact();
    final chapter = await ref.read(novelRepositoryProvider).createChapter(
          novelId: widget.novelId,
          title: defaultChapterTitle(outline.length),
        );
    final newCount = outline.length + 1;
    if (newCount > 2) {
      _camera.animateTo((newCount - 2).toDouble(),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
    await _playGrow(isChapter: true, id: chapter.id);
  }

  /// 点右侧空白：按点击高度找对应章，长出节枝
  Future<void> _addSection(
      List<OutlineChapter> outline, MagicTreeLayout layout, double y) async {
    if (outline.isEmpty) {
      showSoftToast(context, '先点左边空白，长出第一根章枝吧');
      return;
    }
    final chapterId = layout.chapterForY(y);
    if (chapterId == null) return;
    HapticFeedback.lightImpact();
    final chapter =
        outline.firstWhere((c) => c.chapter.id == chapterId);
    final section = await ref.read(novelRepositoryProvider).createSection(
          chapterId: chapterId,
          title: defaultSectionTitle(chapter.sections.length),
        );
    await _playGrow(isChapter: false, id: section.id);
  }

  // ── 镜头与小节滚动手势 ──────────────────────────────

  double get _bandH => (_bodySize.height - 12) / 2;

  /// 左半屏纵向拖动：滚章节（树背景跟随）
  void _onChapterDrag(DragUpdateDetails d) {
    final layout = _layout;
    if (layout == null || !layout.windowMode) return;
    _camera.stop();
    _camera.value = (_camera.value - d.delta.dy / _bandH)
        .clamp(0.0, layout.maxChapterOffset);
  }

  /// 松手：按甩动速度惯性投射若干章，再对齐到整章
  void _onChapterDragEnd(DragEndDetails d) {
    final layout = _layout;
    if (layout == null || !layout.windowMode) return;
    final v = d.velocity.pixelsPerSecond.dy;
    final projected = _camera.value - v * 0.35 / _bandH;
    final target =
        projected.roundToDouble().clamp(0.0, layout.maxChapterOffset);
    final distance = (target - _camera.value).abs();
    _camera.animateTo(target,
        duration: Duration(
            milliseconds: (200 + 90 * distance).clamp(200, 550).round()),
        curve: Curves.easeOutCubic);
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
      _sectionScrolls[ch] =
          ((_sectionScrolls[ch] ?? 0) - d.delta.dy).clamp(0.0, max);
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
        title: Text(label.chapterId != null ? '重命名这一章' : '重命名这一节',
            style: _dlgStyle(weight: FontWeight.w600)),
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
        title: Text('剪掉「${label.text}」？',
            style: _dlgStyle(weight: FontWeight.w600)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            isChapter
                ? '这一章和它的所有小节都会被剪掉；挂在上面的灵感会放回魔毯。'
                : '这一节会被剪掉；挂在上面的灵感会放回魔毯。',
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
            child: Text('剪掉',
                style: _dlgStyle(color: CupertinoColors.destructiveRed)),
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
            child: Text(label.chapterId != null ? '重命名这一章' : '重命名这一节',
                style: _dlgStyle()),
          ),
          CupertinoActionSheetAction(
            key: const Key('菜单删除'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('delete'),
            child: Text('剪掉这根枝丫',
                style: _dlgStyle(color: CupertinoColors.destructiveRed)),
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

  /// 双击：章 → 重命名；节 → 小节页
  Future<void> _onDoubleTap(PlacedLabel label) async {
    if (label.sectionId != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SectionPage(
          sectionId: label.sectionId!,
          initialTitle: label.text,
        ),
      ));
    } else {
      await _rename(label);
    }
  }

  /// 极简自绘头部（替代 Material AppBar）
  Widget _header(BuildContext context) => SizedBox(
        height: 52,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(CupertinoIcons.back, color: _ink, size: 26),
              ),
            ),
            Expanded(
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(width: 54), // 平衡返回箭头宽度
          ],
        ),
      );

  /// 生长中枝的当前比例（未在生长的枝恒为 1）
  double _growthFor({required bool isChapter, required int id}) {
    final g = _growing;
    if (g == null || g.isChapter != isChapter || g.id != id) return 1;
    return Curves.easeOutBack.transform(_grow.value);
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

  /// 一根卷须精灵（shift：在裁剪层内渲染时的坐标平移）
  Widget _tendril(VineBranch b, Offset shift) {
    return Positioned.fromRect(
      rect: b.spriteRect.shift(-shift),
      child: Transform.scale(
        scale: _growthFor(isChapter: b.isChapter, id: b.id),
        // 缩放锚点 = 根茬（右缘/左缘 31% 高度处）
        alignment: b.isChapter
            ? const Alignment(1.0, -0.38)
            : const Alignment(-1.0, -0.38),
        child: Image.asset(
          b.isChapter
              ? 'assets/textures/tendril_chapter.png'
              : 'assets/textures/tendril_section.png',
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  /// 一枚枝端标签胶囊（热区：长按菜单/双击/拖拽落点）
  Widget _labelCapsule(
      PlacedLabel label, List<OutlineChapter> outline, Offset shift) {
    return Positioned.fromRect(
      rect: label.rect.inflate(13).shift(-shift),
      child: DragTarget<Inspiration>(
        onAcceptWithDetails: (details) =>
            _dropInspiration(details.data, label, outline),
        builder: (context, candidates, _) => GestureDetector(
          key: Key(label.chapterId != null
              ? '章热区_${label.chapterId}'
              : '节热区_${label.sectionId}'),
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _showBranchMenu(label),
          onDoubleTap: () => _onDoubleTap(label),
          child: Opacity(
            opacity: _labelOpacity(label),
            child: Center(
              // 羊皮纸胶囊底：压在照片绿叶上也可读；拖拽悬停时染金
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: candidates.isNotEmpty
                      ? const Color(0xF2E9B84C)
                      : const Color(0xE8FDF6EC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x1A3A2A18)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(label.text,
                    maxLines: 1, style: labelStyle(bold: label.bold)),
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
        ref.watch(outlineProvider(widget.novelId)).value ?? const [];

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
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_grow, _camera]),
                    builder: (context, _) {
                      final layout = layoutMagicTree(
                        size: size,
                        outline: outline,
                        chapterOffset: _camera.value,
                        sectionScrolls: _sectionScrolls,
                      );
                      _layout = layout;
                      final labels = placeMagicLabels(
                        layout,
                        canvasWidth: size.width,
                        textScaler: MediaQuery.textScalerOf(context),
                      );
                      // 窗口模式：节按章分组，滚动时裁剪在本章高度带内
                      final secClip = {
                        for (final s in layout.sections)
                          s.id: s.clipChapterId,
                      };
                      final clipRects = <int, Rect>{
                        if (layout.windowMode)
                          for (final e in layout.chapterBands.entries)
                            // 上边缘只留 2px（原 20px 会切掉第一节的上置标签），
                            // 与上一章带的裁剪下沿恰好错开、互不重叠
                            e.key: Rect.fromLTRB(0, e.value.$1 + 2,
                                size.width, e.value.$2 - 2),
                      };

                      Widget clipped(int chapterId, List<Widget> children) {
                        final rect = clipRects[chapterId]!;
                        return Positioned.fromRect(
                          rect: rect,
                          child: ClipRect(
                            child: Stack(children: children),
                          ),
                        );
                      }

                      return Stack(
                        children: [
                          // 魔树本体：阶段摄影素材，窗口模式随镜头平移
                          Positioned.fromRect(
                            rect: layout.imageRect,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 600),
                              child: Image.asset(
                                'assets/textures/magic_tree_${layout.stage}.jpg',
                                key: ValueKey(layout.stage),
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
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
                              onDoubleTap: () =>
                                  _addSection(outline, layout, _rightDoubleTapY),
                              onVerticalDragStart: _onSectionDragStart,
                              onVerticalDragUpdate: _onSectionDrag,
                            ),
                          ),
                          // 卷须与标签（窗口模式的节裁剪在本章带内）
                          IgnorePointer(
                            child: Stack(
                              children: [
                                for (final b in layout.chapters)
                                  _tendril(b, Offset.zero),
                                for (final b in layout.sections)
                                  if (b.clipChapterId == null)
                                    _tendril(b, Offset.zero),
                                for (final e in clipRects.entries)
                                  clipped(e.key, [
                                    for (final b in layout.sections)
                                      if (b.clipChapterId == e.key)
                                        _tendril(b, e.value.topLeft),
                                  ]),
                              ],
                            ),
                          ),
                          // 标签热区：章与整树模式的节直接放；窗口模式的节按带裁剪
                          for (final label in labels)
                            if (label.chapterId != null ||
                                secClip[label.sectionId] == null)
                              _labelCapsule(label, outline, Offset.zero),
                          for (final e in clipRects.entries)
                            clipped(e.key, [
                              for (final label in labels)
                                if (label.sectionId != null &&
                                    secClip[label.sectionId] == e.key)
                                  _labelCapsule(
                                      label, outline, e.value.topLeft),
                            ]),
                        ],
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

  /// 拖拽落点：灵感挂到节；落在章上则挂到该章最新一节
  Future<void> _dropInspiration(Inspiration inspiration, PlacedLabel label,
      List<OutlineChapter> outline) async {
    int? sectionId = label.sectionId;
    if (sectionId == null && label.chapterId != null) {
      final chapter = outline
          .where((c) => c.chapter.id == label.chapterId)
          .firstOrNull;
      if (chapter == null || chapter.sections.isEmpty) {
        showSoftToast(context, '这一章还没有小节，先点右边空白长一根节枝');
        return;
      }
      sectionId = chapter.sections.last.id;
    }
    if (sectionId == null) return;

    await ref
        .read(inspirationRepositoryProvider)
        .assignToSection(inspiration.id, sectionId);
    magicCarpetKey.currentState?.collapse();
  }
}
