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

  test('成熟树树冠丰满且四周保留安全边', () {
    final image = img.decodeWebP(
      File('assets/tree_scene/standins/age_5.webp').readAsBytesSync(),
    )!;
    var left = image.width;
    var right = 0;
    var top = image.height;
    var bottom = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a <= 20) continue;
        left = x < left ? x : left;
        right = x > right ? x : right;
        top = y < top ? y : top;
        bottom = y > bottom ? y : bottom;
      }
    }
    final safeX = image.width * 0.025;
    expect(left, greaterThanOrEqualTo(safeX), reason: '成熟树不能碰到左边界');
    expect(
      right,
      lessThanOrEqualTo(image.width - safeX),
      reason: '成熟树不能碰到右边界',
    );

    final crownBottom = top + ((bottom - top) * 0.65).round();
    var rowSpanTotal = 0.0;
    var populatedRows = 0;
    for (var y = top; y <= crownBottom; y++) {
      var rowLeft = image.width;
      var rowRight = 0;
      for (var x = left; x <= right; x++) {
        if (image.getPixel(x, y).a <= 20) continue;
        rowLeft = x < rowLeft ? x : rowLeft;
        rowRight = x > rowRight ? x : rowRight;
      }
      if (rowLeft > rowRight) continue;
      rowSpanTotal += (rowRight - rowLeft + 1) / (right - left + 1);
      populatedRows++;
    }
    expect(
      rowSpanTotal / populatedRows,
      greaterThanOrEqualTo(0.58),
      reason: '成熟树冠必须宽而丰满，不能是烛台或仙人掌轮廓',
    );
  });
}
