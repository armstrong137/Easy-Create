/// 星球纹理生成工具：把用户提供的两张"正面圆图"（正交投影 2D 星球图）
/// 反投影拼合为等距圆柱展开纹理，供 planet.frag 球面采样实现 3D 自转。
///
/// 原理：图 A 承担正面半球、图 B 承担背面半球（各自反投影），
/// 交界 ±90° 处用渐变带混合——自转时看到两种真实面貌，无镜像伪影。
///
/// 用法：dart run tool/planet_texture_gen.dart <正面.png> <背面.png> <输出.jpg> [宽度]
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln(
        '用法: dart run tool/planet_texture_gen.dart 正面.png 背面.png 输出.jpg [宽度=2048]');
    exit(1);
  }
  final inputA = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final inputB = img.decodeImage(File(args[1]).readAsBytesSync())!;
  final outPath = args[2];
  final outW = args.length > 3 ? int.parse(args[3]) : 2048;
  final outH = outW ~/ 2;

  // 1. 找星球包围圆：扫描"非背景"像素范围。
  // 注意：素材是假透明（棋盘格画在 RGB 里，无 alpha），
  // 背景判定=浅灰白（各通道>225 且近乎无色差）；真透明像素同样视为背景
  bool isBackground(img.Pixel p) {
    if (p.a < 40) return true;
    final maxC = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
    final minC = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
    return minC > 225 && (maxC - minC) < 14;
  }

  (double, double, double) findCircle(img.Image input) {
    var minX = input.width, maxX = -1, minY = input.height, maxY = -1;
    for (var y = 0; y < input.height; y++) {
      for (var x = 0; x < input.width; x++) {
        if (!isBackground(input.getPixel(x, y))) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    // 半径略收缩，避免采到球缘的抗锯齿/杂色像素
    return (
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      ((maxX - minX) + (maxY - minY)) / 4 * 0.985,
    );
  }

  // 可选第 5 参手动指定球体圆 "cx,cy,r"（带光环等干扰物的图无法自动检测）
  final (cxA, cyA, rA) = args.length > 4
      ? _parseCircle(args[4])
      : findCircle(inputA);
  final (cxB, cyB, rB) = args.length > 4
      ? _parseCircle(args[4])
      : findCircle(inputB);
  stderr.writeln('正面圆: ($cxA,$cyA) r=$rA；背面圆: ($cxB,$cyB) r=$rB');

  // 可选第 6 参 "mirror-south"：南半球用北半球镜像
  // （土星等球体下部被光环遮挡的素材专用；水平条纹星球镜像无感）
  final mirrorSouth = args.length > 5 && args[5] == 'mirror-south';

  // 单张圆图采样：lon 为相对该图正面中心的经度（弧度）
  (int, int, int) samplePlanet(img.Image input, double cx, double cy,
      double r, double lon, double latRaw) {
    final lat = mirrorSouth && latRaw < 0 ? -latRaw : latRaw;
    // 只用 ±75° 内优质像素（边缘压缩区拉丝），0.83 缩放采样角
    final lonS = lon * 0.83;
    final x3 = math.cos(lat) * math.sin(lonS);
    final y3 = math.sin(lat);
    var dx = x3, dy = -y3;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0.96) {
      dx = dx / len * 0.96;
      dy = dy / len * 0.96;
    }
    final px = cx + dx * r;
    final py = cy + dy * r;

    // 边缘区（投影半径 >0.72）拉丝抑制：随位置增强的圆形多点模糊，
    // 把圆图边缘的高压缩条纹抹成柔和过渡
    if (len <= 0.72) return _bilinear(input, px, py);
    final blurR = (len - 0.72) / (0.96 - 0.72) * r * 0.055;
    var sr = 0.0, sg = 0.0, sb = 0.0;
    const taps = 8;
    for (var i = 0; i < taps; i++) {
      final ang = i * 2 * math.pi / taps;
      final (tr, tg, tb) = _bilinear(
          input, px + math.cos(ang) * blurR, py + math.sin(ang) * blurR);
      sr += tr;
      sg += tg;
      sb += tb;
    }
    final (cr, cg, cb) = _bilinear(input, px, py);
    return (
      ((sr + cr) / (taps + 1)).round(),
      ((sg + cg) / (taps + 1)).round(),
      ((sb + cb) / (taps + 1)).round(),
    );
  }

  // 2. 反投影拼合：A 管 |lon|<90°，B 管背面，交界 ±26° 宽渐变混合
  const blend = 0.45; // 混合带半宽（弧度，约 26°）
  final out = img.Image(width: outW, height: outH);
  for (var v = 0; v < outH; v++) {
    final lat = math.pi / 2 - (v + 0.5) / outH * math.pi;
    for (var u = 0; u < outW; u++) {
      final lon = (u + 0.5) / outW * 2 * math.pi - math.pi; // -π..π
      // 背面经度（相对背面中心 180°）
      var lonB = lon > 0 ? lon - math.pi : lon + math.pi;

      // A 图权重：正面中心 1，越过 90°±blend 渐变到 0
      final d = math.pi / 2 - lon.abs(); // 距交界的带符号距离（正=正面侧）
      final t = ((d + blend) / (2 * blend)).clamp(0.0, 1.0);
      final wA = t * t * (3 - 2 * t); // smoothstep

      if (wA >= 1.0) {
        final (r0, g0, b0) = samplePlanet(inputA, cxA, cyA, rA, lon, lat);
        out.setPixelRgb(u, v, r0, g0, b0);
      } else if (wA <= 0.0) {
        final (r0, g0, b0) = samplePlanet(inputB, cxB, cyB, rB, lonB, lat);
        out.setPixelRgb(u, v, r0, g0, b0);
      } else {
        final (ra, ga, ba) = samplePlanet(inputA, cxA, cyA, rA, lon, lat);
        final (rb, gb, bb) = samplePlanet(inputB, cxB, cyB, rB, lonB, lat);
        out.setPixelRgb(
          u,
          v,
          (ra * wA + rb * (1 - wA)).round(),
          (ga * wA + gb * (1 - wA)).round(),
          (ba * wA + bb * (1 - wA)).round(),
        );
      }
    }
  }

  // 3. 输出 JPG（app 内加载）
  File(outPath).writeAsBytesSync(img.encodeJpg(out, quality: 90));
  stderr.writeln('已生成 $outPath ($outW x $outH)');
}

