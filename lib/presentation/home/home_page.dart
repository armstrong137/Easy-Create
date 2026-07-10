import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/creative_energy.dart';
import '../../core/spin_inertia.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../outline/outline_page.dart';
import '../settings/settings_page.dart';
import 'orbiting_inspirations.dart';
import 'planet_scene/planet_scene.dart';
import 'planet_view.dart';
import 'saturn_rings_painter.dart';
import 'starfield.dart';

/// 魔毯灵感池流（全局共享，环绕文字数据源）
final inspirationPoolProvider = StreamProvider<List<Inspiration>>(
  (ref) => ref.watch(inspirationRepositoryProvider).watchPool(),
);

/// 全部小说（星球），按首页排列顺序
final novelsProvider = StreamProvider<List<Novel>>(
  (ref) => ref.watch(novelRepositoryProvider).watchNovels(),
);

/// 某小说的创作量（章+节+其下灵感），驱动该星球转速与星空亮度
final creativeCountProvider = StreamProvider.family<int, int>(
  (ref, novelId) =>
      ref.watch(novelRepositoryProvider).watchCreativeCount(novelId),
);

/// 星球 shader 资源（按行星纹理名缓存，如 'earth'）
final planetAssetsProvider = FutureProvider.family<PlanetShaderAssets, String>(
  (ref, planet) => PlanetShaderAssets.load(planet),
);

/// 可选行星纹理（新建星球按当前数量轮换分配）
const kPlanetTextures = ['earth', 'mars', 'jupiter', 'venus', 'saturn'];

/// 3D 星球透明舞台倍率：画布放大同时镜头等比拉远，
/// 初始视觉大小不变，放大时星球有空间铺开而不撞画布方形边缘。
const kPlanetSceneStageScale = 3.0;

/// 星球最大放大倍率（受舞台倍率约束：超过就会露出画布方边）
const kPlanetSceneMaxZoom = kPlanetSceneStageScale;

/// 放大超过此倍率即隐藏书名（避免压在放大的星球上）
const kPlanetTitleHideZoom = 1.06;

/// 捏合增益：手指张开比例的幂次。整屏最多张开约 1.6 倍，
/// 直接 1:1 映射够不到 3 倍上限、捏合"使不上劲"
const kPinchGain = 2.6;

/// 拖动转星球的俯仰上限（弧度）：别转到极点翻面
const kMaxPitch = math.pi / 2 * 0.92;

/// 星球放大/捏合期间锁住 PageView：双指缩放不会误翻页
/// （沿用魔毯 carpetDragging 的全局 ValueNotifier 惯例）
final planetZoomLock = ValueNotifier<bool>(false);

