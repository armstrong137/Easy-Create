import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('正式魔树 GLB、源文件与六张回退图齐全', () {
    expect(
      File(
        'assets/source/magic_tree/blender/magic_tree_master.blend',
      ).existsSync(),
      isTrue,
    );
    expect(File('assets/3d/magic_tree/magic_tree.glb').existsSync(), isTrue);
    for (var i = 0; i < 6; i++) {
      expect(
        File('assets/tree_scene/standins/age_$i.webp').existsSync(),
        isTrue,
        reason: '缺少 age_$i.webp',
      );
    }
  });
}
