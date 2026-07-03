import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/creative_energy.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/main.dart';
import 'package:novel_app/presentation/home/home_page.dart';
import 'package:novel_app/presentation/home/planet_view.dart';
import 'package:novel_app/presentation/home/starfield.dart';
import 'package:novel_app/presentation/shared/quick_capture/capture_button_prefs.dart';

/// 阶段三·1：首页星空与创作能量联动
///
/// 注意：这里 override 灵感池 provider 注入固定数据，绝不让真 drift 流
/// 进入 widget 测试——drift 查询流在 FakeAsync 拆卸时的 pending timer
/// 会挂死整个测试进程（2026-07-02 教训，详见项目记忆）。
/// drift 流本身的正确性由 test/data/repositories_test.dart 覆盖。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 造一条测试灵感（只有数量影响亮度，内容无关紧要）
  Inspiration fakeInspiration(int id) => Inspiration(
        id: id,
        content: '灵感$id',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
        cardOrder: 0,
      );

  Future<void> pumpApp(WidgetTester tester,
      {required List<Inspiration> pool}) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // 固定数据流：立即发出并结束，无 pending timer
          inspirationPoolProvider.overrideWith((ref) => Stream.value(pool)),
          // shader/纹理是真实 IO，FakeAsync 中会挂死——注入永不完成的
          // Future 让星球分支不渲染；shader 渲染由模拟器冒烟验证
          planetAssetsProvider.overrideWith(
              (ref, planet) => Completer<PlanetShaderAssets>().future),
        ],
        child: const NovelApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首页显示星空，零灵感时亮度为下限（最暗）', (tester) async {
    await pumpApp(tester, pool: const []);

    final starfield = tester.widget<Starfield>(find.byType(Starfield));
    expect(starfield.brightness, kStarBrightnessMin);
  });

  testWidgets('灵感入池后星空变亮且不超上限', (tester) async {
    await pumpApp(tester, pool: [fakeInspiration(1), fakeInspiration(2)]);

    final starfield = tester.widget<Starfield>(find.byType(Starfield));
    expect(starfield.brightness, greaterThan(kStarBrightnessMin),
        reason: '有创作量后星光应高于下限');
    expect(starfield.brightness, lessThanOrEqualTo(kStarBrightnessMax));
  });
}
