/// 星球纹理生成工具：把用户提供的 N 张"多角度正面圆图"反投影拼合为
/// 等距圆柱展开纹理，供 planet.frag 球面采样实现 3D 自转。
///
/// 原理（2026-07-03 升级为多图扇区合成）：N 张图均匀分担 360° 经度，
/// 每张只采其圆图中心的优质区（约 ±(180/N + 混合带)°，远离边缘拉伸区），
/// 相邻扇区在混合带内 smoothstep 渐变衔接。
///
/// 用法：
///   dart run tool/planet_texture_gen.dart --out=输出.jpg [选项] 图1 图2 ... 图N
/// 选项：
///   --width=2048          输出宽度（高=宽/2）
///   --circle-ratio=x,y,r  手动球体圆（相对图宽高的比例，用于带光环等素材）
///   --mirror-south        南半球用北半球镜像（球体下部被遮挡的素材）
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main(List<String> args) {
  String? outPath;
  var outW = 2048;
  (double, double, double)? circleRatio;
  var mirrorSouth = false;
  final inputPaths = <String>[];

  for (final a in args) {
    if (a.startsWith('--out=')) {
      outPath = a.substring(6);
    } else if (a.startsWith('--width=')) {
      outW = int.parse(a.substring(8));
    } else if (a.startsWith('--circle-ratio=')) {
      final p = a.substring(15).split(',').map(double.parse).toList();
      circleRatio = (p[0], p[1], p[2]);
    } else if (a == '--mirror-south') {
      mirrorSouth = true;
    } else {
      inputPaths.add(a);
    }
  }
  if (outPath == null || inputPaths.isEmpty) {
    stderr.writeln('用法: --out=输出.jpg [--width=N] [--circle-ratio=x,y,r] '
        '[--mirror-south] 图1 ... 图N');
    exit(1);
  }

  final inputs =
      inputPaths.map((p) => img.decodeImage(File(p).readAsBytesSync())!).toList();
  final n = inputs.length;
  final outH = outW ~/ 2;

  // 背景判定：浅灰白（素材为假透明棋盘底）或真透明
  bool isBackground(img.Pixel p) {
    if (p.a < 40) return true;
    final maxC = [p.r, p.g, p.b].reduce((a, b) => a > b ? a : b);
    final minC = [p.r, p.g, p.b].reduce((a, b) => a < b ? a : b);
    return minC > 225 && (maxC - minC) < 14;
  }

  // 各图球体包围圆（手动比例圆优先）
  final circles = inputs.map((input) {
    if (circleRatio != null) {
      return (
        circleRatio.$1 * input.width,
        circleRatio.$2 * input.height,
        circleRatio.$3 * input.width,
      );
    }
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
    return (
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      ((maxX - minX) + (maxY - minY)) / 4 * 0.985,
    );
  }).toList();
  for (var i = 0; i < n; i++) {
    stderr.writeln('图$i 球体圆: ${circles[i]}');
  }

  // 单图采样：lonRel 为相对该图正面中心的经度
  (int, int, int) samplePlanet(int idx, double lonRel, double latRaw) {
    final lat = mirrorSouth && latRaw < 0 ? -latRaw : latRaw;
    final (cx, cy, r) = circles[idx];
    final x3 = math.cos(lat) * math.sin(lonRel);
    final y3 = math.sin(lat);
    var dx = x3, dy = -y3;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0.96) {
      dx = dx / len * 0.96;
      dy = dy / len * 0.96;
    }
    final px = cx + dx * r;
    final py = cy + dy * r;
    // 边缘区（极区等）渐进模糊抗拉丝
    if (len <= 0.72) return _bilinear(inputs[idx], px, py);
    final blurR = (len - 0.72) / (0.96 - 0.72) * r * 0.055;
    var sr = 0.0, sg = 0.0, sb = 0.0;
    const taps = 8;
    for (var i = 0; i < taps; i++) {
      final ang = i * 2 * math.pi / taps;
      final (tr, tg, tb) = _bilinear(
          inputs[idx], px + math.cos(ang) * blurR, py + math.sin(ang) * blurR);
      sr += tr;
      sg += tg;
      sb += tb;
    }
    final (cr, cg, cb) = _bilinear(inputs[idx], px, py);
    return (
      ((sr + cr) / (taps + 1)).round(),
      ((sg + cg) / (taps + 1)).round(),
      ((sb + cb) / (taps + 1)).round(),
    );
  }

  // 扇区合成：图 i 的中心经度 = i * (2π/n)，混合带为扇区宽的 30%
  final sector = 2 * math.pi / n;
  final blendHalf = sector * 0.30;
  double wrap(double a) {
    while (a > math.pi) a -= 2 * math.pi;
    while (a < -math.pi) a += 2 * math.pi;
    return a;
  }

  final out = img.Image(width: outW, height: outH);
  for (var v = 0; v < outH; v++) {
    final lat = math.pi / 2 - (v + 0.5) / outH * math.pi;
    for (var u = 0; u < outW; u++) {
      final lon = (u + 0.5) / outW * 2 * math.pi - math.pi;
      // 最近扇区与相对经度
      final fi = lon / sector;
      final idx = fi.round();
      final lonRel = wrap(lon - idx * sector); // ∈ [-sector/2, sector/2]
      final i0 = ((idx % n) + n) % n;

      final edge = sector / 2 - lonRel.abs(); // 距扇区边界的距离
      if (edge >= blendHalf) {
        // 扇区腹地：纯当前图
        final (r0, g0, b0) = samplePlanet(i0, lonRel, lat);
        out.setPixelRgb(u, v, r0, g0, b0);
      } else {
        // 混合带：与相邻扇区 smoothstep 渐变
        final neighbor = lonRel > 0 ? (i0 + 1) % n : (i0 - 1 + n) % n;
        final lonRelN =
            lonRel > 0 ? lonRel - sector : lonRel + sector; // 邻图相对经度
        final t0 = (edge / blendHalf + 1) / 2; // 边界处 0.5，带内缘 1
        final w = t0 * t0 * (3 - 2 * t0);
        final (ra, ga, ba) = samplePlanet(i0, lonRel, lat);
        final (rb, gb, bb) = samplePlanet(neighbor, lonRelN, lat);
        out.setPixelRgb(
          u,
          v,
          (ra * w + rb * (1 - w)).round(),
          (ga * w + gb * (1 - w)).round(),
          (ba * w + bb * (1 - w)).round(),
        );
      }
    }
  }

  File(outPath).writeAsBytesSync(img.encodeJpg(out, quality: 90));
  stderr.writeln('已生成 $outPath ($outW x $outH，$n 图扇区合成)');
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
