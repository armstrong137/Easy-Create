import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const evidenceRoot = 'docs/ui_review/rounds/2026-08-10/tree-3d';

  test('3D 场景 QA 控制台覆盖核心验收场景', () {
    final harness = File('tools/tree_scene/qa_harness.html');
    expect(harness.existsSync(), isTrue);
    final source = harness.readAsStringSync();
    for (final scenario in [
      'empty',
      'chapter-1',
      'chapter-10',
      'chapter-40',
      'stress-40x12',
      'add-chapter',
      'add-section-early',
      'add-section-mature',
      'delete-chapter',
      'delete-section',
      'focus-history',
      'drag-inspiration',
      'background-restore',
    ]) {
      expect(source, contains('data-scenario="$scenario"'));
    }
  });

  for (final size in [(390, 844), (430, 932), (768, 1024)]) {
    test('${size.$1}x${size.$2} 成熟树浏览器证据非空且主体不贴边', () {
      final file = File('$evidenceRoot/mature-${size.$1}x${size.$2}.jpg');
      expect(file.existsSync(), isTrue, reason: '缺少该尺寸的真实浏览器截图');
      final image = img.decodeImage(file.readAsBytesSync())!;
      expect(image.width, size.$1);
      expect(image.height, size.$2);

      var nonBackground = 0;
      var edgeContent = 0;
      final edge = (image.width * 0.02).round();
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final distance =
              (pixel.r - 253).abs() +
              (pixel.g - 246).abs() +
              (pixel.b - 236).abs();
          if (distance < 28) continue;
          nonBackground++;
          if (x < edge || x >= image.width - edge) edgeContent++;
        }
      }
      expect(nonBackground, greaterThan(image.width * image.height * 0.08));
      expect(
        edgeContent / nonBackground,
        lessThan(0.015),
        reason: '树体或标签不应被屏幕左右边缘裁切',
      );
    });
  }
}
