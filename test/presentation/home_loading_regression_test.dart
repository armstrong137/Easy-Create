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
    // 返回大纲后 iframe 新建，three.js 出图前可能是黑的；替身必须在场景之上。
    final scenePos = homePage.indexOf('child: PlanetScene(');
    final standInPos = homePage.lastIndexOf('standIn,');
    expect(scenePos, greaterThan(0));
    expect(
      standInPos,
      greaterThan(scenePos),
      reason: 'standIn 必须排在 PlanetScene 之后，位于 Stack 上层',
    );
  });

  test('outline navigation keeps scene alive — no readiness reset before route', () {
    // 彻底方案（2026-07-11）：进大纲不销毁 iframe、也**不复位** _sceneReady。
    // iframe 仅被 display:none + 暂停，场景全程存活；返回时 _sceneReady 仍为真
    //  → 替身恒透明 → 直接露出活场景，零重建、零 1 秒加载、零黑帧。
    final openOutlinePos = homePage.indexOf('Future<void> _openOutline');
    final pushPos = homePage.indexOf(
      'Navigator.of(context).push',
      openOutlinePos,
    );
    final resetPos = homePage.indexOf('_markSceneNotReady();', openOutlinePos);
    expect(openOutlinePos, greaterThan(0));
    expect(pushPos, greaterThan(openOutlinePos));
    // push 之前绝不能出现 _markSceneNotReady（否则返回会先露替身/黑帧）
    expect(
      resetPos == -1 || resetPos > pushPos,
      isTrue,
      reason: '进大纲不复位就绪：场景不销毁，返回即露活场景',
    );
  });

  test(
    'scene reveal is delayed after ready so black first frames stay covered',
    () {
      expect(homePage, contains('_scheduleSceneReveal'));
      expect(homePage, contains('_sceneRevealTimer'));
      expect(homePage, contains('Duration(milliseconds: 220)'));
      expect(homePage, contains('onReady: _scheduleSceneReveal'));
    },
  );

  test(
    'web iframe canvas stays transparent until real textured frame is ready',
    () {
      final sceneHtml = File('assets/planet_scene/index.html').readAsStringSync();
      final webWrapper = File(
        'lib/presentation/home/planet_scene/planet_scene_web.dart',
      ).readAsStringSync();

      expect(sceneHtml, contains('canvas { display: block; opacity: 0;'));
      expect(sceneHtml, contains("renderer.domElement.style.opacity = '1'"));
      expect(sceneHtml, contains('if (!baseTextureReady) return;'));
      expect(webWrapper, contains("..style.backgroundColor = 'transparent'"));
    },
  );

  test('planet stand-in textures are precached before direct page switching', () {
    expect(homePage, contains('_precachePlanetStandIns'));
    expect(homePage, contains('for (final planet in kPlanetTextures)'));
    expect(homePage, contains("precacheImage(AssetImage('assets/textures/\$planet.jpg')"));
    expect(
      homePage,
      contains("AssetImage('assets/planet_scene/standins/\$planet.png')"),
    );
  });

  test(
    'planet long press delete only works at normal size with one pointer',
    () {
      expect(homePage, contains('_canDeleteByLongPress'));
      expect(homePage, contains('_zoom <= kPlanetCreateTitleShowZoom'));
      expect(homePage, contains('_pinchStartDist <= 0'));
      expect(homePage, contains('if (!_canDeleteByLongPress) return;'));
    },
  );

  test('orbiting inspirations stay paused until 3D scene is stable', () {
    expect(homePage, contains('enabled: !_zoomed && (!use3D || _sceneReady)'));
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
    // 弹层打开时 sceneVisible 仍真 → iframe 不隐藏；只有页面真正卸载才复位就绪
    expect(homePage, contains('if (!sceneMounted && _sceneReady)'));
  });

  test('A: web scene is hidden+paused on navigation, not destroyed', () {
    final web = File(
      'lib/presentation/home/planet_scene/planet_scene_web.dart',
    ).readAsStringSync();
    // 进/出大纲切 iframe display 而非 remove；仅真正卸载才 dispose
    expect(web, contains("_iframe?.style.display = widget.visible ? '' : 'none'"));
    expect(
      web,
      contains('bool get _shouldRender => widget.active && widget.visible'),
    );
    // home 用 sceneVisible（首页在顶或弹层打开）驱动 visible
    expect(homePage, contains('final sceneVisible = routeCurrent || popupOpen'));
    expect(homePage, contains('visible: sceneVisible'));
  });

  test('A: io scene mirrors visible param for pause/resume parity', () {
    final io = File(
      'lib/presentation/home/planet_scene/planet_scene_io.dart',
    ).readAsStringSync();
    expect(io, contains('final bool visible'));
    expect(io, contains("now ? 'resumeRender()' : 'pauseRender()'"));
  });

  test('B: stand-in uses the pre-rendered real snapshot, not a flat crop', () {
    // 替身底图是每颗星球的预渲染真身快照（three.js 同款一帧），与真实场景
    // 视觉一致，消除"平面/简球 → 精球"的 2D 突变（用户录屏残留问题的根治）。
    expect(homePage, contains('planet: novel.planet'));
    expect(
      homePage,
      contains("'assets/planet_scene/standins/\$planet.png'"),
    );
    // 快照补 frameBuilder：解码完成前透明露底快照，杜绝透明缝黑帧
    expect(homePage, contains('frameBuilder:'));
    // _PlanetStandIn 内部不再贴平面世界地图裁剪
    final standInClass = homePage.substring(
      homePage.indexOf('class _PlanetStandIn'),
    );
    expect(standInClass, isNot(contains("Image.asset('assets/textures/")));
    // 预渲染快照要预解码，切星球首帧即出
    expect(
      homePage,
      contains("AssetImage('assets/planet_scene/standins/\$planet.png')"),
    );
  });

  test('C: scene reveal has a fallback timer so it never sticks on stand-in', () {
    expect(homePage, contains('Timer? _sceneFallbackTimer'));
    expect(homePage, contains('_armSceneRevealFallback'));
    expect(homePage, contains('if (sceneMounted && !_sceneReady)'));
    expect(homePage, contains('Duration(milliseconds: 3000)'));
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
