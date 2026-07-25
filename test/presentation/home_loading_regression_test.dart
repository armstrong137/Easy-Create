import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final homePage = File(
    'lib/presentation/home/home_page.dart',
  ).readAsStringSync();

  test('outline route waits for snapshot and stand-in is not black', () {
    expect(homePage, contains('_openOutline'));
    expect(homePage, contains('_awaitSnapshotBeforeRoute'));
    expect(homePage, contains('_sharedSnapshotCompleter'));
    expect(homePage, contains('Duration(milliseconds: 90)'));
    expect(homePage, contains('planet: novel.planet'));
    expect(homePage, isNot(contains('Color(0xFF0E1B33)')));
  });

  test(
    'shared scene sits behind page stand-in so switching never exposes black',
    () {
      // 返回大纲后 iframe 新建，three.js 出图前可能是黑的；替身必须在场景之上。
      final sharedScenePos = homePage.indexOf('_SharedPlanetSceneLayer(');
      final pageViewPos = homePage.indexOf('PageView.builder');
      expect(sharedScenePos, greaterThan(0));
      expect(
        pageViewPos,
        greaterThan(sharedScenePos),
        reason: '共享 PlanetScene 必须先于 PageView，页面替身才能遮住切换黑帧',
      );
      expect(homePage, contains('onSharedSceneConfig'));
      expect(homePage, contains('sharedSceneReady'));
    },
  );

  test(
    'outline navigation keeps scene alive — no readiness reset before route',
    () {
      // 彻底方案（2026-07-11）：进大纲不销毁 iframe、也**不复位** _sceneReady。
      // iframe 仅被 display:none + 暂停，场景全程存活；返回时 _sceneReady 仍为真
      //  → 替身恒透明 → 直接露出活场景，零重建、零 1 秒加载、零黑帧。
      final openOutlinePos = homePage.indexOf('Future<void> _openOutline');
      final pushPos = homePage.indexOf(
        'Navigator.of(context).push',
        openOutlinePos,
      );
      final resetPos = homePage.indexOf(
        '_markSceneNotReady();',
        openOutlinePos,
      );
      expect(openOutlinePos, greaterThan(0));
      expect(pushPos, greaterThan(openOutlinePos));
      // push 之前绝不能出现 _markSceneNotReady（否则返回会先露替身/黑帧）
      expect(
        resetPos == -1 || resetPos > pushPos,
        isTrue,
        reason: '进大纲不复位就绪：场景不销毁，返回即露活场景',
      );
    },
  );

  test(
    'scene reveal is delayed after ready so black first frames stay covered',
    () {
      expect(homePage, contains('_scheduleSceneReveal'));
      expect(homePage, contains('_sceneRevealTimer'));
      expect(homePage, contains('Duration(milliseconds: 220)'));
      expect(homePage, contains('onReady: _onPlanetSceneReady'));
      // 揭幕回调带回已接管星球名：只在场景真正换到当前页星球时才淡出替身
      expect(homePage, contains('void _onPlanetSceneReady(String readyPlanet)'));
    },
  );

  test(
    'web iframe canvas stays transparent until real textured frame is ready',
    () {
      final sceneHtml = File(
        'assets/planet_scene/index.html',
      ).readAsStringSync();
      final webWrapper = File(
        'lib/presentation/home/planet_scene/planet_scene_web.dart',
      ).readAsStringSync();

      expect(sceneHtml, contains('canvas { display: block; opacity: 0;'));
      expect(sceneHtml, contains("renderer.domElement.style.opacity = '1'"));
      expect(sceneHtml, contains('if (!baseTextureReady) return;'));
      expect(webWrapper, contains("..style.backgroundColor = 'transparent'"));
    },
  );

  test(
    'planet stand-in textures are precached before direct page switching',
    () {
      expect(homePage, contains('_precachePlanetStandIns'));
      expect(homePage, contains('for (final planet in kPlanetTextures)'));
      expect(
        homePage,
        contains("precacheImage(AssetImage('assets/textures/\$planet.jpg')"),
      );
      expect(
        homePage,
        contains("AssetImage('assets/planet_scene/standins/\$planet.png')"),
      );
    },
  );

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
    expect(
      homePage,
      contains('enabled: !_zoomed && (!use3D || widget.sharedSceneReady)'),
    );
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

  test('quick capture popup keeps shared web planet scene mounted', () {
    expect(homePage, contains('captureSheetOpenProvider'));
    expect(homePage, contains('routeCurrent || popupOpen'));
    expect(homePage, contains('visible: routeCurrent || popupOpen'));
  });

  test('A: web scene is hidden+paused on navigation, not destroyed', () {
    final web = File(
      'lib/presentation/home/planet_scene/planet_scene_web.dart',
    ).readAsStringSync();
    // 进/出大纲切 iframe display 而非 remove；仅真正卸载才 dispose
    expect(
      web,
      contains("_iframe?.style.display = widget.visible ? '' : 'none'"),
    );
    expect(
      web,
      contains('bool get _shouldRender => widget.active && widget.visible'),
    );
    // home 用 sceneVisible（当前页 且 首页在顶/弹层打开）驱动 visible
    expect(homePage, contains('visible: routeCurrent || popupOpen'));
  });

  test('A: io scene mirrors visible param for pause/resume parity', () {
    final io = File(
      'lib/presentation/home/planet_scene/planet_scene_io.dart',
    ).readAsStringSync();
    expect(io, contains('final bool visible'));
    expect(io, contains("now ? 'resumeRender()' : 'pauseRender()'"));
  });

  test(
    'D: homepage owns exactly one shared PlanetScene to avoid iOS Safari OOM',
    () {
      expect(homePage, contains('_SharedPlanetSceneLayer'));
      expect(homePage, isNot(contains('static const _kMaxAliveScenes')));
      expect(homePage, isNot(contains('final List<int> _aliveNovelIds')));
      expect(homePage, isNot(contains('void _touchAliveScene(int novelId)')));
      expect(homePage, isNot(contains('widget.keptAlive')));

      final pageViewStart = homePage.indexOf('PageView.builder');
      final settingsStart = homePage.indexOf('// 左上角设置入口', pageViewStart);
      final pageViewBlock = homePage.substring(pageViewStart, settingsStart);
      expect(pageViewBlock, isNot(contains('PlanetScene(')));
      // 替身只在未就绪（冷启动/上下文异常）时露出；正常切星球不盖替身
      expect(homePage, contains('opacity: widget.sharedSceneReady ? 0 : 1'));
    },
  );

  test('E: 切星球共享场景原地换贴图（不重载/不盖替身/复用视角）', () {
    final sceneHtml = File('assets/planet_scene/index.html').readAsStringSync();
    final web = File(
      'lib/presentation/home/planet_scene/planet_scene_web.dart',
    ).readAsStringSync();
    // setPlanet 不再 disposeScene+location.replace（"变脸"根源），而是原地重建本体
    expect(sceneHtml, contains('function mountPlanet'));
    expect(sceneHtml, contains('function preloadPlanetTextures'));
    expect(sceneHtml, contains("postMessage('planetReady:'"));
    final setPlanetStart = sceneHtml.indexOf('window.setPlanet = function');
    final setPlanetBody = sceneHtml.substring(
      setPlanetStart,
      sceneHtml.indexOf('window.addEventListener', setPlanetStart),
    );
    expect(setPlanetBody, isNot(contains('location.replace')));
    expect(setPlanetBody, isNot(contains('disposeScene()')));
    // 切星球合并下发当前视角，避免新星球先按默认角度亮一帧
    expect(web, contains("'planet': widget.planet"));
    expect(web, contains("'yaw': widget.yaw"));
    expect(web, contains("'zoom': widget.zoom"));
    // 切页不复位就绪（不盖替身）
    expect(homePage, isNot(contains('_markSceneNotReady')));
  });

  test('F: 删除当前页星球后用 safePage 判定 active，杜绝残留删除前那颗', () {
    // 删掉当前页星球后 PageView 不回调 onPageChanged，_currentPage 越界。active
    // 若仍用 _currentPage，剩余页( i=0 )反而非 active，不会把新星球配置发给共享
    // 场景，画面残留删除前那颗（"地球变火星"）。故 active 必须用 clamp 出的 safePage。
    expect(
      homePage,
      contains('final safePage = novels.isEmpty'),
      reason: 'build 里要统一算出安全页码',
    );
    expect(homePage, contains('_currentPage.clamp(0, novels.length - 1)'));
    expect(
      homePage,
      contains('active: i == safePage'),
      reason: 'active 必须用回正后的 safePage，而非可能越界的 _currentPage',
    );
    expect(
      homePage,
      isNot(contains('active: i == _currentPage')),
      reason: '越界的 _currentPage 会让删除后剩余页非 active → 残留删除前那颗',
    );
    // 越界时下一帧把控制器与状态一并回正
    expect(homePage, contains('_pageController.jumpToPage(safePage)'));
  });

  test('B: stand-in uses the pre-rendered real snapshot, not a flat crop', () {
    // 替身底图是每颗星球的预渲染真身快照（three.js 同款一帧），与真实场景
    // 视觉一致，消除"平面/简球 → 精球"的 2D 突变（用户录屏残留问题的根治）。
    expect(homePage, contains('planet: novel.planet'));
    expect(homePage, contains("'assets/planet_scene/standins/\$planet.png'"));
    // 替身只有这一层预渲染真身图（预解码的 AssetImage，同步出画、无透明缝）。
    // 曾叠一层运行时低清快照 + frameBuilder 淡入，已移除——那张图全局共用一张、
    // 仅 480px，切星球时会露出"很糊的地球"（用户实测），底图更清晰且永远对。
    expect(homePage, isNot(contains('frameBuilder:')));
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

  test(
    'C: scene reveal has a fallback timer so it never sticks on stand-in',
    () {
      expect(homePage, contains('Timer? _sceneFallbackTimer'));
      expect(homePage, contains('_armSceneRevealFallback'));
      // 冷启动首个 config 未就绪时启动兜底揭幕定时器
      expect(
        homePage,
        contains(
          'if (firstConfig && !_sharedSceneReady) _armSceneRevealFallback()',
        ),
      );
      // 兜底是**周期检查 + 硬上限**：只有场景长时间零就绪信号才最后强揭幕，
      // 绝不在场景还没换到当前页星球时（慢设备加载中）就淡出替身露出错星球。
      expect(homePage, contains('Timer.periodic(const Duration(milliseconds: 700)'));
      expect(homePage, contains('DateTime.now().add(const Duration(seconds: 10))'));
    },
  );

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
