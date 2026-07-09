import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('正式 3D 星球场景允许触摸进入 OrbitControls', () {
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
      isNot(contains("pointerEvents = 'none'")),
      reason: 'iframe 不能禁用指针事件，否则 iPhone Safari 的双指缩放进不了场景',
    );
    expect(sceneHtml, contains('OrbitControls.js'));
    expect(sceneHtml, contains('new THREE.OrbitControls'));
    expect(File('assets/planet_scene/OrbitControls.js').existsSync(), isTrue);
    expect(homePage, contains('kPlanetSceneStageScale'));
    expect(homePage, contains('OverflowBox'));
    expect(homePage, contains('stageScale: kPlanetSceneStageScale'));
    expect(orbiting, contains('clipBehavior: Clip.none'));
    expect(sceneHtml, contains('stageScale'));
    expect(sceneHtml, contains('fitDistance(frameRadius, stageScale * 1.02)'));
    expect(
      sceneHtml,
      contains('controls.minDistance = d0 / (stageScale * 0.92)'),
    );
    expect(
      sceneHtml,
      isNot(contains('controls.minDistance = d0 * 0.72')),
      reason: '固定 0.72 会把球放大到小 canvas 外，形成矩形裁切边',
    );
  });
}
