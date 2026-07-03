/// 诊断：检查图片四角与中心的 alpha/RGB（判断真假透明）
library;

import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final im = img.decodeImage(File(args[0]).readAsBytesSync())!;
  stderr.writeln('尺寸: ${im.width}x${im.height}, 通道: ${im.numChannels}');
  for (final (name, x, y) in [
    ('左上角', 10, 10),
    ('右上角', im.width - 10, 10),
    ('中心', im.width ~/ 2, im.height ~/ 2),
    ('上缘中', im.width ~/ 2, 10),
  ]) {
    final p = im.getPixel(x.clamp(0, im.width - 1), y.clamp(0, im.height - 1));
    stderr.writeln('$name($x,$y): R=${p.r} G=${p.g} B=${p.b} A=${p.a}');
  }
}
