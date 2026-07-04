/// 魔树阶段图转 JPG：picture/魔树N.png → assets/textures/magic_tree_N.jpg
/// （整图铺底显示，无需透明通道；q92 控制包体）
///
/// 用法：dart run tool/stage_convert.dart
library;

import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  for (var n = 1; n <= 3; n++) {
    final input =
        img.decodeImage(File('picture/魔树$n.png').readAsBytesSync())!;
    final out = 'assets/textures/magic_tree_$n.jpg';
    File(out).writeAsBytesSync(img.encodeJpg(input, quality: 92));
    stderr.writeln('已生成 $out (${File(out).lengthSync() ~/ 1024}KB)');
  }
}
