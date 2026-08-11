import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web 场景启动面保持透明且无回音时会切换静态替身', () {
    final wrapper = File(
      'lib/presentation/outline/tree_scene/tree_scene_web.dart',
    ).readAsStringSync();
    final html = File('assets/tree_scene/index.html').readAsStringSync();

    expect(wrapper, contains("style.backgroundColor = 'transparent'"));
    expect(wrapper, contains('activateStaticFallback'));
    expect(wrapper, contains('Timer('));
    expect(html, contains('background: transparent'));
  });

  test('实时场景真正就绪前静态树始终盖在场景上方', () {
    final source = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    final scene = source.indexOf('child: TreeScene(controller:');
    final standin = source.indexOf('!_treeSceneController.isReady ||');

    expect(scene, greaterThanOrEqualTo(0));
    expect(standin, greaterThan(scene));
  });

  test('场景入口可在渲染器构造失败时向 Flutter 上报错误', () {
    final source = File('assets/tree_scene/dist/main.js').readAsStringSync();

    expect(source, contains('let treeScene = null;'));
    expect(source, contains("parameters.get('session')"));
    expect(source, contains('treeScene = new MagicTreeScene'));
    expect(source, contains("emit('scene.error'"));
  });
}
