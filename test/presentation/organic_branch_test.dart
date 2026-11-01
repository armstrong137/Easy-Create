import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_branch.dart';

void main() {
  test('完整中心线复用后仍按当前粗细收尖，伸展中不沿用完整位置', () {
    final spine = Path()..moveTo(20, 180)..cubicTo(60, 150, 140, 20, 240, 70);
    final completed = OrganicBranchPainter.sampleStem(spine, 1, 16, tipRatio: .04);
    for (final growth in [0.0, .25, .75, 1.0]) {
      for (final radius in [8.0, 40.0]) {
        for (final tip in [.04, .48]) {
          final fresh = OrganicBranchPainter.sampleStem(spine, growth, radius, tipRatio: tip);
          final reused = OrganicBranchPainter.sampleStem(spine, growth, radius,
            tipRatio: tip, completedSections: completed);
          expect(reused, orderedEquals(fresh));
        }
      }
    }
  });
  testWidgets('枝梢连续延伸且不移动根部，左右镜像保持同样生长量', (tester) async {
    await tester.runAsync(() async {
      Future<({int left, int right, int pixels})> bounds(
        double progress,
        bool right,
      ) async {
        final recorder = ui.PictureRecorder();
        OrganicBranchPainter(
          progress,
          right,
          null,
        ).paint(Canvas(recorder), const Size(300, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 200);
        final data = (await image.toByteData())!;
        var left = 300;
        var last = -1;
        var pixels = 0;
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 300; x++) {
            if (data.getUint8((y * 300 + x) * 4 + 3) < 128) continue;
            if (x < left) left = x;
            if (x > last) last = x;
            pixels++;
          }
        }
        image.dispose();
        picture.dispose();
        return (left: left, right: last, pixels: pixels);
      }

      final empty = await bounds(0, false);
      final young = await bounds(.25, false);
      final growing = await bounds(.65, false);
      final grown = await bounds(1, false);
      final mirrored = await bounds(1, true);
      expect(empty.pixels, 0);
      expect(young.left, greaterThan(growing.left));
      expect(growing.left, greaterThan(grown.left));
      expect(young.right, closeTo(300 * .88, 12));
      expect(grown.right, closeTo(300 * .88, 12));
      expect(growing.pixels, greaterThan(young.pixels));
      expect(grown.pixels, greaterThan(growing.pixels));
      expect(mirrored.pixels, closeTo(grown.pixels, 5));
    });
  });
}
