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

  test('Web 端贴图路径正确：iframe 相对 assets/assets/planet_scene/ 上跳一级', () {
    expect(
      webWrapper,
      contains("apptex=../textures/"),
      reason: '上跳两级会指向 assets/textures/（不存在）→ 非地球星球全黑',
    );
  });
}
