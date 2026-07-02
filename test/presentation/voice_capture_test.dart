import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/data/providers.dart';
import 'package:novel_app/main.dart';
import 'package:novel_app/presentation/shared/quick_capture/capture_button_prefs.dart';
import 'package:novel_app/presentation/shared/quick_capture/speech_service.dart';

/// 语音识别服务替身：手动喂识别结果，不依赖平台 channel
class FakeSpeechService extends SpeechService {
  FakeSpeechService({this.available = true});

  /// 模拟设备是否支持语音识别
  final bool available;

  void Function(String text, bool isFinal)? _onResult;
  bool stopCalled = false;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> listen(void Function(String text, bool isFinal) onResult) async {
    _onResult = onResult;
  }

  @override
  Future<void> stop() async => stopCalled = true;

  /// 测试中手动推送一条识别结果
  void emit(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);
}

void main() {
  late AppDatabase db;
  late FakeSpeechService speech;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpApp(WidgetTester tester, {bool available = true}) async {
    speech = FakeSpeechService(available: available);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          speechServiceProvider.overrideWithValue(speech),
        ],
        child: const NovelApp(),
      ),
    );
  }

  final voiceBtn = find.byKey(const Key('语音速记按钮'));

  testWidgets('识别文字实时显示，确认后入池、弹层关闭', (tester) async {
    await pumpApp(tester);

    await tester.tap(voiceBtn);
    await tester.pumpAndSettle();

    // partial 结果实时刷新
    speech.emit('月光落在');
    await tester.pump();
    expect(find.text('月光落在'), findsOneWidget);

    // 最终结果
    speech.emit('月光落在旧钢琴上', isFinal: true);
    await tester.pump();
    expect(find.text('月光落在旧钢琴上'), findsOneWidget);

    await tester.tap(find.byKey(const Key('语音保存按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('语音识别文字')), findsNothing,
        reason: '保存后弹层应关闭');
    final all = await db.select(db.inspirations).get();
    expect(all.single.content, '月光落在旧钢琴上');
    expect(all.single.sectionId, isNull, reason: '语音灵感直接入魔毯');
  });

  testWidgets('设备不支持时显示不可用提示', (tester) async {
    await pumpApp(tester, available: false);

    await tester.tap(voiceBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('语音不可用提示')), findsOneWidget);
  });

  testWidgets('未识别到内容时点保存不入库、弹层不关闭', (tester) async {
    await pumpApp(tester);

    await tester.tap(voiceBtn);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('语音保存按钮')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('语音识别文字')), findsOneWidget,
        reason: '空内容不应关闭弹层');
    final all = await db.select(db.inspirations).get();
    expect(all, isEmpty);
  });

  testWidgets('划掉弹层时停止聆听', (tester) async {
    await pumpApp(tester);

    await tester.tap(voiceBtn);
    await tester.pumpAndSettle();

    // 点弹层外区域关闭
    await tester.tapAt(const Offset(400, 50));
    await tester.pumpAndSettle();

    expect(speech.stopCalled, isTrue, reason: '取消时必须停止麦克风');
  });
}
