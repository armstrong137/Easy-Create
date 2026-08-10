import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_protocol.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_snapshot.dart';

void main() {
  const emptySnapshot = TreeSceneSnapshot(
    novelId: 1,
    chapters: [],
    structuralAge: 0,
    focusedChapterId: null,
  );

  test('场景命令包含版本、会话和单调序号', () {
    final command = TreeSceneCommand.sync(
      sessionId: 's1',
      sequence: 3,
      snapshot: emptySnapshot,
    );

    expect(command.toJson(), containsPair('protocolVersion', 1));
    expect(command.toJson(), containsPair('sceneSessionId', 's1'));
    expect(command.toJson(), containsPair('sequence', 3));
    expect(command.toJson(), containsPair('type', 'tree.syncSnapshot'));
  });

  test('场景事件只解析 JSON 安全字段', () {
    final event = TreeSceneEvent.fromJson(const {
      'protocolVersion': 1,
      'sceneSessionId': 's1',
      'sequence': 4,
      'type': 'tree.mutationCompleted',
      'payload': {'id': 9},
    });

    expect(event.sessionId, 's1');
    expect(event.sequence, 4);
    expect(event.type, 'tree.mutationCompleted');
    expect(event.payload, {'id': 9});
  });

  test('协议拒绝错误版本和负序号', () {
    expect(
      () => TreeSceneEvent.fromJson(const {
        'protocolVersion': 2,
        'sceneSessionId': 's1',
        'sequence': 0,
        'type': 'scene.ready',
      }),
      throwsFormatException,
    );
    expect(
      () => TreeSceneEvent.fromJson(const {
        'protocolVersion': 1,
        'sceneSessionId': 's1',
        'sequence': -1,
        'type': 'scene.ready',
      }),
      throwsFormatException,
    );
  });
}
