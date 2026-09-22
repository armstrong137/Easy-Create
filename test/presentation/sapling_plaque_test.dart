import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/sapling_plaque.dart';

void main() {
  test('幼树牌面在手机与宽屏内且始终位于树干左侧', () {
    for (final size in [
      const Size(360, 800),
      const Size(430, 932),
      const Size(910, 800),
    ]) {
      final rect = saplingPlaqueRect(size);
      expect(rect.left, greaterThan(0));
      expect(rect.right, lessThan(size.width / 2));
      expect(rect.bottom, lessThan(size.height));
      expect(rect.width, greaterThan(45));
    }
  });
  testWidgets('一体化牌面仅绘制标题，不叠加枝牌图像', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 60,
          height: 90,
          child: SaplingPlaqueTitle(title: '引子', selected: true),
        ),
      ),
    );
    expect(find.text('引\n子'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