/// 解析手动圆参数 "cx,cy,r"
(double, double, double) _parseCircle(String s) {
  final parts = s.split(',').map(double.parse).toList();
  return (parts[0], parts[1], parts[2]);
}

/// 双线性采样（越界取边缘），返回 (r, g, b)
(int, int, int) _bilinear(img.Image src, double x, double y) {
  final x0 = x.floor().clamp(0, src.width - 1);
  final y0 = y.floor().clamp(0, src.height - 1);
  final x1 = (x0 + 1).clamp(0, src.width - 1);
  final y1 = (y0 + 1).clamp(0, src.height - 1);
  final fx = (x - x0).clamp(0.0, 1.0);
  final fy = (y - y0).clamp(0.0, 1.0);

  final p00 = src.getPixel(x0, y0);
  final p10 = src.getPixel(x1, y0);
  final p01 = src.getPixel(x0, y1);
  final p11 = src.getPixel(x1, y1);

  num mix(num a, num b, double t) => a + (b - a) * t;
  return (
    mix(mix(p00.r, p10.r, fx), mix(p01.r, p11.r, fx), fy).round(),
    mix(mix(p00.g, p10.g, fx), mix(p01.g, p11.g, fx), fy).round(),
    mix(mix(p00.b, p10.b, fx), mix(p01.b, p11.b, fx), fy).round(),
  );
}
