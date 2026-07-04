/// 抠背景工具：把接近纯色背景（浅灰白）的像素置为透明，
/// 边缘按接近程度渐变（供魔树等素材在纯白页面上无缝显示）。
///
/// 用法：dart run tool/knockout_bg.dart 输入.png 输出.png
library;

import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final input = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final out = img.Image(width: input.width, height: input.height,
      numChannels: 4);

  for (var y = 0; y < input.height; y++) {
    for (var x = 0; x < input.width; x++) {
      final p = input.getPixel(x, y);
      final maxC = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
      final minC = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
      // 背景特征：亮 + 低饱和。alpha 随"背景程度"渐变（软边缘）
      final sat = maxC - minC;
      int alpha;
      if (minC > 225 && sat < 16) {
        alpha = 0; // 纯背景
      } else if (minC > 200 && sat < 30) {
        // 过渡带：越接近背景越透明
        final t = ((225 - minC) / 25).clamp(0.0, 1.0);
        alpha = (t * 255).round();
      } else {
        alpha = 255;
      }
      out.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
    }
  }

  File(args[1]).writeAsBytesSync(img.encodePng(out));
  stderr.writeln('已生成 ${args[1]}');
}
