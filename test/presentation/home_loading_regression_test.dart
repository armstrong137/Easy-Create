import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final homePage = File(
    'lib/presentation/home/home_page.dart',
  ).readAsStringSync();

  test('outline route waits for snapshot and stand-in is not black', () {
    expect(homePage, contains('_openOutline'));
    expect(homePage, contains('_awaitSnapshotBeforeRoute'));
    expect(homePage, contains('_snapshotCompleter'));
    expect(homePage, contains('Duration(milliseconds: 90)'));
    expect(homePage, contains('planet: novel.planet'));
    expect(homePage, isNot(contains('Color(0xFF0E1B33)')));
  });

  test('stand-in sits ABOVE the scene so fresh iframe never flashes black', () {
    // 返回大纲后 iframe 新建，three.js 出图前是黑的；替身必须在场景之上
    // 才能盖住黑帧（回来黑一秒的根因）。用 Stack 子序验证：
    // PlanetScene 先出现、standIn 后出现（后者在上层）。
    final scenePos = homePage.indexOf('child: PlanetScene(');
    final standInPos = homePage.lastIndexOf('standIn,');
    expect(scenePos, greaterThan(0));
    expect(standInPos, greaterThan(scenePos),
        reason: 'standIn 必须排在 PlanetScene 之后（Stack 上层）');
  });

  test('brand title style is shared by boot cover and create title', () {
    expect(homePage, contains('_brandTitleStyle'));
    expect(homePage, contains('_brandTitleStyle(fontSize: 34'));
    expect(homePage, contains('_brandTitleStyle(fontSize: 26'));
    expect(homePage, contains("fontFamily: 'EasyCreateBrand'"));
    expect(homePage, isNot(contains("fontFamily: 'serif'")));
    expect(
      File('assets/fonts/CormorantGaramond-SemiBoldItalic.ttf').existsSync(),
      isTrue,
    );
    expect(File('assets/fonts/CormorantGaramond-OFL.txt').existsSync(), isTrue);
  });

  test('create title visibility follows min zoom instead of page lock', () {
    expect(homePage, contains('planetCreateTitleVisible'));
    expect(homePage, contains('_syncCreateTitleVisibility'));
    expect(homePage, contains('planetCreateTitleVisible.value = _zoom <='));
    expect(homePage, contains('valueListenable: planetCreateTitleVisible'));
  });

  test('quick capture popup keeps web planet scene mounted', () {
    expect(homePage, contains('captureSheetOpenProvider'));
    expect(homePage, contains('routeCurrent || popupOpen'));
    expect(homePage, contains('!showScene && !popupOpen && _sceneReady'));
  });

  test('quick capture sheets keep the planet readable behind input', () {
    final textSheet = File(
      'lib/presentation/shared/quick_capture/text_capture_sheet.dart',
    ).readAsStringSync();
    final voiceSheet = File(
      'lib/presentation/shared/quick_capture/voice_capture_sheet.dart',
    ).readAsStringSync();

    expect(textSheet, contains('barrierColor: kCaptureSheetBarrierColor'));
    expect(voiceSheet, contains('barrierColor: kCaptureSheetBarrierColor'));
  });
}
