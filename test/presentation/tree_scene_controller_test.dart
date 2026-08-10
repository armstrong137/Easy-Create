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

    expect(sent.map((item) => item['sequence']), [0, 1]);
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
}
