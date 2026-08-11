import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_controller.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_protocol.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_snapshot.dart';

void main() {
  const snapshot = TreeSceneSnapshot(
    novelId: 1,
    chapters: [],
    structuralAge: 0,
    focusedChapterId: null,
  );
  late List<Map<String, Object?>> sent;
  late TreeSceneController controller;

  setUp(() {
    sent = [];
    controller = TreeSceneController(sessionId: 'session-1')
      ..attachSender((command) async => sent.add(command));
  });

  test('ready 前命令排队且 ready 后按序发送', () async {
    controller.syncSnapshot(snapshot);
    controller.focusChapter(3);
    expect(sent, isEmpty);

    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 0,
        type: 'scene.ready',
        payload: {},
      ),
    );

    expect(sent.map((item) => item['sequence']), [1, 2]);
  });

  test('旧会话事件会被丢弃', () async {
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'old-session',
        sequence: 0,
        type: 'scene.ready',
        payload: {},
      ),
    );
    controller.syncSnapshot(snapshot);
    expect(sent, isEmpty);
  });

  test('上下文丢失后等待新 ready 并重发最新完整快照', () async {
    await controller.markReadyForTest();
    controller.syncSnapshot(snapshot);
    sent.clear();

    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 1,
        type: 'scene.contextLost',
        payload: {},
      ),
    );
    expect(sent, isEmpty);
    await controller.markReadyForTest();

    expect(sent, hasLength(1));
    expect(sent.single['type'], 'tree.syncSnapshot');
  });

  test('暂停和恢复命令幂等', () async {
    await controller.markReadyForTest();
    controller.pause();
    controller.pause();
    controller.resume();
    controller.resume();

    expect(sent.map((item) => item['type']), ['scene.pause', 'scene.resume']);
  });

  test('连续两次恢复失败后进入静态替身', () async {
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 1,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    expect(controller.useStaticFallback, isFalse);

    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 2,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    expect(controller.useStaticFallback, isTrue);
  });

  test('恢复成功会清零失败次数且只补发最新快照', () async {
    controller.syncSnapshot(snapshot);
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 1,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    sent.clear();

    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 2,
        type: 'scene.ready',
        payload: {},
      ),
    );

    expect(controller.useStaticFallback, isFalse);
    expect(
      sent.where((item) => item['type'] == 'tree.syncSnapshot'),
      hasLength(1),
    );
  });

  test('静态模式不积压命令且重启时只补最新快照', () async {
    controller.setTransportEnabled(false);
    controller.syncSnapshot(snapshot);
    for (var index = 0; index < 50; index += 1) {
      controller.focusChapter(index);
      controller.focusSection(index, index * 10);
    }
    expect(sent, isEmpty);

    controller.setTransportEnabled(true);
    await controller.markReadyForTest();

    expect(sent, hasLength(1));
    expect(sent.single['type'], 'tree.syncSnapshot');
  });

  test('进入静态回退后忽略迟到的上下文与ready事件', () async {
    await controller.markReadyForTest();
    controller.syncSnapshot(snapshot);
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 21,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 22,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    expect(controller.useStaticFallback, isTrue);
    expect(controller.isReady, isFalse);
    sent.clear();

    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 23,
        type: 'scene.contextLost',
        payload: {},
      ),
    );
    await controller.handleEvent(
      const TreeSceneEvent(
        sessionId: 'session-1',
        sequence: 24,
        type: 'scene.ready',
        payload: {},
      ),
    );

    expect(controller.useStaticFallback, isTrue);
    expect(controller.isReady, isFalse);
    expect(sent, isEmpty);
  });
}
