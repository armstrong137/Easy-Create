import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('生产大纲页只保留实时3D与静态替身路径', () {
    const forbidden = <String>[
      'tree_frames',
      'tree_seg',
      'tendril_chapter.png',
      'tendril_section.png',
      '_MagicTreeImage',
      'kTreeFrameFirst',
      'ShaderMask',
    ];
    final productionSources = Directory('lib/presentation/outline')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync());
    final sources = <String>[
      ...productionSources,
      File('pubspec.yaml').readAsStringSync(),
    ].join('\n');

    for (final token in forbidden) {
      expect(sources, isNot(contains(token)), reason: '旧二维魔树标记不得回到生产路径：$token');
    }
  });

  test('旧帧序列与img2img生成脚本已经退役', () {
    for (final path in <String>[
      'lib/presentation/outline/magic_tree_model.dart',
      'assets/textures/tree_frames',
      'assets/textures/tree_frames_v3',
      'assets/textures/tree_seg',
      'assets/textures/tendril_chapter.png',
      'assets/textures/tendril_section.png',
      'scripts/magic_tree_img2img_pipeline.py',
      'scripts/magic_tree_sd_webui_provider.py',
      'scripts/validate_magic_tree_frames.py',
    ]) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: '实时3D定稿后不再维护旧资源：$path',
      );
    }
  });

  test('大纲页在静态模式显式关闭3D命令运输', () {
    final source = File(
      'lib/presentation/outline/outline_page.dart',
    ).readAsStringSync();
    expect(source, contains('_treeSceneController.setTransportEnabled('));
  });
}
