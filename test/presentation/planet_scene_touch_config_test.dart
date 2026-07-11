import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 3D 星球缩放的架构护栏（源码级断言，不依赖平台视图）
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
    expect(homePage, contains('_sceneReady'));
  });

  test('返回首页时用上一帧星球快照兜底，不能调用未定义的 sendSnapshot', () {
    expect(sceneHtml, contains('function sendSnapshot'));
    expect(sceneHtml, contains("toDataURL('image/png')"));
    expect(webWrapper, contains('sceneSnapshot:\$_seq'));
    expect(homePage, contains('_sceneSnapshot'));
    expect(homePage, contains('Image.network'));
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
    expect(homePage, contains('active: widget.active'));
    expect(homePage, contains('_snapshotReq++'), reason: '进大纲前拍最新快照');
    expect(ioWrapper, contains("'pauseRender()'"));
  });

  test('性能护栏：旋转重建路径不再每帧复制排序灵感池', () {
    expect(homePage, contains('items: _cachedOrbitItems'));
    expect(homePage, contains('_refreshCachedOrbitItems'));
    expect(homePage, contains('didUpdateWidget'));
    expect(homePage, isNot(contains('items: [...widget.pool]')));
  });

  test('Web 端路由被覆盖时摘除星球 platform view（进大纲整页白屏的回归）', () {
    // CanvasKit 的 overlay 合成在 platform view 驻留于非当前路由时会
    // 丢掉所有 canvas（CDP 实证 canvases:0 → 整页白）；摘除即恢复，
    // 顺带满足清单 §12.2"不可见页面暂停渲染"
    expect(homePage, contains('ModalRoute.of(context)?.isCurrent'));
    expect(homePage, contains('!kIsWeb || routeCurrent'));
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
    expect(sceneHtml, contains('pivot.add(planet)'));
    expect(sceneHtml, contains('pivot.add(clouds)'), reason: '云层不挂支点则拖动时与地表脱节');
    expect(sceneHtml, contains('pivot.add(ring)'), reason: '土星环不挂支点则拖动时与赤道脱节');
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
      contains('const baseTex'),
      reason: '常态贴图须常驻（带 mipmap，缩小观看不闪砂）',
    );
    expect(sceneHtml, contains('createImageBitmap'), reason: '主线程解码大图会整页卡住');
  });

  test('LOD 调度避开手势热路径：空闲预热、GPU 预热、缩回延迟收尾', () {
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
      contains('warmTextureOnGpu'),
      reason: 'createImageBitmap 只解决解码，首次 GPU 上传也要提前做掉',
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
  });

  test('当前星球进入页面后自动空闲预热高清 LOD，第一次捏合前就把重活提前做掉', () {
    expect(
      sceneHtml,
      contains('initialPrewarmDelayMs'),
      reason: '当前页要主动预热，而不是等用户第一次捏合才加载高清贴图',
    );
    expect(
      sceneHtml,
      contains('const initialPrewarmDelayMs = 300'),
      reason: '预热要挪到启动封面遮挡期内，避免用户看到旋转一秒后卡一下',
    );
    expect(
      sceneHtml,
      contains('scheduleInitialScenePrewarm'),
      reason: '预热入口应由场景加载后主动触发，覆盖第一次放大卡顿',
    );
    expect(
      sceneHtml,
      contains('setTimeout(scheduleInitialScenePrewarm'),
      reason: '预热需要延迟到首屏渲染之后，避免和页面初始加载抢主线程',
    );
  });

  test('切换星球前预构建相邻页，已访问星球页保活，减少第一次切页冷启动卡顿', () {
    expect(
      homePage,
      contains('allowImplicitScrolling: true'),
      reason: 'PageView 应提前构建相邻页，让左右星球的 WebView/iframe 先启动加载',
    );
    expect(
      homePage,
      contains('AutomaticKeepAliveClientMixin'),
      reason: '已访问星球页需要保活，避免来回切换时重新创建 3D 场景',
    );
    expect(homePage, contains('bool get wantKeepAlive => true'));
    expect(homePage, contains('super.build(context)'));
  });

  test('删除前一颗星球后不能复用旧 3D 场景状态', () {
    expect(
      homePage,
      contains("'planet-page-\${novels[i].id}-\${novels[i].planet}'"),
      reason: 'PageView 删除前一页后会按下标复用 State；必须用小说身份给页面定 key',
    );
    expect(
      homePage,
      contains("ValueKey('planet-scene-\${novel.id}-\${novel.planet}')"),
      reason: '3D 场景初始化时绑定 planet；小说切换后不能沿用旧 iframe/WebView',
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
      contains('(v.length() - ringInner) / (ringOuter - ringInner)'),
      reason: 'UV 内径写死会让环纹整体错位',
    );
  });
}
