import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/carpet_constants.dart';
import '../../core/app_keys.dart';
import '../../core/content_font.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart' show inspirationRepositoryProvider;
import '../home/home_page.dart' show inspirationPoolProvider;
import '../home/planet_scene/planet_scene.dart' show advanced3DProvider;
import '../shared/quick_capture/quick_capture_layer.dart'
    show captureSheetOpenProvider;
import 'scroll_carpet.dart';

/// 墨色（配羊皮纸面板）
const _ink = Color(0xFF3A2A18);

/// 整卡吸附滚动：惯性滑完后吸附到卡槽整数倍位置，
/// 静止时永远不出现被拦腰截断的灵感卡（用户定稿：要么完整显示要么不显示）
class _SnapToCardPhysics extends ScrollPhysics {
  const _SnapToCardPhysics({super.parent});

  @override
  _SnapToCardPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapToCardPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 越界回弹交给父物理
    if (position.pixels <= position.minScrollExtent ||
        position.pixels >= position.maxScrollExtent) {
      return super.createBallisticSimulation(position, velocity);
    }
    // 先按父物理惯性模拟出落点（3 秒足够任何 fling 停稳），再吸附最近卡槽
    final sim = super.createBallisticSimulation(position, velocity);
    final end = sim?.x(3.0) ?? position.pixels;
    final target =
        ((end / kCarpetItemHeight).roundToDouble() * kCarpetItemHeight).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if ((target - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}

/// 全局魔毯句柄（大纲页拖拽落点后调 collapse）
final magicCarpetKey = GlobalKey<MagicCarpetState>();

/// 正在从卷轴拖拽的灵感（null=未拖拽）。拖拽时底部浮现垃圾桶可永久删除。
final carpetDragging = ValueNotifier<Inspiration?>(null);

/// 卷轴是否处于展开态（2026-07-16 用户定稿：点击卷轴外空白处自动复原）。
/// 全局层据此挂载"空白收起层"。
final carpetExpanded = ValueNotifier<bool>(false);

/// 已投进垃圾桶、等待确认删除的灵感。
///
/// 删除确认由全局层托管，而不是由垃圾桶 DragTarget 自己弹窗：拖拽完成后垃圾桶会
/// 随 carpetDragging 清空而卸载，如果弹窗依赖垃圾桶自身 context，会出现拖进去却删不掉。
final carpetTrashPending = ValueNotifier<Inspiration?>(null);

/// 折叠卷轴是否缩到右边栏（只露一点点）。大纲页章节多时置 true 让路，
/// 点缩起的卷轴即恢复完整（用户定稿：章节小节多了自动隐到边栏、点击恢复）。
final carpetTucked = ValueNotifier<bool>(false);

/// 全局魔毯层：叠在 Navigator 之上 → **任何界面**右上角都有魔毯
/// （用户定稿 2026-07-03：魔毯设在所有界面最上面，星球主界面也要有）。
/// 自带全屏 Overlay 供灵感拖拽浮影使用；空白区域不拦截指针；
/// 任何弹出层出现时随速记按钮一起让位。
class CarpetOverlay extends StatelessWidget {
  const CarpetOverlay({super.key, required this.child});

  /// 被覆盖的页面内容（整个 App 的 Navigator）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const _GlobalCarpet()),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlobalCarpet extends ConsumerWidget {
  const _GlobalCarpet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popupOpen = ref.watch(captureSheetOpenProvider);
    return Stack(
      children: [
        // 空白收起层（2026-07-16 用户定稿）：卷轴展开时点它外面的任意空白处
        // 自动复原。置于卷轴条带之下（卷轴自身交互优先）；拖拽中不挂载
        //（树/垃圾桶落点要可命中），速记弹层打开时也不挂载。
        if (!popupOpen)
          ValueListenableBuilder<bool>(
            valueListenable: carpetExpanded,
            builder: (context, expanded, _) => !expanded
                ? const SizedBox.shrink()
                : ValueListenableBuilder<Inspiration?>(
                    valueListenable: carpetDragging,
                    builder: (context, dragging, _) => dragging != null
                        ? const SizedBox.shrink()
                        : Positioned.fill(
                            child: GestureDetector(
                              key: const Key('卷轴空白收起层'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  magicCarpetKey.currentState?.collapse(),
                            ),
                          ),
                  ),
          ),
        // 顶部全宽横条：收球态贴右上，展开态整条卷轴自己居中（MagicCarpet 内部
        // 按展开状态切 Align），既保留右上折叠入口习惯，又让展开卷轴居中悬浮。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: IgnorePointer(
                ignoring: popupOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: popupOpen ? 0 : 1,
                  child: MagicCarpet(key: magicCarpetKey),
                ),
              ),
            ),
          ),
        ),
        // 拖拽灵感时：底部浮现垃圾桶，拖上去松手 → 确认 → 永久删除
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: ValueListenableBuilder<Inspiration?>(
              valueListenable: carpetDragging,
              builder: (context, dragging, _) => dragging == null
                  ? const SizedBox.shrink()
                  : Center(child: _TrashZone(inspiration: dragging)),
            ),
          ),
        ),
        const _TrashDeleteHost(),
      ],
    );
  }
}

