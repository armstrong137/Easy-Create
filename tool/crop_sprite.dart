/// 卷须精灵图裁切工具：从魔树素材裁一块区域，把米白背景键控成透明，
/// 自动裁掉四周全透明边，可选水平镜像。供章/节枝用真实照片卷须。
///
/// 用法：dart run tool/crop_sprite.dart --in 源.png --out 出.png \
///        [--rect x,y,w,h] [--flip] [--erase x,y,w,h ...] \
///        [--no-trim] [--resize 宽] [--key-lo 14] [--key-hi 45]
///
/// --rect 缺省时取整图；--erase 相对裁切区域坐标，把杂物直接置透明，可多次；
/// --no-trim 保留原画幅（逐帧动画需各帧对位）；--resize 输出前等比缩到指定宽；
/// --key-lo/--key-hi 背景键控距离阈值（低于 lo 全透、高于 hi 全不透，
/// 中间渐变——底色有柔和晕影的素材要调大 lo 才抠得干净）。
library;

import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  String? inPath;
  String? outPath;
  int x = 0, y = 0, w = 0, h = 0;
  var flip = false;
  var trim = true;
  int? resizeW;
  var keyLo = 14;
  var keyHi = 45;
  var satMode = false;
  final erases = <(int, int, int, int)>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        inPath = args[++i];
      case '--out':
        outPath = args[++i];
      case '--rect':
        final p = args[++i].split(',').map(int.parse).toList();
        (x, y, w, h) = (p[0], p[1], p[2], p[3]);
      case '--erase':
        final p = args[++i].split(',').map(int.parse).toList();
        erases.add((p[0], p[1], p[2], p[3]));
      case '--flip':
        flip = true;
      case '--no-trim':
        trim = false;
      case '--resize':
        resizeW = int.parse(args[++i]);
      case '--key-lo':
        keyLo = int.parse(args[++i]);
      case '--key-hi':
        keyHi = int.parse(args[++i]);
      case '--key-sat':
        satMode = true;
    }
  }
  final src = img.decodeImage(File(inPath!).readAsBytesSync())!;
  if (w == 0) (w, h) = (src.width, src.height);

  // 背景色取全图角落（素材米白底非常均匀）
  final bg = src.getPixel(3, 3);

  var region = img.copyCrop(src, x: x, y: y, width: w, height: h);
  final out =
      img.Image(width: region.width, height: region.height, numChannels: 4);
  for (var yy = 0; yy < region.height; yy++) {
    for (var xx = 0; xx < region.width; xx++) {
      final p = region.getPixel(xx, yy);
      int alpha;
      if (satMode) {
        // 饱和度键控：主体高饱和（红/金/蓝），背景与柔和投影都是低饱和的灰。
        // 用亮度守住主体的黑色描边（暗像素一律保留，避免被误抠）。
        final maxC = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
        final minC = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
        final sat = (maxC - minC).toDouble();
        const satLo = 26.0; // 低于此 = 纯灰背景/投影
        const satHi = 55.0; // 高于此 = 确定的彩色主体
        const brightMin = 120; // 暗于此的像素视为主体描边，强制不透明
        if (minC < brightMin) {
          alpha = 255;
        } else if (sat <= satLo) {
          alpha = 0;
        } else if (sat >= satHi) {
          alpha = 255;
        } else {
          alpha = ((sat - satLo) / (satHi - satLo) * 255).round();
        }
      } else {
        // 与背景色的最大通道距离：越近越透明（软边缘）
        final d = [
          (p.r - bg.r).abs(),
          (p.g - bg.g).abs(),
          (p.b - bg.b).abs(),
        ].reduce((a, b) => a > b ? a : b);
        if (d <= keyLo) {
          alpha = 0;
        } else if (d < keyHi) {
          alpha = ((d - keyLo) / (keyHi - keyLo) * 255).round();
        } else {
          alpha = 255;
        }
      }
      out.setPixelRgba(xx, yy, p.r, p.g, p.b, alpha);
    }
  }

  // 擦除杂物区域
  for (final (ex, ey, ew, eh) in erases) {
    for (var yy = ey; yy < ey + eh && yy < out.height; yy++) {
      for (var xx = ex; xx < ex + ew && xx < out.width; xx++) {
        if (yy >= 0 && xx >= 0) out.setPixelRgba(xx, yy, 0, 0, 0, 0);
      }
    }
  }

  var trimmed = out;
  if (trim) {
    // 裁掉全透明边（留 2px 余量）
    var minX = out.width, minY = out.height, maxX = -1, maxY = -1;
    for (var yy = 0; yy < out.height; yy++) {
      for (var xx = 0; xx < out.width; xx++) {
        if (out.getPixel(xx, yy).a > 8) {
          if (xx < minX) minX = xx;
          if (xx > maxX) maxX = xx;
          if (yy < minY) minY = yy;
          if (yy > maxY) maxY = yy;
        }
      }
    }
    if (maxX < 0) {
      stderr.writeln('区域内没有前景像素，检查 --rect');
      exit(1);
    }
    minX = (minX - 2).clamp(0, out.width - 1);
    minY = (minY - 2).clamp(0, out.height - 1);
    maxX = (maxX + 2).clamp(0, out.width - 1);
    maxY = (maxY + 2).clamp(0, out.height - 1);
    trimmed = img.copyCrop(out,
        x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }
  if (flip) trimmed = img.flipHorizontal(trimmed);
  if (resizeW != null && resizeW < trimmed.width) {
    trimmed = img.copyResize(trimmed,
        width: resizeW, interpolation: img.Interpolation.cubic);
  }

  File(outPath!).writeAsBytesSync(img.encodePng(trimmed));
  stderr.writeln('已生成 $outPath (${trimmed.width}x${trimmed.height})');
}
