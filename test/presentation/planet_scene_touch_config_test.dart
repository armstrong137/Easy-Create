import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('3D 星球缩放不能扩大原生视图命中范围', () {
    final webWrapper = File(
      'lib/presentation/home/planet_scene/planet_scene_web.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/presentation/home/home_page.dart',
    ).readAsStringSync();
    final orbiting = File(
      'lib/presentation/home/orbiting_inspirations.dart',
    ).readAsStringSync();
    final sceneHtml = File('assets/planet_scene/index.html').readAsStringSync();

    expect(
      webWrapper,
      contains("pointerEvents = 'none'"),
      reason: 'iframe 的透明区域不能吃掉首页与灵感魔毯的点击',
    );
    expect(sceneHtml, contains('OrbitControls.js'));
    expect(sceneHtml, contains('new THREE.OrbitControls'));
    expect(File('assets/planet_scene/OrbitControls.js').existsSync(), isTrue);
    expect(homePage, contains('kPlanetSceneStageScale'));
    expect(homePage, contains('kPlanetSceneMaxScale'));
    expect(homePage, contains('InteractiveViewer'));
    expect(homePage, contains('maxScale: kPlanetSceneMaxScale'));
    expect(
      homePage,
      isNot(contains('diameter: sceneDiameter * kPlanetSceneStageScale')),
      reason: '不能再把原生 WebView/iframe 物理尺寸放大，否则透明区域会挡住点击',
    );
    expect(orbiting, contains('clipBehavior: Clip.none'));
    expect(sceneHtml, contains('stageScale'));
  });
}