class _TrashDeleteHost extends ConsumerStatefulWidget {
  const _TrashDeleteHost();

  @override
  ConsumerState<_TrashDeleteHost> createState() => _TrashDeleteHostState();
}

class _TrashDeleteHostState extends ConsumerState<_TrashDeleteHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    carpetTrashPending.addListener(_onPendingChanged);
  }

  @override
  void dispose() {
    carpetTrashPending.removeListener(_onPendingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void _onPendingChanged() {
    if (_showing || carpetTrashPending.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _confirmPendingDelete(),
    );
  }

  Future<void> _confirmPendingDelete() async {
    final inspiration = carpetTrashPending.value;
    if (!mounted || inspiration == null || _showing) return;
    _showing = true;
    final dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null) {
      carpetTrashPending.value = null;
      _showing = false;
      return;
    }
    final ok = await showCupertinoDialog<bool>(
      context: dialogContext,
      useRootNavigator: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text(
          '永久删除这条灵感？',
          style: TextStyle(
            fontFamily: 'LXGWWenKai',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '「${inspiration.content}」将从卷轴彻底删除，无法恢复。',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'LXGWWenKai', fontSize: 13),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(fontFamily: 'LXGWWenKai')),
          ),
          CupertinoDialogAction(
            key: const Key('永久删除确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '永久删除',
              style: TextStyle(fontFamily: 'LXGWWenKai'),
            ),
          ),
        ],
      ),
    );
    if (mounted && ok == true) {
      await ref
          .read(inspirationRepositoryProvider)
          .deleteForever(inspiration.id);
    }
    if (identical(carpetTrashPending.value, inspiration)) {
      carpetTrashPending.value = null;
    }
    _showing = false;
  }
}

/// 永久删除落区：拖拽灵感靠近时放大染红
class _TrashZone extends ConsumerStatefulWidget {
  const _TrashZone({required this.inspiration});

  final Inspiration inspiration;

  @override
  ConsumerState<_TrashZone> createState() => _TrashZoneState();
}

class _TrashZoneState extends ConsumerState<_TrashZone> {
  @override
  Widget build(BuildContext context) {
    return DragTarget<Inspiration>(
      onWillAcceptWithDetails: (d) => d.data.id == widget.inspiration.id,
      onAcceptWithDetails: (_) {
        HapticFeedback.mediumImpact();
        carpetTrashPending.value = widget.inspiration;
        carpetDragging.value = null;
      },
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 28),
          width: hot ? 84 : 68,
          height: hot ? 84 : 68,
          decoration: BoxDecoration(
            color: hot ? const Color(0xF2E5484D) : const Color(0xE62B2018),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 16),
            ],
          ),
          child: Icon(
            CupertinoIcons.trash,
            color: Colors.white,
            size: hot ? 36 : 28,
          ),
        );
      },
    );
  }
}

/// 灵感魔毯（2026-07-15 方案二「卷轴灵感」改版，参考图 picture/方案2_卷轴灵感）：
///
/// - 折叠态 = 短横向魔法卷轴（与展开态同一物件语言）
/// - 点击展开：滚轴先现身 → 羊皮纸长卷向下铺开 → 灵感墨迹按序写入。
///   灵感文字直接写在羊皮纸上（无独立白色卡片），条目间金色分隔纹，
///   超出可视槽位时长卷内滚动、右侧墨迹进度线指示位置
/// - 收起反向卷回（先淡墨迹、再卷纸面、最后回折叠卷轴）；拖拽落点后自动折叠
class MagicCarpet extends ConsumerStatefulWidget {
  const MagicCarpet({super.key});

