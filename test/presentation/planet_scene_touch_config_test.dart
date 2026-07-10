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
    expect(sceneHtml, contains('devicePixelRatio, 3'));
    expect(sceneHtml, contains('SphereGeometry(1, 128, 128)'));
    expect(
      File('assets/planet_scene/textures/earth_day_8192.jpg').existsSync(),
      isTrue,
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
