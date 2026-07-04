import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/main.dart';
import 'package:novel_app/presentation/home/home_page.dart';
import 'package:novel_app/presentation/home/planet_view.dart';
import 'package:novel_app/presentation/shared/quick_capture/capture_button_prefs.dart';

/// 阶段二 widget 测试：全局双速记按钮 + 文字输入弹层
void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// 以测试替身（内存库 + mock 偏好）启动整个 App
  Future<void> pumpApp(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          // 首页的三路数据一律 override：真 drift 流会挂死，
          // shader/纹理是真实 IO 也会挂（2026-07-02 教训）
          novelsProvider.overrideWith((ref) => Stream.value(const [])),
          inspirationPoolProvider.overrideWith((ref) => Stream.value(const [])),
          planetAssetsProvider.overrideWith(
            (ref, planet) => Completer<PlanetShaderAssets>().future,
          ),
        ],
        child: const NovelApp(),
      ),
    );
  }

  final voiceBtn = find.byKey(const Key('语音速记按钮'));
  final textBtn = find.byKey(const Key('文字速记按钮'));

  group('双速记按钮', () {
    testWidgets('任何界面均显示双按钮，默认左语音右文字', (tester) async {
      await pumpApp(tester);

      expect(voiceBtn, findsOneWidget);
      expect(textBtn, findsOneWidget);

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        tester.getCenter(voiceBtn).dx,
        lessThan(screenWidth / 2),
        reason: '默认语音按钮在左半屏',
      );
      expect(
        tester.getCenter(textBtn).dx,
        greaterThan(screenWidth / 2),
        reason: '默认文字按钮在右半屏',
      );
    });

    testWidgets('长按互换位置，且偏好持久化', (tester) async {
      await pumpApp(tester);

      await tester.longPress(voiceBtn);
      await tester.pumpAndSettle();

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        tester.getCenter(voiceBtn).dx,
        greaterThan(screenWidth / 2),
        reason: '互换后语音按钮到右侧',
      );
      expect(
        tester.getCenter(textBtn).dx,
        lessThan(screenWidth / 2),
        reason: '互换后文字按钮到左侧',
      );

      // 偏好已写入持久化存储（重启后仍生效的依据）
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('voice_button_on_left'), isFalse);
    });
  });

  group('文字输入弹层', () {
    testWidgets('弹层打开期间隐藏双按钮，关闭后恢复', (tester) async {
      await pumpApp(tester);

      await tester.tap(textBtn);
      await tester.pumpAndSettle();
      expect(voiceBtn, findsNothing, reason: '弹层打开时按钮应隐藏，避免遮挡');
      expect(textBtn, findsNothing);

      // 点弹层外区域关闭
      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();
      expect(voiceBtn, findsOneWidget, reason: '弹层关闭后按钮应恢复');
      expect(textBtn, findsOneWidget);
    });

    testWidgets('点文字按钮弹层出现，输入保存后灵感入池、弹层关闭', (tester) async {
      await pumpApp(tester);

      await tester.tap(textBtn);
      await tester.pumpAndSettle();

      final input = find.byKey(const Key('灵感输入框'));
      expect(input, findsOneWidget, reason: '弹层应出现输入框');

      await tester.enterText(input, '深夜的一个灵感');
      await tester.tap(find.byKey(const Key('灵感保存按钮')));
      await tester.pumpAndSettle();

      expect(input, findsNothing, reason: '保存后弹层应关闭');

      // 灵感应入池：section_id 为 NULL
      final all = await db.select(db.inspirations).get();
      expect(all.single.content, '深夜的一个灵感');
      expect(all.single.sectionId, isNull, reason: '速记灵感直接入魔毯');
    });

    testWidgets('空内容点保存不入库、弹层不关闭', (tester) async {
      await pumpApp(tester);

      await tester.tap(textBtn);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('灵感输入框')), '   ');
      await tester.tap(find.byKey(const Key('灵感保存按钮')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('灵感输入框')),
        findsOneWidget,
        reason: '空内容不应关闭弹层',
      );
      final all = await db.select(db.inspirations).get();
      expect(all, isEmpty, reason: '空内容不应入库');
    });
  });
}