  @override
  ConsumerState<MagicCarpet> createState() => MagicCarpetState();
}

class MagicCarpetState extends ConsumerState<MagicCarpet>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  /// 面板是否仍在画面中：收起时先保留面板播放反向卷回帧，结束后再切折叠卷轴
  bool _showPanel = false;

  /// 正在拖拽灵感：面板半透明且不拦截指针，给树上落点让路
  bool _dragging = false;

  /// 缩边栏态下临时"点开完整折叠卷轴"（3 秒后自动缩回边栏）
  bool _showFull = false;
  Timer? _reTuckTimer;

  /// 列表滚动控制（滚动停止后吸附整卡用）
  final ScrollController _listScroll = ScrollController();

  /// 正在拖动重排：期间不做吸附补正（重排自带自动滚动）
  bool _reordering = false;

  /// 重排后的乐观顺序：数据库流回填前先按用户拖完的样子显示，
  /// 避免松手瞬间闪回旧序再跳新序（用户反馈"不连贯"）
  List<Inspiration>? _optimisticPool;

  /// 纸面窗口净高（build 时按相框尺寸算），判断灵感是否溢出需滚动
  double _lastHoleHeight = 999;

  /// 卷轴展开主时间线：0~0.32 滚轴现身 → 0.26~0.72 纸面铺开 →
  /// 0.58~1.0 墨迹按序写入；收起 reverse（先淡墨迹再卷纸面）。
  /// （必须在 initState 立即创建：late 惰性到 dispose 才初始化会在
  /// 已卸载元素上建 Ticker 而崩溃）
  late final AnimationController _unroll;

  @override
  void initState() {
    super.initState();
    _unroll = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
      reverseDuration: const Duration(milliseconds: 480),
    );
  }

  bool get expanded => _expanded;

  /// 外部可调用：拖拽完成后自动折叠回右上卷轴（定稿）
  void collapse() {
    _finishDrag();
    if ((_expanded || _showPanel) && mounted) _toggle(false);
  }

  void _finishDrag() {
    carpetDragging.value = null;
    if (_dragging && mounted) setState(() => _dragging = false);
  }

  Future<void> _returnToCarpet(Inspiration inspiration) async {
    HapticFeedback.mediumImpact();
    await ref
        .read(inspirationRepositoryProvider)
        .removeFromSection(inspiration.id);
  }

  Widget _returnDropTarget(Widget child) {
    return DragTarget<Inspiration>(
      onWillAcceptWithDetails: (d) =>
          d.data.sectionId != null || d.data.chapterId != null,
      onAcceptWithDetails: (d) => _returnToCarpet(d.data),
      builder: (context, candidates, _) => AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: candidates.isNotEmpty ? 1.06 : 1.0,
        child: child,
      ),
    );
  }

  Future<void> _toggle(bool open) async {
    HapticFeedback.lightImpact();
    carpetExpanded.value = open; // 全局空白收起层据此挂载/卸载
    if (open) {
      _reTuckTimer?.cancel();
      setState(() {
        _expanded = true;
        _showPanel = true;
        _showFull = false; // 展开后关闭时回到缩边栏态
      });
      await _unroll.forward(from: 0);
    } else {
      _finishDrag();
      setState(() => _expanded = false);
      await _unroll.reverse();
      if (mounted) setState(() => _showPanel = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 预解码卷轴素材，首次折叠/展开不闪帧
    for (final name in const [
      'scroll_collapsed',
      'scroll_full',
      'scroll_parchment',
    ]) {
      precacheImage(
        AssetImage('assets/textures/scroll_carpet/$name.png'),
        context,
      );
    }
  }

  @override
  void dispose() {
    // 卷轴随宿主卸载时归零展开态，空白收起层跟着退场（测试反复 pump 场景）
    carpetExpanded.value = false;
    _reTuckTimer?.cancel();
    _listScroll.dispose();
    _unroll.dispose();
    super.dispose();
  }

  /// 把列表残余的半卡偏移补回最近卡槽（下一帧执行，避开当前滚动活动）
  void _scheduleSnapToSlot() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reordering || !_listScroll.hasClients) return;
      final m = _listScroll.position;
      final target =
          ((m.pixels / kCarpetItemHeight).roundToDouble() * kCarpetItemHeight)
              .clamp(m.minScrollExtent, m.maxScrollExtent);
      if ((target - m.pixels).abs() > 0.5) {
        _listScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 吸附补漏：轻点打断惯性等路径不经过物理层 ballistic（吸附管不到），
  /// 滚动一停就补吸附（用户定稿：不出现半张卡）
  bool _snapAfterScroll(ScrollEndNotification n) {
    if (!_reordering) _scheduleSnapToSlot();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 数据库流一有新值（重排落库后的回填）就丢掉乐观顺序
    ref.listen(inspirationPoolProvider, (_, _) {
      if (_optimisticPool != null) setState(() => _optimisticPool = null);
    });
    final pool =
        _optimisticPool ?? ref.watch(inspirationPoolProvider).value ?? const [];
    final screen = MediaQuery.sizeOf(context);
    // P4 整体化返工（2026-07-16）：整条卷轴是**固定宽高比的单张相框**，
    // 尺寸由宽度驱动、高度封顶护住地球可见区（五条以上只在纸面窗口内滚动，
    // 相框绝不长高）。
    var width = math.min(screen.width * 0.86, 356.0);
    var height = width / kScrollFrameAspect;
    final heightCap = math.min(screen.height * 0.62, 560.0);
    if (height > heightCap) {
      height = heightCap;
      width = height * kScrollFrameAspect;
    }
    final glow = ref.watch(advanced3DProvider);
    // 纸面窗口净高（相框挖空区），供判断是否溢出显示进度线
    _lastHoleHeight = height * (kScrollHoleBottom - kScrollHoleTop) - 20;

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      width: _showPanel ? width : kCollapsedScrollWidth,
      height: _showPanel ? height : kCollapsedScrollHeight,
      child: _showPanel
          // OverflowBox 让内容始终以展开后的尺寸布局，避免动画中途挤压溢出
          ? OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              alignment: Alignment.topLeft,
              child: _dragging
                  ? _buildPanel(pool, glow)
                  : _returnDropTarget(_buildPanel(pool, glow)),
            )
          : _returnDropTarget(_buildCollapsedScroll()),
    );
    // 展开态整条卷轴居中悬浮 + 顶部留白（不贴屏顶）；收球态回到右上角。
    return Align(
      alignment: _showPanel ? Alignment.topCenter : Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: _showPanel ? 16 : 0,
          right: _showPanel ? 0 : 12,
        ),
        child: box,
      ),
    );
  }

  /// 折叠态：短横向魔法卷轴。
  /// 缩边栏（章节多）时只露一点点：点一下临时露出完整折叠卷轴（3 秒后自动缩回），
  /// 完整态再点一下才展开魔毯；不缩边栏时点击直接展开。
  Widget _buildCollapsedScroll() {
    return ValueListenableBuilder<bool>(
      valueListenable: carpetTucked,
      builder: (context, tucked, _) {
        final peek = tucked && !_showFull; // 真正贴边只露一点点的状态
        return AnimatedSlide(
          offset: peek ? const Offset(0.62, 0) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: GestureDetector(
            key: const Key('魔毯小球'), // 历史 key：保留给拖拽/回归测试命中。
            onTap: () {
              if (peek) {
                // 贴边→点一下露出完整折叠卷轴，3 秒没进一步操作就自动缩回
                setState(() => _showFull = true);
                _reTuckTimer?.cancel();
                _reTuckTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) setState(() => _showFull = false);
                });
              } else {
                _reTuckTimer?.cancel();
                _toggle(true); // 完整态→展开魔毯
              }
            },
            child: Image.asset(
              'assets/textures/scroll_carpet/scroll_collapsed.png',
              key: const Key('灵感卷轴折叠态'),
              width: kCollapsedScrollWidth,
              height: kCollapsedScrollHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
    );
  }

  /// 展开态：整条卷轴相框（挖空纸面窗口内放墨迹内容）
  Widget _buildPanel(List<Inspiration> pool, bool glow) {
    return IgnorePointer(
      ignoring: _dragging,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        // 拖拽时完全隐藏面板：半透明残卡会像"残影"干扰落点（用户反馈）
        opacity: _dragging ? 0 : 1,
        child: _panelBody(pool, glow),
      ),
    );
  }

  Widget _panelBody(List<Inspiration> pool, bool glow) {
    final content = _paperContent(pool);
    // 展开分镜：相框随主时间线从上向下"抖开"（heightFactor 揭示，先出滚轴
    // 后落底部流苏）+ 淡入；墨迹随后按序写入；进度线/标题最后。收起 reverse。
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _unroll,
        builder: (context, _) {
          final reveal = Curves.easeOut.transform(
            (_unroll.value / 0.8).clamp(0.0, 1.0),
          );
          final fade = (_unroll.value / 0.3).clamp(0.0, 1.0);
          double? progress;
          final overflow =
              pool.length * kCarpetItemHeight > _lastHoleHeight + 0.5;
          if (overflow) {
            progress = 0;
            if (_listScroll.hasClients &&
                _listScroll.position.hasContentDimensions &&
                _listScroll.position.maxScrollExtent > 0) {
              progress =
                  _listScroll.position.pixels /
                  _listScroll.position.maxScrollExtent;
            }
          }
          return Opacity(
            opacity: fade,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: reveal.clamp(0.02, 1.0),
                child: ScrollFrame(
                  count: pool.length,
                  glow: glow,
                  onClose: () => _toggle(false),
                  progress: progress,
                  progressOpacity: ((_unroll.value - 0.85) / 0.15).clamp(
                    0.0,
                    1.0,
                  ),
                  titleOpacity: ((_unroll.value - 0.15) / 0.2).clamp(0.0, 1.0),
                  child: content,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 纸面内容：0 条淡墨水印 / 1 条居中大字 / 多条长卷逐条墨迹
  Widget _paperContent(List<Inspiration> pool) {
    if (pool.isEmpty) {
      // 空状态：提示作淡墨水印融入羊皮纸（星图水印在纸面素材里）
      return _inkFade(
        0,
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '卷轴空空如也\n随时速记一条灵感吧',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'LXGWWenKai',
                // 淡墨水印但要可读：比正文墨色略淡，仍压得住羊皮纸
                color: Color(0xC15A4326),
                fontSize: 14.5,
                height: 1.9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      );
    }
    if (pool.length == 1) {
      // 单条：居中大字，四周留呼吸空间（参考 01）
      return _inkFade(
        0,
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            child: CarpetItem(
              inspiration: pool.first,
              big: true,
              onDragStarted: () {
                setState(() => _dragging = true);
                carpetDragging.value = pool.first;
              },
              onDragEnd: _finishDrag,
            ),
          ),
        ),
      );
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: _snapAfterScroll,
      // 可重排长卷：右侧把手拖动重排（长按墨迹本体仍是拖上树）
      child: ReorderableListView.builder(
        scrollController: _listScroll,
        padding: const EdgeInsets.fromLTRB(2, 2, 14, 12),
        // 固定槽高 + 整卡吸附：静止时不出现被拦腰截断的条目
        physics: const _SnapToCardPhysics(),
        buildDefaultDragHandles: false,
        // 拖动替身透明底（默认 Material 灰底会遮纸面）
        proxyDecorator: (child, index, animation) =>
            Material(type: MaterialType.transparency, child: child),
        onReorderStart: (_) {
          _reordering = true;
          HapticFeedback.selectionClick();
        },
        onReorderEnd: (_) {
          // 重排的自动滚动可能停在半卡位，结束后补吸附
          _reordering = false;
          _scheduleSnapToSlot();
        },
        // onReorderItem 已自动修正移除位后的 newIndex。
        // 先乐观更新本地顺序（拖完什么样就是什么样），再落库
        onReorderItem: (oldIndex, newIndex) {
          final list = [...pool];
          list.insert(newIndex, list.removeAt(oldIndex));
          setState(() => _optimisticPool = list);
          ref
              .read(inspirationRepositoryProvider)
              .reorderCards(list.map((e) => e.id).toList());
        },
        itemCount: pool.length,
        itemBuilder: (context, i) => SizedBox(
          key: Key('魔毯行_${pool[i].id}'),
          height: kCarpetItemHeight,
          child: _inkFade(
            i,
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CarpetItem(
                          inspiration: pool[i],
                          onDragStarted: () {
                            setState(() => _dragging = true);
                            carpetDragging.value = pool[i];
                          },
                          onDragEnd: _finishDrag,
                        ),
                      ),
                      // 条目间金色分隔纹（最后一条不画）
                      if (i < pool.length - 1)
                        const GoldDivider()
                      else
                        const SizedBox(height: 10),
                    ],
                  ),
                ),
                // 排序把手：金线书签结（融入卷轴材质，不用系统图标）
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Center(
                      child: InkHandle(key: Key('魔毯排序把手_${pool[i].id}')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 墨迹淡入：第 [index] 条按主时间线错峰写入（收起时反向先淡出）
  Widget _inkFade(int index, Widget child) {
    return AnimatedBuilder(
      animation: _unroll,
      builder: (context, c) =>
          Opacity(opacity: inkFadeT(_unroll.value, index), child: c),
      child: child,
    );
  }
}

/// 长卷上的一条灵感墨迹：长按从纸面浮起成拖拽影子（可放到树上章/节标签），
/// 原位留淡墨残影，松手失败墨迹回写纸面。文字直接写在羊皮纸上，无卡片底。
class CarpetItem extends StatelessWidget {
  const CarpetItem({
    super.key,
    required this.inspiration,
    this.big = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  final Inspiration inspiration;

  /// 单条模式：居中大字（参考 01_单条灵感_展开态）
  final bool big;

  /// 拖起/结束通知（魔毯面板借此让路/复原）
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  /// 拖拽浮影尺寸（固定，供中心锚点计算）
  static const _feedbackWidth = 200.0;
  static const _feedbackHeight = 56.0;

  /// 浮影锚点 = 纸片**中心**对准手指。默认 pointer 锚在左上角，
  /// 拇指看起来总是捏着纸片最左边（用户实测反馈）。
  static Offset _centerDragAnchor(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) => const Offset(_feedbackWidth / 2, _feedbackHeight / 2);

  @override
  Widget build(BuildContext context) {
    final tile = _inkText();
    // 长按拖拽（列表内普通 Draggable 会与滚动手势冲突）
    return LongPressDraggable<Inspiration>(
      key: Key('魔毯灵感_${inspiration.id}'),
      data: inspiration,
      dragAnchorStrategy: _centerDragAnchor,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      onDragCompleted: onDragEnd,
      onDraggableCanceled: (_, _) => onDragEnd?.call(),
      // 拖起时的浮影：一小片撕下的羊皮纸（墨迹随纸浮起）
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: _feedbackWidth,
          height: _feedbackHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage(
                'assets/textures/scroll_carpet/scroll_parchment.png',
              ),
              fit: BoxFit.cover,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFC9A050), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x66C9A050), blurRadius: 14),
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            inspiration.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily:
                  contentFontFamily(inspiration.content) ?? 'LXGWWenKai',
              fontStyle: contentUsesBrandFont(inspiration.content)
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: _ink,
              fontSize: 13,
            ),
          ),
        ),
      ),
      // 淡墨残影：拖起后原位留下若隐若现的墨痕
      childWhenDragging: Opacity(opacity: 0.25, child: tile),
      child: tile,
    );
  }

  /// 墨迹本体：直接写在羊皮纸上（透明底），两行内优雅截断
  Widget _inkText() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 4 : 8, vertical: 4),
      alignment: big ? Alignment.center : Alignment.centerLeft,
      color: Colors.transparent,
      child: Text(
        inspiration.content,
        maxLines: big ? 4 : 2,
        overflow: TextOverflow.ellipsis,
        textAlign: big ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontFamily:
              contentFontFamily(inspiration.content) ?? 'LXGWWenKai',
          fontStyle: contentUsesBrandFont(inspiration.content)
              ? FontStyle.italic
              : FontStyle.normal,
          color: _ink,
          fontSize: big ? 19 : 13.5,
          height: big ? 1.7 : 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: big ? 2 : 0.4,
          // 轻微墨晕：像墨渗进纸纤维，而不是浮在纸上的控件文字
          shadows: const [
            Shadow(
              color: Color(0x30321F0E),
              blurRadius: 2.2,
              offset: Offset(0.4, 0.9),
            ),
          ],
        ),
      ),
    );
  }
}
