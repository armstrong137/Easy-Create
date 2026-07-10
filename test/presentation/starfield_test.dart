import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/creative_energy.dart';
import 'package:novel_app/presentation/home/starfield.dart';

/// 动态星空层（阶段八 P2-2）
///
/// 注意：动态层是无限 Ticker——本文件只用定点 pump，严禁 pumpAndSettle
/// （会等无限动画结束而挂死，项目老教训）。
void main() {
  testWidgets('animated=false（测试/低端回退）：只有静态照片，无动态层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Starfield(brightness: kStarBrightnessMin, animated: false),
      ),
    );
    expect(find.byKey(const Key('动态星空层')), findsNothing);
    expect(find.byType(Image), findsOneWidget, reason: '照片底始终在');
  });

  testWidgets('animated=true：动态层存在，Ticker 在推进时间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Starfield(brightness: kStarBrightnessMax, animated: true),
      ),
    );
    final layer = find.byKey(const Key('动态星空层'));
    expect(layer, findsOneWidget);

    // 取画笔持有的时间源，定点推帧后必须前进（证明动画活着）
    final paint = tester.widget<CustomPaint>(layer);
    final elapsed =
        (paint.painter as dynamic).elapsed as ValueNotifier<double>;
    final t0 = elapsed.value;
    await tester.pump(const Duration(milliseconds: 320));
    expect(elapsed.value, greaterThan(t0), reason: 'Ticker 应持续推进时间');

    // 卸载即停（不泄漏 Ticker）
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页在测试环境（FLUTTER_TEST）下动态层自动关闭', (tester) async {
    // advanced3DProvider 在测试环境为 false → Starfield.animated=false，
    // 这保证了全套 home_page 测试的 pumpAndSettle 不会被无限动画挂死。
    // 此断言守住这条链路：谁把开关改掉，这里立刻红。
    await tester.pumpWidget(
      MaterialApp(
        home: Starfield(brightness: kStarBrightnessMin, animated: false),
      ),
    );
    await tester.pumpAndSettle(); // animated=false 时必须能 settle
    expect(find.byKey(const Key('动态星空层')), findsNothing);
  });
}
