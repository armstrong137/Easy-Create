import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('透明留白裁切不损失小叶片滤波内容', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        await File(
          'assets/tree_scene/illustrated/leaf_detail.png',
        ).readAsBytes(),
        targetWidth: 512,
      );
      final leaf = (await codec.getNextFrame()).image;
      codec.dispose();
      Future<ByteData> render(Rect source, double scale, double angle) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawAtlas(
          leaf,
          [
            ui.RSTransform.fromComponents(
              rotation: angle,
              scale: scale,
              anchorX: 256 - source.left,
              anchorY: 512 * .82 - source.top,
              translateX: 64,
              translateY: 64,
            ),
          ],
          [source],
          null,
          null,
          null,
          Paint()..filterQuality = FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final bytes = (await image.toByteData())!;
        image.dispose();
        picture.dispose();
        return bytes;
      }

      var maximum = 0;
      for (final scale in [.001, .002, .005, .01, .03, .07, .1, .3]) {
        for (final angle in [0.0, .5, 1.7]) {
          final full = await render(
            const Rect.fromLTWH(0, 0, 512, 512),
            scale,
            angle,
          );
          final cropped = await render(
            const Rect.fromLTRB(128, 48, 400, 472),
            scale,
            angle,
          );
          for (var index = 0; index < full.lengthInBytes; index++) {
            maximum = math.max(
              maximum,
              (full.getUint8(index) - cropped.getUint8(index)).abs(),
            );
          }
        }
      }
      leaf.dispose();
      expect(maximum, lessThanOrEqualTo(2));
    });
  });
}
