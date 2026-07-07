import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/carpet_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart' show inspirationRepositoryProvider;
import '../home/home_page.dart' show inspirationPoolProvider;
import '../shared/quick_capture/quick_capture_layer.dart'
    show captureSheetOpenProvider;

/// 墨色（配羊皮纸面板）
const _ink = Color(0xFF3A2A18);

/// 全局魔毯句柄（大纲页拖拽落点后调 collapse）
final magicCarpetKey = GlobalKey<MagicCarpetState>();

/// 正在从魔毯拖拽的灵感（null=未拖拽）。拖拽时底部浮现垃圾桶可永久删除。
final carpetDragging = ValueNotifier<Inspiration?>(null);

/// 魔毯小球是否缩到右边栏（只露一点点）。大纲页章节多时置 true 让路，
/// 点缩起的小球即恢复完整（用户定稿：章节小节多了自动隐到边栏、点击恢复）。
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
        Positioned(
          top: 0,
          right: 12,
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
      ],
    );
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
  Future<void> _confirmDelete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
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
            '「${widget.inspiration.content}」将从魔毯彻底删除，无法恢复。',
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
    if (ok == true) {
      await ref
          .read(inspirationRepositoryProvider)
          .deleteForever(widget.inspiration.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<Inspiration>(
      onWillAcceptWithDetails: (d) => d.data.id == widget.inspiration.id,
      onAcceptWithDetails: (_) {
        HapticFeedback.mediumImpact();
        _confirmDelete();
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

/// 灵感魔毯（2026-07-03 照片级改版，用户素材 picture/魔毯1-9）：
///
/// - 缩球态 = 素材"魔毯1"卷球照片本体
/// - 点击展开：**逐帧播放素材 1→9 的真实展开动画**（卷球徐徐摊平），
///   摊平的魔毯横陈面板顶部，灵感列表在其下的羊皮纸毛玻璃卡内
/// - 收起反向卷回；拖拽落点后自动缩球
class MagicCarpet extends ConsumerStatefulWidget {
  const MagicCarpet({super.key});

  @override
  ConsumerState<MagicCarpet> createState() => MagicCarpetState();
}

class MagicCarpetState extends ConsumerState<MagicCarpet>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  /// 面板是否仍在画面中：收起时先保留面板播放反向卷回帧，结束后再切小球
  bool _showPanel = false;

  /// 正在拖拽灵感：面板半透明且不拦截指针，给树上落点让路
  bool _dragging = false;

  /// 缩边栏态下临时"点开完整球"（3 秒后自动缩回边栏）
  bool _showFull = false;
  Timer? _reTuckTimer;

  /// 展开帧动画：value 0→1 映射素材帧 1→9
  /// （必须在 initState 立即创建：late 惰性到 dispose 才初始化会在
  /// 已卸载元素上建 Ticker 而崩溃）
  late final AnimationController _unroll;

  @override
  void initState() {
    super.initState();
    _unroll = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  /// 展开面板顶部魔毯横幅高度
  static const _bannerHeight = 210.0;

  bool get expanded => _expanded;

  /// 外部可调用：拖拽完成后自动缩回小球（定稿）
  void collapse() {
    if ((_expanded || _showPanel) && mounted) _toggle(false);
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
    if (open) {
      _reTuckTimer?.cancel();
      setState(() {
        _expanded = true;
        _showPanel = true;
        _showFull = false; // 展开后关闭时回到缩边栏态
      });
      await _unroll.forward(from: 0);
    } else {
      setState(() => _expanded = false);
      await _unroll.reverse();
      if (mounted) setState(() => _showPanel = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 预解码九帧，首次展开不闪帧
    for (var f = 1; f <= 9; f++) {
      precacheImage(AssetImage('assets/textures/carpet_frame_$f.png'), context);
    }
  }

  @override
  void dispose() {
    _reTuckTimer?.cancel();
    _unroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pool = ref.watch(inspirationPoolProvider).value ?? const [];
    final width = MediaQuery.sizeOf(context).width * 0.86;
    final height = _bannerHeight + carpetHeight(pool.length);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      width: _showPanel ? width : kCarpetBallSize,
      height: _showPanel ? height : kCarpetBallSize,
      child: _showPanel
          // OverflowBox 让内容始终以展开后的尺寸布局，避免动画中途挤压溢出
          ? OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              alignment: Alignment.topLeft,
              child: _dragging
                  ? _buildPanel(pool, width, height)
                  : _returnDropTarget(_buildPanel(pool, width, height)),
            )
          : _returnDropTarget(_buildBall()),
    );
  }

  /// 缩球态：素材卷球照片。
  /// 缩边栏（章节多）时只露一点点：点一下临时露出完整球（3 秒后自动缩回），
  /// 完整态再点一下才展开魔毯；不缩边栏时点击直接展开。
  Widget _buildBall() {
    return ValueListenableBuilder<bool>(
      valueListenable: carpetTucked,
      builder: (context, tucked, _) {
        final peek = tucked && !_showFull; // 真正贴边只露一点点的状态
        return AnimatedSlide(
          offset: peek ? const Offset(0.62, 0) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: GestureDetector(
            key: const Key('魔毯小球'),
            onTap: () {
              if (peek) {
                // 贴边→点一下露出完整球，3 秒没进一步操作就自动缩回
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
              'assets/textures/carpet_ball.png',
              width: kCarpetBallSize,
              height: kCarpetBallSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }

  /// 展开态：魔毯展开动画横幅 + 羊皮纸毛玻璃灵感列表
  Widget _buildPanel(List<Inspiration> pool, double width, double height) {
    return IgnorePointer(
      ignoring: _dragging,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _dragging ? 0.22 : 1,
        child: _panelBody(pool, width, height),
      ),
    );
  }

  /// 标题/空状态文字用的柔和阴影（浮在星空/魔树背景上仍可读）
  static const _floatShadow = [
    Shadow(color: Color(0xCCFFFFFF), blurRadius: 6),
    Shadow(color: Color(0x66FFFFFF), blurRadius: 12),
  ];

  Widget _panelBody(List<Inspiration> pool, double width, double height) {
    // 透明浮层：不再有实底面板。魔毯图透明四周、灵感卡之间的空隙，
    // 都直接透出后面一层的背景（用户定稿：有内容置顶、空处显背景）。
    // 透明 Material 供 Text/InkWell 用；外层 GestureDetector 空处轻点收起。
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // 吸收空处轻点（不painting → 背景照样透出）
        onTap: () => _toggle(false),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 魔毯横幅：逐帧展开动画（contain → 两侧透出背景）
              SizedBox(
                height: _bannerHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _unroll,
                        builder: (context, _) {
                          final t = Curves.easeInOut.transform(_unroll.value);
                          final frame = 1 + (t * 8).round();
                          return Image.asset(
                            'assets/textures/carpet_frame_$frame.png',
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        key: const Key('魔毯收起按钮'),
                        icon: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: Color(0xE63A2A18),
                          size: 26,
                          shadows: _floatShadow,
                        ),
                        onPressed: () => _toggle(false),
                      ),
                    ),
                  ],
                ),
              ),
              // 标题（浮字带白晕，任何背景上可读）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Text(
                  '灵感魔毯 · ${pool.length}',
                  style: const TextStyle(
                    fontFamily: 'LXGWWenKai',
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    shadows: _floatShadow,
                  ),
                ),
              ),
              // 灵感列表（卡片不透明→可读；卡间与列表未占满处透出背景）
              Expanded(
                child: pool.isEmpty
                    ? const Center(
                        child: Text(
                          '魔毯空空如也\n随时速记一条灵感吧',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'LXGWWenKai',
                            color: _ink,
                            fontSize: 13,
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                            shadows: _floatShadow,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                        itemCount: pool.length,
                        itemBuilder: (context, i) => CarpetItem(
                          inspiration: pool[i],
                          onDragStarted: () {
                            setState(() => _dragging = true);
                            carpetDragging.value = pool[i];
                          },
                          onDragEnd: () {
                            setState(() => _dragging = false);
                            carpetDragging.value = null;
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 魔毯上的一条灵感：长按拖起，可放到树上章/节标签（DragTarget 在大纲页）
class CarpetItem extends StatelessWidget {
  const CarpetItem({
    super.key,
    required this.inspiration,
    this.onDragStarted,
    this.onDragEnd,
  });

  final Inspiration inspiration;

  /// 拖起/结束通知（魔毯面板借此让路/复原）
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    // 长按拖拽（列表内普通 Draggable 会与滚动手势冲突）
    return LongPressDraggable<Inspiration>(
      key: Key('魔毯灵感_${inspiration.id}'),
      data: inspiration,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      // 拖起时的浮影：一张微光羊皮纸小卡
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC9A050), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x59C9A050), blurRadius: 14),
            ],
          ),
          child: Text(
            inspiration.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'LXGWWenKai',
              color: _ink,
              fontSize: 13,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  Widget _tile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        // 不透明羊皮纸底：卡片浮在星空/魔树背景上文字仍清晰
        color: const Color(0xFAFFFCF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33C9A050)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        inspiration.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'LXGWWenKai',
          color: _ink,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}
