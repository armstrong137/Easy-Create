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

  test('Web 端 iframe viewType 必须每实例唯一（工厂闭包捕获旧 State 的回归）', () {
    // Flutter web 对同名 viewType 的重复注册会被忽略：PageView 滑页重建后
    // 新 State 的工厂不生效，iframe 被写进旧 State → postMessage 全部打空，
    // 表现为"多星球滑页后缩放/旋转全失效"（真实发生过）
    expect(webWrapper, contains('_instanceSeq'));
    expect(webWrapper, contains(r'${++_instanceSeq}'));
  });

  test('场景页自带 selftest：serve_web.ps1 每次构建后无头跑核心链路', () {
    // 覆盖"改完代码后星球放不大/转不动"这类只有真机才暴露的回归
    expect(sceneHtml, contains("params.get('selftest')"));
    expect(sceneHtml, contains('SELFTEST_PASS'));
    expect(sceneHtml, contains('SELFTEST_FAIL'));
    final ps1 = File('scripts/serve_web.ps1').readAsStringSync();
    expect(ps1, contains('selftest=1'));
    expect(
      ps1,
      contains('场景自检失败'),
      reason: '自检失败必须让脚本报错，不能静默放行',
    );
  });

  test('原生视图不吃点击：iframe 透明区与 WebView 均不接手势', () {
    expect(
      webWrapper,
      contains("pointerEvents = 'none'"),
      reason: 'iframe 的透明区域不能吃掉首页与灵感魔毯的点击',
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
    expect(
      sceneHtml,
      contains('pivot.add(clouds)'),
      reason: '云层不挂支点则拖动时与地表脱节',
    );
    expect(
      sceneHtml,
      contains('pivot.add(ring)'),
      reason: '土星环不挂支点则拖动时与赤道脱节',
    );
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
    expect(
      homePage,
      contains('_spin.grab()'),
      reason: '按下须抓停滑行中的星球',
    );
  });

  test('放大态：书名与环绕文字让位、PageView 锁定防误翻页', () {
    expect(homePage, contains('kPlanetTitleHideZoom'));
    expect(homePage, contains('planetZoomLock'));
    expect(homePage, contains('NeverScrollableScrollPhysics'));
    expect(homePage, contains('fade: _zoomed'));
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

  test('放大时像素比拉满设备、缩回降档省电（触屏常态 2.5）', () {
    expect(sceneHtml, contains('isMobileLike ? 2.5 : 3'));
    expect(sceneHtml, contains('setPixelRatioBoost'));
  });

  test('LOD 迟滞切换：缩回释放高清纹理、常态贴图常驻、解码不阻塞主线程', () {
    expect(
      sceneHtml,
      contains('lodZoomOut'),
      reason: '无迟滞会在阈值附近来回抖动、反复加载大图',
    );
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
    expect(
      sceneHtml,
      contains('createImageBitmap'),
      reason: '主线程解码大图会整页卡住',
    );
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
    expect(
      sceneHtml,
      contains('let d0 = 0'),
      reason: 'd0 须可重算（const 意味着只算一次）',
    );
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
