import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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

  test('六张回退图四周透明且没有矩形底片', () {
    for (var i = 0; i < 6; i++) {
      final file = File('assets/tree_scene/standins/age_$i.webp');
      final image = img.decodeWebP(file.readAsBytesSync());
      expect(image, isNotNull, reason: 'age_$i.webp 必须可解码');
      final corners = [
        image!.getPixel(0, 0),
        image.getPixel(image.width - 1, 0),
        image.getPixel(0, image.height - 1),
        image.getPixel(image.width - 1, image.height - 1),
      ];
      expect(
        corners.every((pixel) => pixel.a <= 8),
        isTrue,
        reason: 'age_$i.webp 四角必须透明，否则静态回退会出现矩形分割感',
      );
    }
  });
}
