import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/core/creative_energy.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/main.dart';
import 'package:novel_app/presentation/home/home_page.dart';
import 'package:novel_app/presentation/home/planet_view.dart';
import 'package:novel_app/presentation/home/starfield.dart';
import 'package:novel_app/presentation/shared/quick_capture/capture_button_prefs.dart';

/// 阶段三：首页创作宇宙（多星球 + 能量联动）
///
/// 注意：所有 drift 流一律 overrideWith 固定 Stream——真 drift 流进
/// widget 测试会 pending timer 挂死（2026-07-02 教训，见项目记忆）；
/// shader/纹理加载是真实 IO，注入永不完成的 Future 跳过星球渲染。
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Novel fakeNovel(int id, String title, {String planet = 'earth'}) => Novel(
    id: id,
    title: title,
    planet: planet,
    sortOrder: id,
    createdAt: DateTime(2026, 7, 1),
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Novel> novels = const [],
    Stream<List<Novel>>? novelsStream,
    int creativeCount = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          novelsProvider.overrideWith(
            (ref) => novelsStream ?? Stream.value(novels),
          ),
          inspirationPoolProvider.overrideWith((ref) => Stream.value(const [])),
          creativeCountProvider.overrideWith(
            (ref, novelId) => Stream.value(creativeCount),
          ),
          globalCreativeCountProvider.overrideWith(
            (ref) => Stream.value(creativeCount),
          ),
          planetAssetsProvider.overrideWith(
            (ref, planet) => Completer<PlanetShaderAssets>().future,
          ),
        ],
        child: const NovelApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空宇宙：星空最暗 + 邀请创建文案', (tester) async {
    await pumpApp(tester);

    final starfield = tester.widget<Starfield>(find.byType(Starfield));
    expect(starfield.brightness, kStarBrightnessMin);
    expect(find.textContaining('点亮第一颗星球'), findsOneWidget);

    // 字体与全 App 统一：中文用霞鹜文楷，"Create Something" 用品牌衬线斜体
    final invite = tester.widget<Text>(find.textContaining('点亮第一颗星球'));
    expect(invite.textSpan?.style?.fontFamily, 'LXGWWenKai');
    final brandSpan = (invite.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'Create Something');
    expect(brandSpan.style?.fontFamily, 'EasyCreateBrand');
    expect(brandSpan.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('有小说且有创作量：星空亮于下限，显示书名', (tester) async {
    await pumpApp(tester, novels: [fakeNovel(1, '群星的回声')], creativeCount: 8);

    final starfield = tester.widget<Starfield>(find.byType(Starfield));
    expect(starfield.brightness, greaterThan(kStarBrightnessMin));
    expect(starfield.brightness, lessThanOrEqualTo(kStarBrightnessMax));
    expect(find.text('群星的回声'), findsOneWidget);
  });

  testWidgets('点标题弹创建对话框，输入书名确认后落库、纹理自动分配', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('创建新星球标题')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('星球名称弹窗卡片')), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);

    await tester.enterText(find.byKey(const Key('新星球书名输入框')), '第二颗行星');
    await tester.tap(find.byKey(const Key('新星球确认按钮')));
    await tester.pumpAndSettle();

    final saved = await db.select(db.novels).get();
    expect(saved.single.title, '第二颗行星');
    expect(saved.single.planet, 'earth', reason: '第 1 颗星球分配 earth 纹理');
  });

  testWidgets('拖球面转星球（不翻页）；拖球外仍可左右滑切换星球', (tester) async {
    addTearDown(() => planetZoomLock.value = false);
    await pumpApp(
      tester,
      novels: [
        fakeNovel(1, '第一颗'),
        fakeNovel(2, '第二颗', planet: 'mars'),
      ],
    );
    expect(find.text('第一颗'), findsOneWidget);

    // ① 手指落在球面上横拖：转星球，PageView 被锁住，不切页
    final center = tester.getCenter(find.byKey(const Key('星球_1')));
    final onPlanet = await tester.startGesture(center);
    await tester.pump();
    expect(planetZoomLock.value, isTrue, reason: '拖球面时锁住翻页');
    await onPlanet.moveBy(const Offset(-220, 0));
    await tester.pump();
    await onPlanet.up();
    await tester.pumpAndSettle();

    expect(find.text('第一颗'), findsOneWidget, reason: '拖球面只转星球，不该翻页');
    expect(planetZoomLock.value, isFalse, reason: '松手后解锁');

    // ② 手指落在球外（屏幕左缘）横拖：正常翻页到下一颗星球
    final size = tester.getSize(find.byType(HomePage));
    final outside = Offset(16, size.height / 2);
    await tester.dragFrom(outside, const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('第二颗'), findsOneWidget, reason: '球外横拖应切换星球');
  });

  // 惯性本身由 test/core/spin_inertia_test.dart 覆盖（滑行/衰减/钳制/停止）。
  // 这里不写"甩手后仍在重绘"的断言：hasScheduledFrame 会被其他重绘触发，
  // 去掉惯性它照样通过（已做变异验证），是个假测试。

  testWidgets('双指捏合放大星球：锁住翻页、书名让位；松手回到原大小则恢复', (tester) async {
    addTearDown(() => planetZoomLock.value = false);
    await pumpApp(tester, novels: [fakeNovel(1, '被放大的星球')]);

    expect(planetZoomLock.value, isFalse);

    // 两指同时按下屏幕，向两侧张开 → 捏合放大
    final center = tester.getCenter(find.byKey(const Key('星球_1')));
    final f1 = await tester.startGesture(center - const Offset(40, 0));
    final f2 = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    expect(planetZoomLock.value, isTrue, reason: '双指按下即锁 PageView，防误翻页');

    await f1.moveBy(const Offset(-70, 0));
    await f2.moveBy(const Offset(70, 0));
    await tester.pump();

    // 书名淡出让位（放大态）
    final title = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(const Key('书名_1')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(title.opacity, 0, reason: '放大后书名应淡出');

    // 顶部 Create Something 标题也让位（放大观察时不压星球——用户反馈）
    final appTitle = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(const Key('创建新星球标题')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(appTitle.opacity, 0, reason: '放大后顶部标题应淡出');

    // 收回到起始间距后松手：回到原大小，解锁翻页、书名归位
    await f1.moveBy(const Offset(70, 0));
    await f2.moveBy(const Offset(-70, 0));
    await tester.pump();
    await f1.up();
    await f2.up();
    await tester.pumpAndSettle();

    expect(planetZoomLock.value, isFalse, reason: '松手复位后应解锁翻页');
  });

  testWidgets('星球命名框：未输入时提示语居中（左对齐显得空落）', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('创建新星球标题')));
    await tester.pumpAndSettle();

    final field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('新星球书名输入框')),
    );
    expect(field.textAlign, TextAlign.center);
    expect(field.placeholder, '这部小说叫什么？');

    // 弹窗卡片垂直居中（原顶对齐钉在状态栏下，太靠上——用户反馈）
    final card = tester.getRect(find.byKey(const Key('星球名称弹窗卡片')));
    final screen = tester.getSize(find.byType(HomePage));
    expect(
      (card.center.dy - screen.height / 2).abs(),
      lessThan(40),
      reason: '无键盘时弹窗应垂直居中',
    );
  });

  testWidgets('星球命名框：键盘弹起时不贴状态栏，保持手机友好宽度', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('创建新星球标题')));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const Key('星球名称弹窗卡片')));
    expect(
      card.top,
      greaterThanOrEqualTo(72),
      reason: 'iPhone Safari 键盘弹起后，弹窗不能被顶到状态栏下面',
    );
    expect(card.width, lessThanOrEqualTo(310), reason: '手机上弹窗不应显得过宽');
  });

  testWidgets('创建新星球成功后自动切到新星球页', (tester) async {
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            title: '第一颗',
            planet: 'earth',
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            title: '第二颗',
            planet: 'mars',
            sortOrder: 1,
            createdAt: DateTime.now(),
          ),
        );
    final novelsStream = StreamController<List<Novel>>();
    addTearDown(novelsStream.close);

    await pumpApp(tester, novelsStream: novelsStream.stream);
    novelsStream.add(await db.select(db.novels).get());
    await tester.pumpAndSettle();
    expect(find.text('第一颗'), findsOneWidget);
    expect(find.text('第三颗'), findsNothing);

    await tester.tap(find.byKey(const Key('创建新星球标题')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('新星球书名输入框')), '第三颗');
    await tester.tap(find.byKey(const Key('新星球确认按钮')));
    await tester.pump();

    var saved = await db.select(db.novels).get();
    for (var i = 0; i < 10 && saved.length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      saved = await db.select(db.novels).get();
    }
    expect(saved, hasLength(3));
    expect(saved.map((n) => n.title), contains('第三颗'));
    novelsStream.add(saved);
    await tester.pump();
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.childrenDelegate.estimatedChildCount, 3);
    expect(find.text('第三颗'), findsOneWidget);
  });

  testWidgets('长按星球弹出删除确认，确认后删除小说', (tester) async {
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            title: '待删除星球',
            planet: 'earth',
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
    await pumpApp(tester, novels: [fakeNovel(1, '待删除星球')]);

    await tester.longPress(find.byKey(const Key('星球_1')));
    await tester.pumpAndSettle();
    expect(find.text('删除这颗星球？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await db.select(db.novels).get(), hasLength(1));

    await tester.longPress(find.byKey(const Key('星球_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('星球删除确认按钮')));
    await tester.pumpAndSettle();

    expect(await db.select(db.novels).get(), isEmpty);
  });

  testWidgets('单击书名 → 重命名对话框 → 保存落库', (tester) async {
    // 真库造一本书（rename 走真库）
    await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            title: '旧书名',
            planet: 'earth',
            sortOrder: 0,
            createdAt: DateTime.now(),
          ),
        );
    await pumpApp(tester, novels: [fakeNovel(1, '旧书名')]);

    await tester.tap(find.byKey(const Key('书名_1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('书名重命名输入框')), '群星的新回声');
    await tester.tap(find.byKey(const Key('书名重命名确认按钮')));
    await tester.pumpAndSettle();

    final saved = await db.select(db.novels).get();
    expect(saved.single.title, '群星的新回声');
  });

  testWidgets('取消创建或空书名不落库', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('创建新星球标题')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('新星球确认按钮'))); // 空书名直接确认
    await tester.pumpAndSettle();

    final saved = await db.select(db.novels).get();
    expect(saved, isEmpty);
  });
}
