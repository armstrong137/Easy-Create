import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('正式 3D 星球场景允许触摸进入 OrbitControls', () {
    final webWrapper = File(
      'lib/presentation/home/planet_scene/planet_scene_web.dart',
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
  });
}