/// 首页｜创作宇宙：一颗星球 = 一部小说，左右滑切换
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final PageController _pageController;

  /// 当前浏览的星球下标（星空亮度跟随它对应的小说）
  int _currentPage = 0;

  int? _pendingNovelId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 点击标题创建新星球：输入书名，纹理按现有数量轮换分配
  Future<void> _createNovel() async {
    final title = await _promptText(
      context: context,
      heading: '创造一颗新星球',
      hint: '这部小说叫什么？',
      confirm: '诞生',
      fieldKey: const Key('新星球书名输入框'),
      confirmKey: const Key('新星球确认按钮'),
    );

    final name = title?.trim() ?? '';
    if (name.isEmpty) return;
    final count = ref.read(novelsProvider).value?.length ?? 0;
    final novel = await ref
        .read(novelRepositoryProvider)
        .createNovel(
          title: name,
          planet: kPlanetTextures[count % kPlanetTextures.length],
        );
    if (!mounted) return;
    setState(() => _pendingNovelId = novel.id);
    _scheduleCreatedNovelJump(ref.read(novelsProvider).value ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final novels = ref.watch(novelsProvider).value ?? const [];
    final pool = ref.watch(inspirationPoolProvider).value ?? const [];

    // 当前星球的创作量 → 星空亮度（无星球时最暗）
    final currentNovel = novels.isEmpty
        ? null
        : novels[_currentPage.clamp(0, novels.length - 1)];
    final currentCount = currentNovel == null
        ? 0
        : ref.watch(creativeCountProvider(currentNovel.id)).value ?? 0;
    _scheduleCreatedNovelJump(novels);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Starfield(brightness: starBrightness(currentCount)),
          if (novels.isEmpty)
            // 空宇宙：邀请创建第一颗星球
            const Center(
              child: Text(
                '宇宙一片寂静\n点上方 Create Something 点亮第一颗星球',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            )
          else
            // 一页一星球，左右滑切换小说
            ValueListenableBuilder<bool>(
              valueListenable: planetZoomLock,
              builder: (context, locked, _) => PageView.builder(
                controller: _pageController,
                itemCount: novels.length,
                allowImplicitScrolling: true,
                // 捏合放大星球期间禁翻页（否则双指会被识别成滑动换书）
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (i) => setState(() => _currentPage = i),
                // ClipRect：放大的星球画布只在本页内铺开，
                // 不会溢出到相邻星球页造成"两颗星球重影"
                itemBuilder: (context, i) => ClipRect(
                  child: _PlanetPage(
                    key: ValueKey(
                      'planet-page-${novels[i].id}-${novels[i].planet}',
                    ),
                    novel: novels[i],
                    pool: pool,
                    active: i == _currentPage,
                  ),
                ),
              ),
            ),
          // 左上角设置入口（齿轮）：进设置页改速记按钮左右侧
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: GestureDetector(
                  key: const Key('设置入口'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      CupertinoIcons.gear,
                      color: Colors.white70,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 顶部标题：点击创建新星球
          // 定稿要求 Arabic Typesetting（微软授权字体，无法打包分发）——
          // 暂以衬线斜体近似，待终审；有授权字体文件放 assets/fonts 即可替换
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              // 下移到右上角魔毯球（92px）下方，避免标题右端与球重叠。
              // padding 放在 GestureDetector 外，热区只裹文字（点击命中稳定）
              child: Padding(
                padding: const EdgeInsets.only(top: 100),
                child: GestureDetector(
                  key: const Key('创建新星球标题'),
                  onTap: _createNovel,
                  child: const Text(
                    'Create Something',
                    style: TextStyle(
                      fontSize: 26,
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleCreatedNovelJump(List<Novel> novels) {
    final pendingId = _pendingNovelId;
    if (pendingId == null) return;
    final target = novels.indexWhere((n) => n.id == pendingId);
    if (target < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingNovelId != pendingId) return;
      _pendingNovelId = null;
      setState(() => _currentPage = target);
      if (!_pageController.hasClients) return;
      _pageController.jumpToPage(target);
    });
  }
}

/// 单颗星球页：星球 + 环绕灵感 + 书名，点星球进大纲页
class _PlanetPage extends ConsumerStatefulWidget {
  const _PlanetPage({
    super.key,
    required this.novel,
    required this.pool,
    required this.active,
  });

  final Novel novel;
  final List<Inspiration> pool;
  final bool active;

  @override
  ConsumerState<_PlanetPage> createState() => _PlanetPageState();
}

class _PlanetPageState extends ConsumerState<_PlanetPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// 当前缩放倍率（下发到 3D 场景做镜头推进，不是位图放大）
  double _zoom = 1;

  /// 拖动转星球的角度与松手后的惯性滑行（地球仪手感）
  final _spin = SpinInertia(maxPitch: kMaxPitch);
  // 必须在 initState 建：late final 会拖到 dispose 时才首次创建，
  // 那时 widget 树正在拆除，createTicker 会断言失败
  late final Ticker _glideTicker;
  Duration _lastGlideTs = Duration.zero;

  /// 上一次拖动事件的时间戳（用于估计角速度）
  Duration _lastMoveTs = Duration.zero;

  /// 双指跟踪：指针位置、捏合起始两指间距与起始倍率
  final _pointers = <int, Offset>{};
  double _pinchStartDist = 0;
  double _pinchStartZoom = 1;

  /// 单指落在星球上 → 本次拖动用于转星球（而非翻页切星球）
  bool _rotating = false;

  /// 星球画面区域（用于判断手指是否落在球上）
  final _planetKey = GlobalKey();

  bool get _zoomed => _zoom > kPlanetTitleHideZoom;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _glideTicker = createTicker(_onGlideTick);
  }

  @override
  void dispose() {
    _glideTicker.dispose();
    super.dispose();
  }

  /// 惯性滑行：每帧推进角度，停下即关掉 Ticker（不可见时不烧 CPU）
  void _onGlideTick(Duration elapsed) {
    final dt = (elapsed - _lastGlideTs).inMicroseconds / 1e6;
    _lastGlideTs = elapsed;
    if (dt <= 0) return;
    final stillGliding = _spin.tick(dt);
    setState(() {});
    if (!stillGliding) _glideTicker.stop();
  }

  void _startGlide() {
    _spin.release();
    if (!_spin.gliding || _glideTicker.isActive) return;
    _lastGlideTs = Duration.zero;
    _glideTicker.start();
  }

  void _syncPageLock() {
    // 捏合、转星球、已放大时都锁住 PageView，避免误翻页
    planetZoomLock.value = _pointers.length >= 2 || _rotating || _zoom > 1.001;
  }

  void _resetZoom() {
    setState(() => _zoom = 1);
    _syncPageLock();
  }

  /// 星球当前的视觉半径（放大后变大）；返回 null 表示还没布局
  ({Offset center, double radius})? _planetCircle() {
    final box = _planetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return (
      center: box.localToGlobal(box.size.center(Offset.zero)),
      radius: box.size.shortestSide / 2 * _zoom,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 1) {
      // 手指落在球面上才接管拖动（落在球外留给 PageView 翻页）
      final circle = _planetCircle();
      _rotating =
          circle != null &&
          (e.position - circle.center).distance <= circle.radius;
      if (_rotating) {
        // 按住即抓停滑行中的星球
        _spin.grab();
        _glideTicker.stop();
        _lastMoveTs = e.timeStamp;
      }
    } else if (_pointers.length == 2) {
      _rotating = false; // 双指优先给缩放
      final p = _pointers.values.toList();
      _pinchStartDist = (p[0] - p[1]).distance;
      _pinchStartZoom = _zoom;
    }
    _syncPageLock();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final prev = _pointers[e.pointer]!;
    _pointers[e.pointer] = e.position;

    // 单指拖球面 → 转星球。位移除以球半径即为转过的弧度（贴合手指的自然手感），
    // 放大时同样的位移对应更小的转角，便于细看某个区域
    if (_rotating && _pointers.length == 1) {
      final circle = _planetCircle();
      if (circle == null) return;
      final d = e.position - prev;
      final dt = (e.timeStamp - _lastMoveTs).inMicroseconds / 1e6;
      _lastMoveTs = e.timeStamp;
      setState(() {
        _spin.dragBy(d.dx / circle.radius, d.dy / circle.radius, dt);
      });
      return;
    }

    if (_pointers.length < 2 || _pinchStartDist <= 0) return;
    final p = _pointers.values.toList();
    final dist = (p[0] - p[1]).distance;
    // 手指张开比例带增益：整屏只能张开约 1.6 倍，直接映射够不到 3 倍上限，
    // 捏合会"使不上劲"。取幂放大手感（1.6^2.6 ≈ 3.4，够到顶且不突兀）
    final raw = dist / _pinchStartDist;
    final gained = math.pow(raw, kPinchGain).toDouble();
    final next = (_pinchStartZoom * gained).clamp(1.0, kPlanetSceneMaxZoom);
    if ((next - _zoom).abs() > 0.002) setState(() => _zoom = next);
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDist = 0;
    if (_pointers.isEmpty) {
      // 甩手松开 → 星球带着惯性继续滑行一段
      if (_rotating) _startGlide();
      _rotating = false;
    }
    // 松手后接近原始大小就吸附回 1，避免停在 1.02 这种尴尬位（书名一直藏着）
    if (_pointers.isEmpty && _zoom > 1 && _zoom < kPlanetTitleHideZoom) {
      _resetZoom();
      return;
    }
    _syncPageLock();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final novel = widget.novel;
    final count = ref.watch(creativeCountProvider(novel.id)).value ?? 0;
    final use3D = ref.watch(advanced3DProvider);
    // 3D 场景不依赖 shader 资源；旧路径（测试/低端回退）仍需等待加载
    final assets = use3D
        ? null
        : ref.watch(planetAssetsProvider(novel.planet)).value;
    final diameter = MediaQuery.sizeOf(context).width * 0.62;
    final ready = use3D || assets != null;

    // 星球本体：真实 3D 场景（阶段八 P2-1）或旧 FragmentShader（回退）
    Widget planetBody() {
      if (use3D) {
        // 土星的 3D 环带在场景内渲染，加宽画幅给环留位
        final sceneDiameter = novel.planet == 'saturn'
            ? diameter * 1.4
            : diameter;
        // 舞台：画布放到 stage 倍（镜头同步拉远、初始视觉不变），
        // 放大时星球在画布内铺开不被方形边裁。OverflowBox 使其只溢出绘制、
        // 不撑大布局与命中区（否则会盖住魔毯球与速记按钮）。
        return SizedBox.square(
          key: _planetKey,
          dimension: sceneDiameter,
          child: OverflowBox(
            maxWidth: sceneDiameter * kPlanetSceneStageScale,
            maxHeight: sceneDiameter * kPlanetSceneStageScale,
            child: PlanetScene(
              key: ValueKey('planet-scene-${novel.id}-${novel.planet}'),
              planet: novel.planet,
              spin: planetSpin(count),
              diameter: sceneDiameter * kPlanetSceneStageScale,
              stageScale: kPlanetSceneStageScale,
              zoom: _zoom,
              yaw: _spin.yaw,
              pitch: _spin.pitch,
              autoPrewarm: widget.active,
            ),
          ),
        );
      }
      return SizedBox.square(
        key: _planetKey,
        dimension: diameter,
        child: novel.planet == 'saturn'
            ? SaturnView(
                assets: assets!,
                spin: planetSpin(count),
                diameter: diameter,
              )
            : PlanetView(
                assets: assets!,
                spin: planetSpin(count),
                diameter: diameter,
              ),
      );
    }

    // 捏合监听盖住整页而非只盖星球：
    // 星球是平台视图（WebView/iframe），指针能否穿透它取决于宿主实现；
    // 提到整页后屏幕任意处双指都能缩放，也更好用
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      behavior: HitTestBehavior.translucent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            key: Key('星球_${novel.id}'),
            behavior: HitTestBehavior.opaque,
            // 点星球 → 进入该小说的大纲页（铅笔树）。放大态也直接进入，
            // 避免用户点击地球时被"复位缩放"吞掉第一次点击。
            onTap: !ready
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OutlinePage(novelId: novel.id, title: novel.title),
                      ),
                    );
                  },
            onLongPress: () => _confirmDeleteNovel(context, ref),
            child: !ready
                // 占位也要带 key：否则星球未就绪时"手指是否在球上"恒为否
                ? SizedBox.square(key: _planetKey, dimension: diameter)
                : OrbitingInspirations(
                    // 环绕取"最近几条"：魔毯池已改为旧→新/手动序，
                    // 这里单独按创建时间倒序取最新（轨道显示灵感原文）
                    items: [...widget.pool]
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
                    orbitWidth: diameter * 1.5,
                    // 放大态下环绕文字淡出，避免压在放大的星球上
                    fade: _zoomed,
                    child: planetBody(),
                  ),
          ),
          const SizedBox(height: 28),
          // 书名（楷体白字）：单击可重命名；放大星球时淡出让位
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _zoomed ? 0 : 1,
            child: IgnorePointer(
              ignoring: _zoomed,
              child: GestureDetector(
                key: Key('书名_${novel.id}'),
                onTap: () => _renameNovel(context, ref),
                child: Text(
                  novel.title,
                  style: const TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteNovel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除这颗星球？', style: _dlgStyle(weight: FontWeight.w600)),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '「${widget.novel.title}」的大纲会被剪掉，挂在小节里的灵感会回到魔毯。',
            style: _dlgStyle(size: 14, color: const Color(0xFF4A3A28)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('星球删除确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: _dlgStyle(weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(novelRepositoryProvider).deleteNovel(widget.novel.id);
    }
  }

  /// 单击书名 → 重命名对话框 → 落库
  Future<void> _renameNovel(BuildContext context, WidgetRef ref) async {
    final newTitle = await _promptText(
      context: context,
      heading: '重命名这颗星球',
      hint: '新名字',
      confirm: '保存',
      initial: widget.novel.title,
      fieldKey: const Key('书名重命名输入框'),
      confirmKey: const Key('书名重命名确认按钮'),
    );
    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == widget.novel.title) return;
    await ref.read(novelRepositoryProvider).renameNovel(widget.novel.id, title);
  }
}

/// 楷体文字（弹窗共用）
TextStyle _dlgStyle({double size = 17, FontWeight? weight, Color? color}) =>
    TextStyle(
      fontFamily: 'LXGWWenKai',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

/// iOS 质感文字输入弹窗（建星球/重命名共用，替代 Material AlertDialog）
Future<String?> _promptText({
  required BuildContext context,
  required String heading,
  required String hint,
  required String confirm,
  required Key fieldKey,
  required Key confirmKey,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  final result = showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final media = MediaQuery.of(dialogContext);
      final width = math.min(media.size.width - 48, 310.0);
      final keyboardOpen = media.viewInsets.bottom > 0;
      final topGap = math.max(media.padding.top + 24, 72.0);
      final bottomGap = keyboardOpen
          ? media.viewInsets.bottom + 16
          : math.max(media.padding.bottom + 24, 24.0);
      return Material(
        type: MaterialType.transparency,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(24, topGap, 24, bottomGap),
          child: Align(
            // iPhone Safari 聚焦输入框时会自行滚动画布；键盘态下固定上边距，
            // 防止弹窗被顶到状态栏下面。无键盘时仍保持近似居中。
            alignment: keyboardOpen ? Alignment.topCenter : Alignment.center,
            child: Container(
              key: const Key('星球名称弹窗卡片'),
              width: width,
              decoration: BoxDecoration(
                color: const Color(0xF8FFFDF8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                    child: Text(
                      heading,
                      textAlign: TextAlign.center,
                      style: _dlgStyle(
                        size: 20,
                        weight: FontWeight.w600,
                        color: const Color(0xFF3D332A),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: CupertinoTextField(
                      key: fieldKey,
                      controller: controller,
                      autofocus: true,
                      placeholder: hint,
                      // 提示语与输入内容都居中（左对齐时未输入的框显得空落）
                      textAlign: TextAlign.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE3D8C7)),
                      ),
                      style: _dlgStyle(
                        size: 16,
                        color: const Color(0xFF1A1A1A),
                      ),
                      placeholderStyle: _dlgStyle(
                        size: 16,
                        color: const Color(0x993D332A),
                      ),
                      onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
                    ),
                  ),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0x1F3D332A))),
                    ),
                    child: SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: Text(
                                '取消',
                                style: _dlgStyle(
                                  size: 18,
                                  color: const Color(0xFF8C4A63),
                                ),
                              ),
                            ),
                          ),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: Color(0x1F3D332A),
                          ),
                          Expanded(
                            child: CupertinoButton(
                              key: confirmKey,
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.of(
                                dialogContext,
                              ).pop(controller.text),
                              child: Text(
                                confirm,
                                style: _dlgStyle(
                                  size: 18,
                                  weight: FontWeight.w600,
                                  color: const Color(0xFF8C4A63),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return result.whenComplete(controller.dispose);
}
