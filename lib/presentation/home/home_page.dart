import 'dart:async';
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
import '../shared/quick_capture/quick_capture_layer.dart'
    show captureSheetOpenProvider;
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

/// 全局创作量（所有星球的章+节+灵感总数），驱动宇宙背景演化速度
final globalCreativeCountProvider = StreamProvider<int>(
  (ref) => ref.watch(novelRepositoryProvider).watchGlobalCreativeCount(),
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

/// 顶部创建标题只在星球完全回到最小态时出现，避免拖动/捏合起手时闪烁。
const kPlanetCreateTitleShowZoom = 1.001;

/// 捏合增益：手指张开比例的幂次。整屏最多张开约 1.6 倍，
/// 直接 1:1 映射够不到 3 倍上限、捏合"使不上劲"
const kPinchGain = 2.6;

/// 拖动转星球的俯仰上限（弧度）：别转到极点翻面
const kMaxPitch = math.pi / 2 * 0.92;

/// 星球放大/捏合期间锁住 PageView：双指缩放不会误翻页
/// （沿用魔毯 carpetDragging 的全局 ValueNotifier 惯例）
final planetZoomLock = ValueNotifier<bool>(false);

/// 顶部 Create Something 的显示状态：只跟随当前星球是否最小化，不跟随拖动锁页。
final planetCreateTitleVisible = ValueNotifier<bool>(true);

/// 任一星球场景出首帧就 +1：启动封面等它揭开（事件驱动，不再拍脑袋定时）
final planetSceneReadyTick = ValueNotifier<int>(0);

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

  _SharedPlanetSceneConfig? _sharedSceneConfig;
  bool _sharedSceneReady = false;
  String? _sharedSceneSnapshot;
  int _sharedSnapshotReq = 0;
  Completer<void>? _sharedSnapshotCompleter;
  Timer? _sceneRevealTimer;
  Timer? _sceneFallbackTimer;

  /// 启动封面：事件驱动揭开——等星球场景真正就绪（而非拍脑袋定时），
  /// 封面期间 iframe 初始化/贴图上传/星云编译全部做完，揭开即流畅。
  /// 只在冷启动出现一次；从魔树页返回不再盖（快照替身已兜住重建期）。
  bool _coverVisible = true;
  bool _coverGone = false; // 淡出动画结束后彻底摘除（星云层停渲染省电）
  bool _coverMinDone = false; // 最短展示时长已到（避免一闪而过）
  int _coverStartReadyTick = 0; // 只认本次首页启动之后的场景就绪信号
  Timer? _coverMinTimer;
  Timer? _coverMaxTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    planetCreateTitleVisible.value = true;
    _coverStartReadyTick = planetSceneReadyTick.value;
    planetSceneReadyTick.addListener(_onSceneReadyTick);
    // 最短 900ms：给封面一个体面的亮相；最长 4s：场景异常也不能永远盖着
    _coverMinTimer = Timer(const Duration(milliseconds: 900), () {
      _coverMinDone = true;
      _maybeRevealCover();
    });
    _coverMaxTimer = Timer(const Duration(seconds: 4), _revealCover);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precachePlanetStandIns();
    });
  }

  @override
  void dispose() {
    planetSceneReadyTick.removeListener(_onSceneReadyTick);
    _coverMinTimer?.cancel();
    _coverMaxTimer?.cancel();
    _sceneRevealTimer?.cancel();
    _sceneFallbackTimer?.cancel();
    final snapshotCompleter = _sharedSnapshotCompleter;
    if (snapshotCompleter != null && !snapshotCompleter.isCompleted) {
      snapshotCompleter.complete();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _onSceneReadyTick() => _maybeRevealCover();

  void _precachePlanetStandIns() {
    for (final planet in kPlanetTextures) {
      // 非 3D 回退主体用的等距圆柱贴图
      precacheImage(AssetImage('assets/textures/$planet.jpg'), context);
      // 3D 加载/切换期替身用的预渲染真身快照——预解码，切星球首帧即出
      precacheImage(
        AssetImage('assets/planet_scene/standins/$planet.png'),
        context,
      );
    }
  }

  /// 就绪条件：小说列表已加载，且（空宇宙 或 本次启动后的星球场景已出首帧）
  void _maybeRevealCover() {
    if (!_coverVisible || !_coverMinDone || !mounted) return;
    final novelsAsync = ref.read(novelsProvider);
    if (!novelsAsync.hasValue) return;
    final sceneOk =
        (novelsAsync.value?.isEmpty ?? false) ||
        planetSceneReadyTick.value > _coverStartReadyTick;
    if (sceneOk) _revealCover();
  }

  void _revealCover() {
    if (!mounted || !_coverVisible) return;
    _coverMaxTimer?.cancel();
    setState(() => _coverVisible = false);
  }

  void _dropStartupCover() {
    if (!mounted || _coverGone) return;
    _coverMinTimer?.cancel();
    _coverMaxTimer?.cancel();
    setState(() {
      _coverVisible = false;
      _coverGone = true;
    });
  }

  void _onSharedSceneConfig(_SharedPlanetSceneConfig config) {
    if (_sharedSceneConfig == config) return;
    // 换星球**不复位就绪**：共享场景原地换贴图（不重建 iframe），旧星球持续
    // 显示到新贴图就绪再一次性接管——全程活画面，无需静态替身介入。就绪标记
    // 只在真正冷启动（首个 config）/上下文异常时才为假，交给兜底定时器揭幕。
    final firstConfig = _sharedSceneConfig == null;
    setState(() => _sharedSceneConfig = config);
    if (firstConfig && !_sharedSceneReady) _armSceneRevealFallback();
  }

  Future<void> _awaitSnapshotBeforeRoute() async {
    if (!mounted ||
        !ref.read(advanced3DProvider) ||
        _sharedSceneConfig == null) {
      return;
    }
    final completer = Completer<void>();
    _sharedSnapshotCompleter = completer;
    setState(() => _sharedSnapshotReq++);
    await completer.future.timeout(
      const Duration(milliseconds: 90),
      onTimeout: () {},
    );
    if (identical(_sharedSnapshotCompleter, completer)) {
      _sharedSnapshotCompleter = null;
    }
  }

  void _scheduleSceneReveal() {
    _sceneFallbackTimer?.cancel();
    _sceneFallbackTimer = null;
    _sceneRevealTimer?.cancel();
    _sceneRevealTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      if (!_sharedSceneReady) {
        setState(() => _sharedSceneReady = true);
      }
      planetSceneReadyTick.value++;
    });
  }

  void _armSceneRevealFallback() {
    if (_sceneFallbackTimer != null) return;
    _sceneFallbackTimer = Timer(const Duration(milliseconds: 3000), () {
      _sceneFallbackTimer = null;
      if (!mounted || _sharedSceneReady || _sharedSceneConfig == null) return;
      setState(() => _sharedSceneReady = true);
      planetSceneReadyTick.value++;
    });
  }

  void _handleSharedSceneSnapshot(String snapshot) {
    if (mounted && snapshot != _sharedSceneSnapshot) {
      setState(() => _sharedSceneSnapshot = snapshot);
    }
    final completer = _sharedSnapshotCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
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
    final novelsAsync = ref.watch(novelsProvider);
    final novels = novelsAsync.value ?? const <Novel>[];
    final pool = ref.watch(inspirationPoolProvider).value ?? const [];
    final popupOpen = ref.watch(captureSheetOpenProvider);
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeCurrent && !popupOpen && !_coverGone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dropStartupCover());
    }
    // 小说列表加载完成也可能是揭开封面的最后一块拼图（空宇宙场景）
    if (_coverVisible && novelsAsync.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRevealCover());
    }

    // 删除当前页那颗星球后，PageView 不会回调 onPageChanged，_currentPage 会
    // 停在越界的旧下标——若仍拿它判 active，剩下的页( i=0 )反而非 active，不会
    // 把新星球配置发给共享 3D 场景，画面残留删除前那颗（表现为"地球变火星"）。
    // 故统一 clamp 出安全页码，作为"当前页 / active 判断"的唯一依据，并在越界时
    // 下一帧把控制器与 _currentPage 一并回正。
    final safePage = novels.isEmpty
        ? 0
        : _currentPage.clamp(0, novels.length - 1);
    if (_currentPage != safePage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _currentPage == safePage) return;
        if (_pageController.hasClients &&
            _pageController.page?.round() != safePage) {
          _pageController.jumpToPage(safePage);
        }
        setState(() => _currentPage = safePage);
      });
    }

    // 当前星球的创作量 → 星空亮度（无星球时最暗）
    final currentNovel = novels.isEmpty ? null : novels[safePage];
    final currentCount = currentNovel == null
        ? 0
        : ref.watch(creativeCountProvider(currentNovel.id)).value ?? 0;
    _scheduleCreatedNovelJump(novels);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 动态层跟随高级效果开关：测试/低端机回退纯静态照片。
          // 演化速度随全局创作量（所有星球的章+节+灵感）：越写越"快进"
          Starfield(
            brightness: starBrightness(currentCount),
            animated: ref.watch(advanced3DProvider),
            evolveSpeed: nebulaEvolveSpeed(
              ref.watch(globalCreativeCountProvider).value ?? 0,
            ),
          ),
          if (novels.isNotEmpty && ref.watch(advanced3DProvider))
            _SharedPlanetSceneLayer(
              config: _sharedSceneConfig,
              visible: routeCurrent || popupOpen,
              snapshotRequestId: _sharedSnapshotReq,
              onReady: _scheduleSceneReveal,
              onSnapshot: _handleSharedSceneSnapshot,
            ),
          if (novels.isEmpty)
            // 空宇宙：邀请创建第一颗星球。字体与全 App 统一——
            // 中文用霞鹜文楷（正文体），"Create Something" 用品牌衬线斜体
            Center(
              child: Text.rich(
                const TextSpan(
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontFamily: 'LXGWWenKai',
                    height: 1.6,
                  ),
                  children: [
                    TextSpan(text: '宇宙一片寂静\n点上方 '),
                    TextSpan(
                      // 与顶部品牌标题同字体（EasyCreateBrand 斜体），
                      // 只借字形，颜色/字号继承本句样式
                      text: 'Create Something',
                      style: TextStyle(
                        fontFamily: 'EasyCreateBrand',
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: ' 点亮第一颗星球'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            // 一页一星球，左右滑切换小说
            ValueListenableBuilder<bool>(
              valueListenable: planetZoomLock,
              builder: (context, locked, _) => PageView.builder(
                controller: _pageController,
                itemCount: novels.length,
                allowImplicitScrolling: false,
                // 捏合放大星球期间禁翻页（否则双指会被识别成滑动换书）
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                // 切星球**不复位就绪、不盖替身**：共享场景原地换贴图，旧星球
                // 持续显示到新贴图就绪再一次性接管（planet_scene/index.html:setPlanet）。
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
                    // active 用回正后的 safePage：删掉当前页后，剩余页立刻成为
                    // active 并把新星球配置发给共享场景，杜绝残留删除前那颗。
                    active: i == safePage,
                    sharedSceneReady: _sharedSceneReady,
                    sharedSceneSnapshot: _sharedSceneSnapshot,
                    onSharedSceneConfig: _onSharedSceneConfig,
                    onRequestSnapshotBeforeRoute: _awaitSnapshotBeforeRoute,
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
                // 只在当前星球完全最小化时显示；拖动旋转/双指刚按下不再误闪。
                child: ValueListenableBuilder<bool>(
                  valueListenable: planetCreateTitleVisible,
                  builder: (context, visible, child) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: visible ? 1 : 0,
                    child: IgnorePointer(ignoring: !visible, child: child),
                  ),
                  child: GestureDetector(
                    key: const Key('创建新星球标题'),
                    onTap: _createNovel,
                    child: Text(
                      'Create Something',
                      style: _brandTitleStyle(fontSize: 26),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 淡出结束即彻底摘除（封面的星云层停渲染，不再烧 GPU）
          if (!_coverGone)
            _HomeLoadingCover(
              visible: _coverVisible,
              onHidden: () {
                if (mounted) setState(() => _coverGone = true);
              },
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

/// 启动封面：静态深空照片 + "Easy Create" 品牌标题。
/// 这里不能再复用动态星云 shader：慢设备上封面本身会参与 GPU 争抢，
/// 反而把后台加载过程暴露给用户。
class _HomeLoadingCover extends StatelessWidget {
  const _HomeLoadingCover({required this.visible, required this.onHidden});

  final bool visible;

  /// 淡出动画结束（宿主借此把封面整个摘除，停掉其星云渲染）
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        opacity: visible ? 1 : 0,
        onEnd: () {
          if (!visible) onHidden();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/textures/starfield_4.jpg', fit: BoxFit.cover),
            // 与 web/index.html 的 HTML 启动屏同款遮罩：
            // 引擎交接（HTML 封面 → Flutter 画面）瞬间无明暗跳变，观感一段式
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    Color(0x480B1230),
                    Color(0x85060A1D),
                    Color(0xD102040B),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Easy Create',
                  style: _brandTitleStyle(fontSize: 34, letterSpacing: 1.2),
                ),
                const SizedBox(height: 14),
                const Text(
                  '正在点亮你的宇宙…',
                  style: TextStyle(
                    color: Color(0x8FFFFFFF),
                    fontSize: 13,
                    fontFamily: 'LXGWWenKai',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedPlanetSceneConfig {
  const _SharedPlanetSceneConfig({
    required this.novelId,
    required this.planet,
    required this.spin,
    required this.diameter,
    required this.stageScale,
    required this.zoom,
    required this.yaw,
    required this.pitch,
    required this.autoPrewarm,
  });

  final int novelId;
  final String planet;
  final double spin;
  final double diameter;
  final double stageScale;
  final double zoom;
  final double yaw;
  final double pitch;
  final bool autoPrewarm;

  @override
  bool operator ==(Object other) =>
      other is _SharedPlanetSceneConfig &&
      other.novelId == novelId &&
      other.planet == planet &&
      other.spin == spin &&
      other.diameter == diameter &&
      other.stageScale == stageScale &&
      other.zoom == zoom &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.autoPrewarm == autoPrewarm;

  @override
  int get hashCode => Object.hash(
    novelId,
    planet,
    spin,
    diameter,
    stageScale,
    zoom,
    yaw,
    pitch,
    autoPrewarm,
  );
}

class _SharedPlanetSceneLayer extends StatelessWidget {
  const _SharedPlanetSceneLayer({
    required this.config,
    required this.visible,
    required this.snapshotRequestId,
    required this.onReady,
    required this.onSnapshot,
  });

  final _SharedPlanetSceneConfig? config;
  final bool visible;
  final int snapshotRequestId;
  final VoidCallback onReady;
  final ValueChanged<String> onSnapshot;

  @override
  Widget build(BuildContext context) {
    final config = this.config;
    if (config == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -25),
          child: OverflowBox(
            maxWidth: config.diameter,
            maxHeight: config.diameter,
            child: PlanetScene(
              key: const ValueKey('shared-planet-scene'),
              planet: config.planet,
              spin: config.spin,
              diameter: config.diameter,
              stageScale: config.stageScale,
              zoom: config.zoom,
              yaw: config.yaw,
              pitch: config.pitch,
              autoPrewarm: config.autoPrewarm,
              active: true,
              visible: visible,
              snapshotRequestId: snapshotRequestId,
              onReady: onReady,
              onSnapshot: onSnapshot,
            ),
          ),
        ),
      ),
    );
  }
}

/// 单颗星球页：星球 + 环绕灵感 + 书名，点星球进大纲页
class _PlanetPage extends ConsumerStatefulWidget {
  const _PlanetPage({
    super.key,
    required this.novel,
    required this.pool,
    required this.active,
    required this.sharedSceneReady,
    required this.sharedSceneSnapshot,
    required this.onSharedSceneConfig,
    required this.onRequestSnapshotBeforeRoute,
  });

  final Novel novel;
  final List<Inspiration> pool;

  /// 是否为当前正在看的页（决定谁渲染、谁接管星空亮度/手势）
  final bool active;

  /// 是否保活场景：当前页 或 最近看过的星球。为真则场景常驻树中——
  /// 非当前页只暂停+隐藏 iframe（不销毁），切回即刻恢复，无冷启动窗口。
  final bool sharedSceneReady;
  final String? sharedSceneSnapshot;
  final ValueChanged<_SharedPlanetSceneConfig> onSharedSceneConfig;
  final Future<void> Function() onRequestSnapshotBeforeRoute;

  @override
  ConsumerState<_PlanetPage> createState() => _PlanetPageState();
}

class _PlanetPageState extends ConsumerState<_PlanetPage>
    with SingleTickerProviderStateMixin {
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

  /// 环绕灵感只需要最近几条；缓存后避免旋转 setState 时每帧复制并排序整个灵感池。
  List<Inspiration> _cachedOrbitItems = const [];

  /// 星球画面区域（用于判断手指是否落在球上）
  final _planetKey = GlobalKey();

  bool get _zoomed => _zoom > kPlanetTitleHideZoom;

  bool get _canDeleteByLongPress =>
      _zoom <= kPlanetCreateTitleShowZoom && _pinchStartDist <= 0;

  @override
  void initState() {
    super.initState();
    _glideTicker = createTicker(_onGlideTick);
    _refreshCachedOrbitItems();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCreateTitleVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant _PlanetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pool, widget.pool)) {
      _refreshCachedOrbitItems();
    }
    if (oldWidget.active != widget.active && widget.active) {
      _syncCreateTitleVisibility();
    }
  }

  void _refreshCachedOrbitItems() {
    final sorted = List<Inspiration>.of(widget.pool)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cachedOrbitItems = sorted
        .take(OrbitingInspirations.maxItems)
        .toList(growable: false);
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

  void _syncCreateTitleVisibility() {
    if (!widget.active) return;
    planetCreateTitleVisible.value = _zoom <= kPlanetCreateTitleShowZoom;
  }

  void _resetZoom() {
    setState(() => _zoom = 1);
    _syncCreateTitleVisibility();
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
    if ((next - _zoom).abs() > 0.002) {
      setState(() => _zoom = next);
      _syncCreateTitleVisibility();
    }
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
    _syncCreateTitleVisibility();
    _syncPageLock();
  }

  Future<void> _awaitSnapshotBeforeRoute() async {
    await widget.onRequestSnapshotBeforeRoute();
  }

  Future<void> _openOutline(Novel novel) async {
    // 进大纲前抓一帧快照，供极端情况下（场景被暂停后仍需替身）兜底遮罩。
    await _awaitSnapshotBeforeRoute();
    if (!mounted) return;
    // 关键：**不**复位 _sceneReady。iframe 只是被隐藏+暂停（planet_scene_web），
    // 场景全程存活；返回时 _sceneReady 仍为真 → 替身恒透明 → 直接露出活场景，
    // 零重建、零 1 秒加载、零黑帧（旧实现每次导航都拆重建才需要复位+替身）。
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OutlinePage(novelId: novel.id, title: novel.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novel = widget.novel;
    final count = ref.watch(creativeCountProvider(novel.id)).value ?? 0;
    final use3D = ref.watch(advanced3DProvider);
    // 着色器资源：非 3D 模式是主体；3D 模式给替身用——首次加载/切换时
    // 替身显**着色器球体**（球面投影+光照）而非平面裁剪贴图，消除"2D 贴纸突变"。
    // 非 3D 回退才需着色器贴图；3D 模式替身改用预渲染真身快照，不再加载着色器资源
    final assets = use3D
        ? null
        : ref.watch(planetAssetsProvider(novel.planet)).value;
    final diameter = MediaQuery.sizeOf(context).width * 0.62;
    final ready = use3D || assets != null;

    Widget planetBody() {
      if (use3D) {
        final sceneDiameter = novel.planet == 'saturn'
            ? diameter * 1.4
            : diameter;
        if (widget.active) {
          final config = _SharedPlanetSceneConfig(
            novelId: novel.id,
            planet: novel.planet,
            spin: planetSpin(count),
            diameter: sceneDiameter * kPlanetSceneStageScale,
            stageScale: kPlanetSceneStageScale,
            zoom: _zoom,
            yaw: _spin.yaw,
            pitch: _spin.pitch,
            autoPrewarm: true,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.active) widget.onSharedSceneConfig(config);
          });
        }
        // 替身只在共享场景**未就绪**（真正冷启动/上下文异常兜底）时露出；
        // 正常切星球场景常就绪 → 替身恒透明，不参与切换（原地换贴图不露替身）。
        final standIn = AnimatedOpacity(
          duration: const Duration(milliseconds: 350),
          opacity: widget.sharedSceneReady ? 0 : 1,
          child: _PlanetStandIn(
            diameter: sceneDiameter,
            planet: novel.planet,
            snapshotDataUrl: widget.sharedSceneSnapshot,
          ),
        );
        return SizedBox.square(
          key: _planetKey,
          dimension: sceneDiameter,
          child: Center(child: standIn),
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
            onTap: !ready ? null : () => _openOutline(novel),
            onLongPress: () {
              if (!_canDeleteByLongPress) return;
              _confirmDeleteNovel(context, ref);
            },
            child: !ready
                // 占位也要带 key：否则星球未就绪时"手指是否在球上"恒为否
                ? SizedBox.square(key: _planetKey, dimension: diameter)
                : OrbitingInspirations(
                    // 环绕取"最近几条"：缓存按创建时间倒序，旋转 setState 时不再重排全池。
                    items: _cachedOrbitItems,
                    orbitWidth: diameter * 1.5,
                    enabled: !_zoomed && (!use3D || widget.sharedSceneReady),
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

/// 星球替身：仅在**真正首次加载/切换**（无活场景可复用）时占位。
///
/// 分层（自下而上，均不透明、均非平面裁剪，杜绝"2D 贴纸"与"透明缝黑帧"）：
/// 1. 底 base = 该星球的**预渲染真身快照** `standins/$planet.png`（three.js 同款
///    一帧：大气辉光/海面高光/云层，stage=3 同款取景）——与真实场景视觉一致，
///    加载/切换期不再有"平面/简球 → 精球"的 2D 突变。资源缺失才退到深空渐变球。
/// 2. 若另有运行时低清快照 [snapshotDataUrl]（更贴合当前角度），叠在底之上，
///    **解码完成才淡入**，解码期间露出底快照，绝不透出下方黑 iframe。
class _PlanetStandIn extends StatelessWidget {
  const _PlanetStandIn({
    required this.diameter,
    required this.planet,
    this.snapshotDataUrl,
  });

  final double diameter;

  /// 行星名（earth/mars/venus/jupiter/saturn），决定用哪张预渲染真身快照
  final String planet;
  final String? snapshotDataUrl;

  @override
  Widget build(BuildContext context) {
    final full = diameter * kPlanetSceneStageScale;
    // 底：预渲染真身快照，取景与 three.js（stage=3）一致，直接铺满同款舞台框
    final base = Image.asset(
      'assets/planet_scene/standins/$planet.png',
      width: full,
      height: full,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => SizedBox.square(
        dimension: full,
        child: Center(child: _gradientSphere()),
      ),
    );
    final snapshot = snapshotDataUrl;
    final content = snapshot == null
        ? base
        : Stack(
            alignment: Alignment.center,
            children: [
              base,
              Image.network(
                snapshot,
                width: full,
                height: full,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                // 解码完成前 frame==null → 透明，露出底快照；完成后淡入
                frameBuilder: (context, child, frame, wasSync) =>
                    AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: child,
                    ),
              ),
            ],
          );
    return IgnorePointer(
      child: OverflowBox(maxWidth: full, maxHeight: full, child: content),
    );
  }

  /// 无着色器资源时的兜底：深空渐变球（非平面裁剪、不透明）
  Widget _gradientSphere() => SizedBox.square(
    dimension: diameter,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 0.95,
          colors: [Color(0xFF2A4A78), Color(0xFF14264A), Color(0xFF060D1E)],
          stops: [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: Color(0x665D9DFF), blurRadius: 32, spreadRadius: 2),
        ],
      ),
    ),
  );
}

TextStyle _brandTitleStyle({
  required double fontSize,
  double letterSpacing = 1.0,
}) => TextStyle(
  color: const Color(0xF5FFFFFF),
  fontSize: fontSize,
  fontFamily: 'EasyCreateBrand',
  fontWeight: FontWeight.w600,
  fontStyle: FontStyle.italic,
  letterSpacing: letterSpacing,
);

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
