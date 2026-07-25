import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 3D 星球缩放的架构护栏（源码级断言，不依赖平台视图）
String functionBody(String source, String name) {
  final start = source.indexOf('function $name(');
  expect(start, greaterThanOrEqualTo(0), reason: '找不到函数 $name');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i += 1) {
    final ch = source[i];
    if (ch == '{') depth += 1;
    if (ch == '}') depth -= 1;
    if (depth == 0) return source.substring(open + 1, i);
  }
  fail('函数 $name 没有闭合');
}

void main() {
  final webWrapper = File(
    'lib/presentation/home/planet_scene/planet_scene_web.dart',
  ).readAsStringSync();
  final ioWrapper = File(
    'lib/presentation/home/planet_scene/planet_scene_io.dart',
  ).readAsStringSync();
  final homePage = File(
    'lib/presentation/home/home_page.dart',
  ).readAsStringSync();
  final sceneHtml = File('assets/planet_scene/index.html').readAsStringSync();

  test('Web 端不得强制 lod=hi：iPhone 首次换档上传 8192(约134MB) 明显掉帧', () {
    // 只匹配 URL 参数形态（&lod=hi），不误伤解释历史的注释
    expect(webWrapper, isNot(contains('&lod=hi')));
    // 移动 App 壳仍显式 mid
    expect(ioWrapper, contains('lod=mid'));
  });

  test('场景首帧就绪信号：宿主用星球替身盖住加载/重建期（返回空白的修复）', () {
    expect(
      sceneHtml,
      contains('sceneReady:'),
      reason: 'iframe 经 parent.postMessage 上报',
    );
    expect(webWrapper, contains('&token='), reason: '多实例 token 区分');
    expect(webWrapper, contains('sceneReady:\$_seq'));
    expect(ioWrapper, contains('"ready":true'));
    expect(homePage, contains('_PlanetStandIn'), reason: '光晕替身');
    expect(homePage, contains('_sharedSceneReady'));
  });

  test('场景就绪必须等待基础地表贴图加载，不能先露黑色空材质球', () {
    expect(sceneHtml, contains('baseTextureReady'));
    expect(sceneHtml, contains('srgb(pcfg.map, true)'));
    expect(sceneHtml, contains('if (!baseTextureReady) return;'));
  });

  test('场景快照通道仍在（sendSnapshot 已定义），但替身不再叠这张低清图', () {
    expect(sceneHtml, contains('function sendSnapshot'));
    expect(sceneHtml, contains("toDataURL('image/png')"));
    expect(webWrapper, contains('sceneSnapshot:\$_seq'));
    expect(homePage, contains('_handleSharedSceneSnapshot'));
    // 运行时快照最长边仅 480px 且全局共用一张（拍自初始星球，通常是地球），
    // 叠在替身上会被拉伸成"很糊的地球"、切土星更被撑大（用户实测）。已移除：
    // 替身只用 standins/$planet.png（960px、永远是本页正确星球）。
    expect(
      homePage,
      isNot(contains('Image.network')),
      reason: '替身不得再叠运行时低清快照，否则切星球会露出很糊的错星球',
    );
    expect(homePage, isNot(contains('snapshotDataUrl')));
  });

  test('启动封面：Easy Create 标题 + 静态同款封面，事件驱动揭开', () {
    expect(homePage, contains('_HomeLoadingCover'));
    expect(homePage, contains("'Easy Create'"), reason: '封面标题为品牌名');
    expect(
      homePage,
      contains("Image.asset('assets/textures/starfield_4.jpg'"),
      reason: '启动遮挡不能再依赖动态星云 shader，否则慢机仍会看到后台加载/卡顿',
    );
    // 事件驱动：等星球场景首帧（planetSceneReadyTick）才揭开，
    // 拍脑袋定时揭开会正撞上场景初始化 → 揭开瞬间卡顿（用户实测）
    expect(homePage, contains('planetSceneReadyTick'));
    expect(homePage, contains('_coverStartReadyTick'));
    expect(homePage, contains('_coverMinDone'));
    expect(homePage, contains('_maybeRevealCover'));
    // 兜底：场景异常也不能永远盖着
    expect(homePage, contains('_coverMaxTimer'));
    // 揭开后彻底摘除（封面星云停渲染省电）
    expect(homePage, contains('_coverGone'));
  });

  test('从魔树返回首页不再显示封面（快照替身已兜住重建期）', () {
    expect(homePage, isNot(contains('_lastRouteCurrent')));
    expect(homePage, isNot(contains('_showCoverFor')));
    expect(homePage, contains('_dropStartupCover'));
    expect(homePage, contains('!routeCurrent && !popupOpen && !_coverGone'));
  });

  test('HTML 启动屏与 Flutter 封面同款（消掉"两段式"观感）', () {
    final bootHtml = File('web/index.html').readAsStringSync();
    expect(bootHtml, contains('Easy Create'), reason: '标题须与 Flutter 封面一致');
    expect(bootHtml, contains('正在点亮你的宇宙'));
    expect(
      bootHtml,
      contains('starfield_4.jpg'),
      reason: 'HTML 与 Flutter 封面共用同一张图',
    );
    expect(bootHtml, contains('flutter-first-frame'), reason: 'Flutter 首帧后交接');
    expect(
      bootHtml,
      contains('bootMinVisibleMs'),
      reason: 'HTML 封面要多盖住 Flutter/场景启动期，不能第一帧就退造成两段式',
    );
    expect(
      bootHtml,
      contains('bootMaxVisibleMs'),
      reason: '场景异常时仍要兜底消失，不能永久遮住',
    );
    expect(
      bootHtml,
      isNot(contains('Create Something')),
      reason: '旧文案会让两段封面内容跳变',
    );
  });

  test('性能护栏：不做周期快照、非当前页暂停渲染', () {
    // toDataURL 的 PNG 编码在主线程，周期快照是固定 jank 源（用户实测"会变卡"）
    expect(sceneHtml, isNot(contains('setInterval(sendSnapshot')));
    expect(sceneHtml, contains('m.snapshot'), reason: '快照改为宿主请求式');
    // 滑过的页 keepAlive 后 iframe 仍后台渲染，多球常驻越用越卡
    expect(sceneHtml, contains('m.render'), reason: '渲染暂停通道');
    expect(homePage, contains('active: true'));
    expect(homePage, contains('_sharedSnapshotReq++'), reason: '进大纲前拍最新快照');
    expect(ioWrapper, contains("'pauseRender()'"));
  });

  test('Web 护栏：首页只保留一个共享星球场景，禁止多 WebGL 场景保活', () {
    expect(
      homePage,
      contains('allowImplicitScrolling: false'),
      reason: 'iPhone Safari 连续滑动时不能预构建相邻 3D iframe，否则多个 WebGL 场景会挤爆页面进程',
    );
    // 保活集有上限：只留最近 N 颗，太久没看的星球才销毁释放 WebGL
    expect(
      homePage,
      isNot(contains('static const _kMaxAliveScenes')),
      reason: '保活的 3D 场景数必须封顶，否则多颗星球常驻会挤爆 iPhone 页面进程',
    );
    expect(homePage, isNot(contains('_aliveNovelIds')));
    // keepAlive/挂载看 keptAlive（当前页 + 最近看过），不再只看 active
    expect(
      homePage,
      isNot(contains('bool get wantKeepAlive => widget.keptAlive')),
    );
    expect(
      homePage,
      isNot(contains('final sceneMounted = use3D && widget.keptAlive')),
      reason: '保活集内的页（含非当前）都挂载真实 3D 场景，切回即刻恢复',
    );
  });

  test('Web 护栏：销毁 PlanetScene 时主动释放 iframe/WebGL 页面', () {
    expect(webWrapper, contains("src = 'about:blank'"));
    expect(webWrapper, contains('_iframe?.remove()'));
    expect(sceneHtml, contains('function disposeScene()'));
    expect(sceneHtml, contains('renderer.dispose()'));
    expect(sceneHtml, contains('cancelAnimationFrame'));
  });

  test('Web 护栏：共享场景支持切星球消息并处理 WebGL 上下文丢失', () {
    expect(webWrapper, contains('old.planet != widget.planet'));
    expect(webWrapper, contains("'planet': widget.planet"));
    expect(sceneHtml, contains('window.setPlanet'));
    expect(sceneHtml, contains('webglcontextlost'));
    expect(sceneHtml, contains('webglcontextrestored'));
  });

  test('性能护栏：旋转重建路径不再每帧复制排序灵感池', () {
    expect(homePage, contains('items: _cachedOrbitItems'));
    expect(homePage, contains('_refreshCachedOrbitItems'));
    expect(homePage, contains('didUpdateWidget'));
    expect(homePage, isNot(contains('items: [...widget.pool]')));
  });

  test('Web 端路由被覆盖时隐藏+暂停 iframe（不销毁，返回即露活场景）', () {
    // 彻底方案（2026-07-11）：不再随导航销毁 platform view。进大纲时把 iframe
    // display:none 让平台视图退出合成——既规避"驻留非当前路由 → CanvasKit 丢
    // canvas → 大纲整页白"，又保留场景存活，返回即恢复，零重建/黑帧。
    expect(homePage, contains('ModalRoute.of(context)?.isCurrent'));
    // 保活页始终挂载场景，可见性交给 sceneVisible（当前页且首页在顶才显示）
    expect(homePage, contains('visible: routeCurrent || popupOpen'));
    // web 端据 visible 切 display，而非移出树/销毁
    expect(
      webWrapper,
      contains("_iframe?.style.display = widget.visible ? '' : 'none'"),
    );
    // 不再依赖 kIsWeb 分支做导航销毁
    expect(homePage, isNot(contains('!kIsWeb || routeCurrent')));
  });

  test('切换星球前后只预热相邻纹理，不保活多套 WebGL 场景', () {
    expect(
      homePage,
      contains('_neighborPlanetsFor'),
      reason: '首页应按当前页计算左右相邻星球，用于单场景内的纹理预热',
    );
    expect(
      homePage,
      contains('prewarmPlanets: _neighborPlanetsFor(novels, safePage)'),
    );
    expect(webWrapper, contains('final List<String> prewarmPlanets'));
    expect(ioWrapper, contains('final List<String> prewarmPlanets'));
    expect(webWrapper, contains("'prewarmPlanets': widget.prewarmPlanets"));
    expect(ioWrapper, contains('prewarmPlanets'));
    expect(sceneHtml, contains('planetTextureCache'));
    expect(sceneHtml, contains('prewarmPlanets'));
    expect(sceneHtml, contains('preloadPlanetTextureBundle'));
    expect(
      sceneHtml,
      contains('createTextureChunked'),
      reason: '预加载须在 loadTexAsync 内完成解码+分块 GPU 上传，到手即可用',
    );
    expect(sceneHtml, contains('trimPlanetTextureCache'));
  });

  test('高清 LOD 异步回写防串台：完成时校验仍是发起加载的那颗星球', () {
    // 切星球不会取消在途的 ensureHiTexture：旧星球（如火星）的高清贴图解码/
    // 上传完成太晚时，若只查 disposed 就回写全局 hiTex，当前星球（地球）
    // 放大就会贴上火星地表（实测复现）。完成时必须校验归属再回写。
    expect(sceneHtml, contains('const planetAtStart = planetName'));
    expect(sceneHtml, contains('planetName !== planetAtStart'));
    expect(
      sceneHtml,
      contains('if (planetName === planetAtStart) hiLoading = false'),
      reason: '旧任务收尾不得清掉新星球加载的在途标记，否则会并发两份高清加载',
    );
  });

  test('切球收尾不冻主线程：静默期调度 + 不强制重分配画布 + 旧贴图回存缓存', () {
    // Safari 无 requestIdleCallback，旧退化 setTimeout(task, 350) 是固定延时，
    // 常正撞滑页收尾动画（星球+星空+书名一起冻 0.5s，用户 iPhone 实测）
    expect(sceneHtml, contains('lastActivityTs'));
    expect(sceneHtml, contains('noteActivity'));
    expect(sceneHtml, isNot(contains('setTimeout(task, 350)')));
    // 切球只重算镜头距离；setSize 即使尺寸没变也会重分配 drawing buffer
    expect(
      sceneHtml,
      isNot(contains('lastW = 0; lastH = 0; updateFraming();')),
    );
    // 大贴图分块上传：一次性 texImage2D 喂 33~75MB 会冻主线程 150~400ms
    expect(sceneHtml, contains('copyTextureToTexture'));
    expect(sceneHtml, contains('renderer.initTexture'));
    expect(
      sceneHtml,
      isNot(contains('warmTextureOnGpu')),
      reason: '1×1 渲染式整张预热（仍是整张上传）已被分块上传取代',
    );
    // 旧星球贴图回存缓存（GPU 常驻），杜绝来回滑"扔掉→重新下载解码上传"
    expect(sceneHtml, contains('prevBundle'));
    expect(sceneHtml, contains('unmountPlanet(old, true)'));
  });

  test('切星球是前台上传：不被首页自转的活动卡在静默窗口外', () {
    // 用户实测：新建第 6 颗（地球，5 张重贴图）显示成上一颗，进出大纲才刷新。
    // 根因是切球贴图上传走后台"静默期才传"，首页星球持续自转刷新
    // lastActivityTs，静默窗口迟迟不来 → 上传卡很多秒。切球必须走前台通道。
    expect(sceneHtml, contains('function nextGpuUploadSlot(foreground)'));
    expect(
      sceneHtml,
      contains('preloadPlanetTextureBundle(name, true, !full)'),
      reason: 'takePlanetTextureBundle（切球）必须以 foreground=true 上传（滑页只基础相）',
    );
    // 前台通道只等下一帧、不等静默
    expect(sceneHtml, contains('foreground ? nextFrameTick : waitForUploadWindow'));
  });

  test('切球分两相：基础球前台先出，细节贴图后台补挂', () {
    // 地球 5 张贴图约 67MB 全走前台通道会和滑页动画抢帧（用户实测切换卡顿）。
    // 只有底图（+土星环）走前台，normal/specular/云层/夜光留到基础球出画面后
    // 由 attachPlanetDetails 以 foreground=false 补齐。
    expect(sceneHtml, contains('function loadPlanetTextureBundle(pcfg, foreground, baseOnly)'));
    expect(
      sceneHtml,
      contains('if (!baseOnly && pcfg.normal)'),
      reason: '基础相只上传底图，细节贴图必须被 baseOnly 跳过',
    );
    expect(sceneHtml, contains('function attachPlanetDetails(name, pcfg)'));
    expect(
      sceneHtml,
      contains('attachPlanetDetails(nextName, nextCfg)'),
      reason: '换星球事务收尾必须触发细节相补挂',
    );
    final detailBody = functionBody(sceneHtml, 'attachPlanetDetails');
    expect(
      detailBody,
      contains('loadTexAsync(pcfg.normal, false, false)'),
      reason: '细节相走后台通道（foreground=false），不与滑动动画抢帧',
    );
    expect(
      detailBody,
      contains('planetName !== name'),
      reason: '补挂前须校验仍是同一颗星球，否则丢弃（防串台）',
    );
    expect(
      detailBody,
      contains('!planetMat.normalMap'),
      reason: '缓存里已带全套细节时不得重复加载',
    );
  });

  test('换星球推迟到滑页落定后：贴图上传不与 PageView 动画抢主线程', () {
    // PageView 的 onPageChanged 在动画中途（越过半页）就回调，此刻换星球会让
    // 解码/上传和剩余滑动动画抢同一条主线程（用户实测"星球之间切换卡顿"）。
    expect(homePage, contains('bool _pageSettling = false'));
    expect(homePage, contains('_deferredSceneConfig'));
    expect(homePage, contains('bool _onPageScroll(ScrollNotification n)'));
    expect(
      homePage,
      contains('NotificationListener<ScrollNotification>'),
      reason: 'PageView 须被滚动通知监听包裹，才能识别滑动起止',
    );
    final onConfig = homePage.substring(
      homePage.indexOf('void _onSharedSceneConfig('),
      homePage.indexOf('void _applySharedSceneConfig('),
    );
    expect(
      onConfig,
      contains('current.planet != config.planet'),
      reason: '只推迟"换星球"，同一颗球内的缩放/旋转仍即时下发',
    );
    final flush = homePage.substring(
      homePage.indexOf('bool _onPageScroll('),
      homePage.length,
    );
    expect(flush, contains('ScrollEndNotification'));
    expect(
      homePage,
      contains('_deferredSceneTimer ??= Timer('),
      reason: '滚动结束通知万一没来也要兜底补发，不能把星球永远卡住',
    );
  });

  test('新建星球时复位就绪：让正确星球/正确尺寸的替身盖住加载窗口', () {
    // 新建用 jumpToPage 瞬跳新页，Flutter 容器立刻变新星球尺寸（土星 1.4×），
    // 但共享场景仍渲染上一颗星球贴图 → 露出"放大的金星/缩小的土星"。新建时须复位
    // _sharedSceneReady，让 _PlanetStandIn（正确星球预渲染快照）不透明盖住加载窗口。
    final jump = homePage.substring(
      homePage.indexOf('void _scheduleCreatedNovelJump('),
      homePage.indexOf('/// 启动封面：静态深空照片'),
    );
    expect(
      jump,
      contains('_sharedSceneReady = false'),
      reason: '新建跳页须复位就绪，替身才会盖住上一颗星球的加载窗口',
    );
    expect(
      jump,
      contains('_armSceneRevealFallback()'),
      reason: '新星球场景万一不发 planetReady 也要兜底揭幕，替身不永久停留',
    );
    // 揭幕后清标记：否则之后滑页回该星球会重走前台全量、又在滑动里卡顿
    final ready = homePage.substring(
      homePage.indexOf('void _onPlanetSceneReady('),
      homePage.indexOf('void _precachePlanetStandIns('),
    );
    expect(ready, contains('_immediateDetailNovelId = null'));
  });

  test('新建星球走整包前台一次上传：接管即全清，消除"低清→高清"', () {
    // 用户要求新建时一步到位。创建是 jumpToPage、无滑页动画，可整包前台上传，
    // 不再走"底图前台 + 细节后台"两相（那是为保护滑动帧而设，滑页仍保留）。
    expect(homePage, contains('int? _immediateDetailNovelId'));
    expect(
      homePage,
      contains('fullDetail: novel.id == widget.immediateDetailNovelId'),
      reason: '仅刚新建的那颗星球 config 带 fullDetail=true',
    );
    expect(homePage, contains('fullDetail: config.fullDetail'));
    // 两端场景壳都把 fullDetail 经换星球消息里的 immediate 下发
    expect(webWrapper, contains('final bool fullDetail'));
    expect(webWrapper, contains("'immediate': widget.fullDetail"));
    expect(ioWrapper, contains('final bool fullDetail'));
    expect(ioWrapper, contains('immediate:\${widget.fullDetail}'));
    // 场景侧：immediate 走整包前台（takePlanetTextureBundle 的 full=true）
    expect(sceneHtml, contains('function takePlanetTextureBundle(name, full)'));
    expect(
      sceneHtml,
      contains('const immediate = !!(state && state.immediate)'),
      reason: 'setPlanet 须从宿主消息 state.immediate 读取整包前台标志',
    );
    expect(sceneHtml, contains('takePlanetTextureBundle(nextName, immediate)'));
  });

  test('揭幕只认当前页星球：串行换球滞后时替身不淡出到错星球', () {
    // 根因（用户实测"新建先出地球 / 后面还出小土星"）：共享场景是串行换球队列，
    // 快速新建时滞后 1~2 颗；旧实现见任一 planetReady 就揭幕，替身在场景仍停在
    // 滞后旧星球时淡出，露出错星球。修复：ready 信号带回已接管星球名，宿主只在
    // 场景真正换到当前页星球时才揭幕。
    // 1) 场景就绪信号必须带星球名
    expect(sceneHtml, contains("'planetReady:' + (params.get('token') || '') + ':' + planetName"));
    expect(sceneHtml, contains("'sceneReady:' + (params.get('token') || '') + ':' + planetName"));
    expect(sceneHtml, contains('ready: true, planet: planetName'));
    // 2) web 壳按前缀解析出星球名回传（onReady 改为 ValueChanged<String>）
    expect(webWrapper, contains('ValueChanged<String>? onReady'));
    expect(webWrapper, contains("'sceneReady:\$_seq:'"));
    expect(webWrapper, contains("'planetReady:\$_seq:'"));
    // 3) io 壳从 JSON 里取 planet 回传
    expect(ioWrapper, contains('ValueChanged<String>? onReady'));
    expect(ioWrapper, contains("decoded['planet']"));
    // 4) 宿主只在就绪星球 == 当前页星球时才揭幕
    final onReady = homePage.substring(
      homePage.indexOf('void _onPlanetSceneReady('),
      homePage.indexOf('void _precachePlanetStandIns('),
    );
    expect(onReady, contains('void _onPlanetSceneReady(String readyPlanet)'));
    expect(
      onReady,
      contains('if (want != null && readyPlanet != want) return;'),
      reason: '就绪星球与当前页星球不符（场景滞后）时不得揭幕，替身继续盖',
    );
  });

  test('左右滑动切星球也盖替身：滑到不同星球页复位就绪，避免先闪错星球+大小跳', () {
    // 用户实测：不止新建，左右滑动 3→4、4→5 也"先闪错星球 + 大小/位置跳"。
    // 根因同新建——共享场景串行换球要 ~1s，期间仍显示上一颗（且被塞进新页尺寸框）。
    // onPageChanged 落到不同星球页时必须复位 _sharedSceneReady，让该页替身盖住，
    // 揭幕仍只认场景换到该页星球（planetReady 匹配，与新建同一套机制）。
    final onPageChanged = homePage.substring(
      homePage.indexOf('onPageChanged: (i) => setState(() {'),
      homePage.indexOf('// ClipRect'),
    );
    expect(
      onPageChanged,
      contains('newPlanet != _sharedSceneConfig?.planet'),
      reason: '滑到与当前场景不同的星球才盖替身（同星球零打扰）',
    );
    expect(onPageChanged, contains('_sharedSceneReady = false'));
    expect(onPageChanged, contains('_armSceneRevealFallback()'));
  });

  test('切页时星空亮度延后到 planetReady 后更新，避免和贴图上传抢同一帧', () {
    expect(homePage, contains('_visibleStarfieldPage'));
    expect(homePage, contains('_pendingStarfieldPage'));
    expect(homePage, contains('_onPlanetSceneReady'));
    expect(
      homePage,
      contains(
        'final starfieldNovel = novels.isEmpty ? null : novels[starfieldPage]',
      ),
    );
    expect(
      homePage,
      contains('ref.watch(creativeCountProvider(starfieldNovel.id))'),
    );
    expect(
      homePage,
      contains('_pendingStarfieldPage = i'),
      reason: 'PageView 刚切页只记录待切换星空页，不立刻重建星空亮度/底图',
    );
    expect(
      homePage,
      contains('_visibleStarfieldPage = pending'),
      reason: '等 3D 场景 planetReady 后再让星空跟上新页',
    );
  });

  test('Web 端 iframe viewType 必须每实例唯一（工厂闭包捕获旧 State 的回归）', () {
    // Flutter web 对同名 viewType 的重复注册会被忽略：PageView 滑页重建后
    // 新 State 的工厂不生效，iframe 被写进旧 State → postMessage 全部打空，
    // 表现为"多星球滑页后缩放/旋转全失效"（真实发生过）
    expect(webWrapper, contains('++_instanceSeq'));
    expect(webWrapper, contains(r'_$_seq'), reason: 'viewType 须带实例序号');
  });

  test('场景页自带 selftest：serve_web.ps1 每次构建后无头跑核心链路', () {
    // 覆盖"改完代码后星球放不大/转不动"这类只有真机才暴露的回归
    expect(sceneHtml, contains("params.get('selftest')"));
    expect(sceneHtml, contains('SELFTEST_PASS'));
    expect(sceneHtml, contains('SELFTEST_FAIL'));
    final ps1 = File('scripts/serve_web.ps1').readAsStringSync();
    expect(ps1, contains('selftest=1'));
    expect(ps1, contains('场景自检失败'), reason: '自检失败必须让脚本报错，不能静默放行');
  });

  test('原生视图不吃点击：DOM 层与 Flutter 层两道都必须放行', () {
    expect(
      webWrapper,
      contains("pointerEvents = 'none'"),
      reason: 'DOM 层：iframe 的透明区域不能吃掉 DOM 事件',
    );
    expect(
      webWrapper,
      contains('IgnorePointer'),
      reason:
          'Flutter 层：platform view 会在手势竞技场赢走所有手势，'
          '漏包则"点星球进大纲"在 web 上永远不触发（CDP 探针实证过）',
    );
    expect(
      ioWrapper,
      contains('IgnorePointer'),
      reason: '移动端 WebView 同理：点击进大纲/长按删除/翻页全归 Flutter',
    );
  });

  test('放大不撑大布局与命中区：舞台用 OverflowBox 只溢出绘制', () {
    expect(
      homePage,
      contains('OverflowBox'),
      reason: '舞台放大只能溢出绘制；撑大布局会让透明区盖住魔毯球与速记按钮',
    );
    // SizedBox 外框仍为 sceneDiameter（未乘舞台倍率）= 布局与命中区不变
    expect(homePage, contains('dimension: sceneDiameter'));
    expect(
      homePage,
      isNot(contains('dimension: sceneDiameter * kPlanetSceneStageScale')),
    );
  });

  test('缩放是镜头推进而非位图放大：放大后重新渲染且恒居中', () {
    expect(
      homePage,
      isNot(contains('InteractiveViewer')),
      reason: 'InteractiveViewer 放大的是渲染好的位图 → 模糊；须走场景镜头 dolly',
    );
    expect(sceneHtml, contains('window.setZoom'));
    expect(
      sceneHtml,
      contains('camera.position.z = d0 / zoom'),
      reason: '镜头沿视线推进，恒过原点 → 星球始终居中',
    );
    expect(
      sceneHtml,
      isNot(contains('OrbitControls')),
      reason: '本层 pointer 透明，OrbitControls 收不到事件，已移除',
    );
    // 移除 OrbitControls 后不得残留 controls 引用：
    // 裸的 ReferenceError 会让整个渲染循环停摆，而 Dart 侧工具链看不到
    expect(sceneHtml, isNot(contains('controls.')));
  });

  test('拖动转星球：支点承载转角，云层与土星环同挂支点', () {
    expect(sceneHtml, contains('window.setRotation'));
    expect(sceneHtml, contains('pivot.add(pmesh)'));
    expect(sceneHtml, contains('pivot.add(cl)'), reason: '云层不挂支点则拖动时与地表脱节');
    expect(sceneHtml, contains('pivot.add(rg)'), reason: '土星环不挂支点则拖动时与赤道脱节');
    expect(sceneHtml, contains('maxPitch'), reason: '俯仰须钳制，不许翻过极点');
    // 两端桥都要下发转角
    expect(ioWrapper, contains('setRotation('));
    expect(webWrapper, contains("'yaw'"));
    // Flutter 侧：拖球面转星球，拖球外留给 PageView 翻页
    expect(homePage, contains('_rotating'));
    expect(homePage, contains('kMaxPitch'));
    // 甩手惯性接线（滑行行为本身由 test/core/spin_inertia_test.dart 覆盖）
    expect(homePage, contains('SpinInertia'));
    expect(homePage, contains('_glideTicker'));
    expect(homePage, contains('_spin.grab()'), reason: '按下须抓停滑行中的星球');
  });

  test('放大态：书名与环绕文字让位、PageView 锁定防误翻页', () {
    expect(homePage, contains('kPlanetTitleHideZoom'));
    expect(homePage, contains('planetZoomLock'));
    expect(homePage, contains('NeverScrollableScrollPhysics'));
    expect(homePage, contains('fade: _zoomed'));
  });

  test('放大态点击星球仍进入魔树，不把第一次点击消耗成复位', () {
    expect(
      homePage,
      isNot(contains('if (_zoomed)')),
      reason: '用户点击地球应直接进入魔树；缩放复位不应吞掉这次点击',
    );
  });

  test('星球画布不跨页：每页 ClipRect，杜绝相邻星球重影', () {
    expect(homePage, contains('ClipRect'));
  });

  test('高清：8K 地表 LOD + 高像素比 + 128 段球体', () {
    expect(sceneHtml, contains('earth_day_8192.jpg'));
    expect(sceneHtml, contains('lodZoom'));
    expect(sceneHtml, contains('SphereGeometry(1, 128, 128)'));
    expect(
      File('assets/planet_scene/textures/earth_day_8192.jpg').existsSync(),
      isTrue,
    );
  });

  test('移动端放大档 6144（约 75MB）：8192 单张纹理约 134MB，iPhone 会卡死', () {
    // 手机档 mapMid 指向 6144 贴图（地球/火星/金星；气态行星源图上限 4096）
    for (final p in ['earth_day', 'mars', 'venus']) {
      expect(sceneHtml, contains('textures/${p}_6144.jpg'));
      expect(
        File('assets/planet_scene/textures/${p}_6144.jpg').existsSync(),
        isTrue,
      );
    }
    expect(sceneHtml, contains('mapMid'));
    expect(sceneHtml, contains("lodParam === 'mid'"));
    // 移动端 App 壳显式下发 lod=mid，不依赖浏览器嗅探
    expect(ioWrapper, contains('lod=mid'));
  });

  test('Web 体验版启用最高地表档，最大缩放时增强地表细节感', () {
    expect(
      webWrapper,
      contains('lod=hi'),
      reason: '用户用 iPhone Safari 测 Web 版时应能体验最高地表细节',
    );
    expect(sceneHtml, contains('applySurfaceDetail'));
    expect(sceneHtml, contains('detailZoomFull'));
    expect(sceneHtml, contains('normalScale.set'));
    expect(sceneHtml, contains('planetMat.shininess'));
  });

  test('放大时像素比拉满设备、缩回降档省电（触屏常态 2.5）', () {
    expect(sceneHtml, contains('isMobileLike ? 2.5 : 3'));
    expect(sceneHtml, contains('setPixelRatioBoost'));
  });

  test('LOD 迟滞切换：缩回释放高清纹理、常态贴图常驻、解码不阻塞主线程', () {
    expect(sceneHtml, contains('lodZoomOut'), reason: '无迟滞会在阈值附近来回抖动、反复加载大图');
    expect(
      sceneHtml,
      contains('hiTex.dispose()'),
      reason: '缩回不释放高清贴图则显存长期高占用 → iPhone 卡死',
    );
    expect(
      sceneHtml,
      contains('baseTex: pmat.map'),
      reason: '常态贴图须常驻（mountPlanet 返回 baseTex，缩小观看不闪砂）',
    );
    expect(sceneHtml, contains('createImageBitmap'), reason: '主线程解码大图会整页卡住');
  });

  test('LOD 调度避开手势热路径：空闲预热、GPU 预热、缩回延迟收尾', () {
    final applyLodBody = functionBody(sceneHtml, 'applyLod');
    expect(
      sceneHtml,
      contains('requestIdleCallback'),
      reason: '高清纹理解码/预热应尽量安排到空闲时间，而不是捏合过阈值那一刻',
    );
    expect(
      sceneHtml,
      contains('prewarmHiTexture'),
      reason: '场景稳定后要主动预热放大档，避免第一次放大才开始搬大图',
    );
    expect(
      sceneHtml,
      contains('createTextureChunked'),
      reason: 'createImageBitmap 只解决解码，GPU 上传也要分块提前做掉',
    );
    expect(
      sceneHtml,
      contains('lodSettleDelayMs'),
      reason: '缩回时不要立刻降像素比/换贴图，避免手势中来回重配画布',
    );
    expect(
      sceneHtml,
      contains('lodDisposeDelayMs'),
      reason: '高清纹理释放要更晚，短时间再次放大不能重新 fetch/upload',
    );
    expect(
      sceneHtml,
      contains('cancelLodTimers'),
      reason: '重新放大时必须取消延迟收尾，否则会把正在看的高清档释放掉',
    );
    expect(
      applyLodBody,
      isNot(contains('setPixelRatioBoost(true)')),
      reason: '捏合跨过高清阈值时不能同步重分配 drawing buffer / MSAA 缓冲',
    );
    expect(
      applyLodBody,
      isNot(contains('ensureHiTexture()')),
      reason: '捏合热路径不能现场 fetch/decode/upload 6144 高清贴图',
    );
    expect(
      sceneHtml,
      contains('schedulePixelRatioBoost'),
      reason: 'DPR 提升应延后到手势静默期或空闲帧执行',
    );
    expect(
      sceneHtml,
      contains('decodeImageOffMainThread'),
      reason: '高清 JPEG 先用 img.decode 后台解码，再进入 ImageBitmap/分块上传',
    );
  });

  test('可见场景零后台重活：切球完成后禁止一切自动高清预热/DPR boost', () {
    // 根本方案（2026-07-15 定稿）：只要后台还允许偷偷做高清解码/GPU 上传/
    // setPixelRatio+setSize，就一定会在某些 iPhone/Safari 时机下短顿（调 2.5s、
    // 4s、分块大小都只是把顿挪来挪去）。自动高清预热线整条删除，高清 LOD
    // 只在用户明确放大（applyLod 手势路径）时进入。
    expect(sceneHtml, isNot(contains('scheduleInitialScenePrewarm')));
    expect(sceneHtml, isNot(contains('initialPrewarmDelayMs')));
    expect(sceneHtml, isNot(contains('autoPrewarm')));
    expect(webWrapper, isNot(contains('autoPrewarm')));
    expect(ioWrapper, isNot(contains('autoPrewarm')));
    expect(homePage, isNot(contains('autoPrewarm')));
    // 切球事务收尾不得排任何预热任务
    final setPlanetStart = sceneHtml.indexOf('window.setPlanet = function');
    final setPlanetBody = sceneHtml.substring(
      setPlanetStart,
      sceneHtml.indexOf('window.addEventListener', setPlanetStart),
    );
    expect(setPlanetBody, isNot(contains('prewarmHiTexture')));
    expect(setPlanetBody, isNot(contains('PixelRatioBoost')));
    // 邻居星球只预取到 HTTP 缓存层：不解码、不建 ImageBitmap、不上传 GPU
    final prewarmBody = sceneHtml.substring(
      sceneHtml.indexOf('window.prewarmPlanets = function'),
      sceneHtml.indexOf('// 切星球'),
    );
    expect(prewarmBody, isNot(contains('preloadPlanetTextureBundle')));
    expect(prewarmBody, isNot(contains('createImageBitmap')));
    expect(prewarmBody, isNot(contains('createTextureChunked')));
    // 预取助手本体也必须是纯字节层：消费完 body 落 HTTP 缓存即止
    final prefetchBody = functionBody(sceneHtml, 'prefetchTexturePath');
    expect(prefetchBody, contains('.blob()'));
    expect(prefetchBody, isNot(contains('createImageBitmap')));
    expect(prefetchBody, isNot(contains('createTextureChunked')));
    expect(prefetchBody, isNot(contains('decodeImageOffMainThread')));
  });

  test('第一次放大不慢半拍：高清文件预取字节 + 手势即刻解码 + DPR 仍延后', () {
    // 1) 高清 LOD 路径进入轻量预取清单（仅字节落 HTTP 缓存，不碰 GPU）；
    //    切球后/首屏也预取当前星球的高清档
    expect(sceneHtml, contains('useMidLod ? pcfg.mapMid : pcfg.mapHi'));
    expect(sceneHtml, contains('prefetchTexturePath(lodSrc)'));
    // 2) 捏合跨过预热阈值＝用户明确意图：立刻 img.decode+分块上传，
    //    不再走 runWhenQuiet 等静默期（那是人为制造"慢半拍"）
    final prewarmHiBody = functionBody(sceneHtml, 'prewarmHiTexture');
    expect(prewarmHiBody, isNot(contains('runWhenQuiet')));
    expect(prewarmHiBody, contains('ensureHiTexture()'));
    // 3) 保护阀：DPR 画布重分配仍不打在手势热帧上
    expect(sceneHtml, contains('schedulePixelRatioBoost'));
  });

  test('GPU 上传调度器：按帧预算、自适应块大小、交互期间让路', () {
    // 交互期间绝不做重 GPU 工作：手指下的帧只允许改镜头。重活全部排进
    // 按帧预算的串行队列——交互中让路、持续交互有防饿死兜底、块大小按
    // 实测耗时自适应（>6ms 减半、<3ms 加倍）。
    expect(sceneHtml, contains('waitForUploadWindow'));
    expect(sceneHtml, contains('uploadInteractGuardMs'));
    expect(sceneHtml, contains('uploadSlotMaxWaitMs'), reason: '连续滑页/转球不能把切球事务饿死');
    expect(sceneHtml, contains('adaptiveBandBytes'));
    expect(sceneHtml, contains('tuneUploadBudget'));
    // 显存大分配（initTexture ≈75MB）也要先拿预算槽，不打手势热帧
    final chunkBody = functionBody(sceneHtml, 'createTextureChunked');
    expect(
      chunkBody.indexOf('nextGpuUploadSlot'),
      lessThan(chunkBody.indexOf('renderer.initTexture')),
      reason: 'initTexture 必须排在预算槽之后执行',
    );
    // DPR 升/降档（画布重分配）全部走同一预算队列
    expect(
      functionBody(sceneHtml, 'schedulePixelRatioBoost'),
      contains('nextGpuUploadSlot'),
    );
    expect(
      functionBody(sceneHtml, 'prewarmPixelRatioBoost'),
      contains('nextGpuUploadSlot'),
    );
    expect(
      functionBody(sceneHtml, 'scheduleLodSettleDown'),
      contains('nextGpuUploadSlot'),
    );
  });

  test('切换星球：不预构建相邻页，也不保活多颗 WebGL 场景', () {
    expect(
      homePage,
      contains('allowImplicitScrolling: false'),
      reason: 'iPhone Safari 连续滑动时不能让"尚未看过"的相邻星球提前持有 WebGL 场景',
    );
    expect(
      homePage,
      isNot(contains('AutomaticKeepAliveClientMixin')),
      reason: 'keepAlive 机制保留：保活集内（当前页 + 最近看过）都常驻，切回不重建',
    );
    expect(
      homePage,
      isNot(contains('bool get wantKeepAlive => widget.keptAlive')),
    );
    // 上限护显存：太久没看的星球淘汰、销毁
    expect(homePage, isNot(contains('static const _kMaxAliveScenes')));
    expect(homePage, contains('_SharedPlanetSceneLayer'));
  });

  test('删除前一颗星球后仍复用同一个共享 3D 场景容器', () {
    expect(
      homePage,
      contains("'planet-page-\${novels[i].id}-\${novels[i].planet}'"),
      reason: 'PageView 删除前一页后会按下标复用 State；必须用小说身份给页面定 key',
    );
    expect(
      homePage,
      isNot(contains("ValueKey('planet-scene-\${novel.id}-\${novel.planet}')")),
      reason: '单场景复用时 PlanetScene 不能再按小说/星球建多份 iframe/WebView',
    );
    expect(
      homePage,
      contains("ValueKey('shared-planet-scene')"),
      reason: '共享 3D 场景容器保持同一个平台视图实例，切星球只下发参数',
    );
  });

  test('LOD 高清贴图与常态贴图保持同一 UV 朝向，缩放换档不能让大陆跳变', () {
    expect(
      sceneHtml,
      contains("imageOrientation: 'flipY'"),
      reason:
          '常态贴图由 TextureLoader 上传时会翻转 Y；ImageBitmap 必须在解码时显式翻转，否则换档会像刷新到另一面',
    );
    expect(
      sceneHtml,
      contains('tex.flipY = false'),
      reason: 'ImageBitmap 已在解码阶段完成翻转，纹理对象不能再依赖被浏览器忽略的 flipY',
    );
  });

  test('五颗星球都有高清 LOD 与源图（CC-BY solarsystemscope）', () {
    for (final p in ['mars', 'venus', 'jupiter', 'saturn']) {
      expect(sceneHtml, contains('textures/${p}_2048.jpg'));
      expect(sceneHtml, contains('textures/${p}_hi.jpg'));
      expect(
        File('assets/planet_scene/textures/${p}_2048.jpg').existsSync(),
        isTrue,
      );
      expect(
        File('assets/planet_scene/textures/${p}_hi.jpg').existsSync(),
        isTrue,
      );
    }
    // 场景纹理全部自带，不再借道回环服务去取主 App 的 2K 旧贴图
    expect(sceneHtml, isNot(contains('apptex')));
    expect(webWrapper, isNot(contains('apptex')));
  });

  test('取景随视口重算：WebView/iframe 首帧 0×0 不会把镜头距离算成 NaN', () {
    // d0 只在加载时算一次 + 首帧 0×0 → aspect NaN → 镜头 NaN → 场景永远空白
    expect(sceneHtml, contains('function updateFraming'));
    expect(sceneHtml, contains('if (!w || !h'), reason: '零尺寸时必须跳过取景计算');
    expect(sceneHtml, contains("addEventListener('resize', updateFraming)"));
    expect(sceneHtml, contains('let d0 = 0'), reason: 'd0 须可重算（const 意味着只算一次）');
  });

  test('土星环用真实环带贴图（含卡西尼缝），UV 按实际内径重映射', () {
    expect(sceneHtml, contains('textures/saturn_ring.png'));
    expect(
      File('assets/planet_scene/textures/saturn_ring.png').existsSync(),
      isTrue,
    );
    expect(
      sceneHtml,
      contains('(vv.length() - ringInner) / (rOuter - ringInner)'),
      reason: 'UV 内径写死会让环纹整体错位',
    );
  });
}
