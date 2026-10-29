import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';

void main() {
  test('主树由同一根部连续延伸，枝叶随树龄生成', () {
    final young = OrganicTreeFrame(.2);
    final middle = OrganicTreeFrame(.55);
    final mature = OrganicTreeFrame(1);
    for (final frame in [young, middle, mature]) {
      expect(frame.wood.contains(const Offset(490, 1410)), isTrue);
    }
    expect(
      young.wood.getBounds().top,
      greaterThan(middle.wood.getBounds().top),
    );
    expect(
      middle.wood.getBounds().top,
      greaterThan(mature.wood.getBounds().top),
    );
    expect(mature.leaves.length, greaterThan(middle.leaves.length));
    expect(
      OrganicTreeFrame(.551).wood.getBounds().top - middle.wood.getBounds().top,
      inInclusiveRange(-10, 0),
    );
  });

  testWidgets('渲染主树连续形态美术样件', (tester) async {
    await tester.runAsync(() async {
      Future<ui.Image> load(String file) async {
        final codec = await ui.instantiateImageCodec(
          await File(file).readAsBytes(),
          targetWidth: 512,
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return image;
      }

      final bark = await load('assets/tree_scene/illustrated/bark_detail.png');
      final leaf = await load('assets/tree_scene/illustrated/leaf_detail.png');
      for (final age in [.2, .55, 1.0]) {
        final recorder = ui.PictureRecorder();
        OrganicTreeStudyPainter(
          age,
          bark,
          leaf,
        ).paint(Canvas(recorder), const Size(941, 1672));
        final picture = recorder.endRecording();
        final image = await picture.toImage(941, 1672);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        if (const bool.fromEnvironment('WRITE_TREE_STUDY')) {
          final output = Directory('build/qa/main-tree-study')
            ..createSync(recursive: true);
          await File(
            '${output.path}/age_${(age * 100).round()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        }
        image.dispose();
        picture.dispose();
      }
      bark.dispose();
      leaf.dispose();
    });
  });
}
