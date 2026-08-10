import 'tree_scene_snapshot.dart';

const treeSceneProtocolVersion = 1;

class TreeSceneCommand {
  const TreeSceneCommand._({
    required this.sessionId,
    required this.sequence,
    required this.type,
    required this.payload,
  });

  factory TreeSceneCommand.sync({
    required String sessionId,
    required int sequence,
    required TreeSceneSnapshot snapshot,
  }) {
    return TreeSceneCommand._(
      sessionId: sessionId,
      sequence: sequence,
      type: 'tree.syncSnapshot',
      payload: snapshot.toJson(),
    );
  }

  factory TreeSceneCommand.playMutation({
    required String sessionId,
    required int sequence,
    required TreeMutation mutation,
    required TreeSceneSnapshot snapshot,
  }) {
    return TreeSceneCommand._(
      sessionId: sessionId,
      sequence: sequence,
      type: 'tree.playMutation',
      payload: {'mutation': mutation.toJson(), 'snapshot': snapshot.toJson()},
    );
  }

  factory TreeSceneCommand.focusChapter({
    required String sessionId,
    required int sequence,
    required int chapterId,
    bool animate = true,
  }) {
    return TreeSceneCommand._(
      sessionId: sessionId,
      sequence: sequence,
      type: 'tree.focusChapter',
      payload: {'id': chapterId, 'animate': animate},
    );
  }

  factory TreeSceneCommand.scene({
    required String sessionId,
    required int sequence,
    required String action,
    Map<String, Object?> payload = const {},
  }) {
    return TreeSceneCommand._(
      sessionId: sessionId,
      sequence: sequence,
      type: 'scene.$action',
      payload: payload,
    );
  }

  factory TreeSceneCommand.action({
    required String sessionId,
    required int sequence,
    required String type,
    Map<String, Object?> payload = const {},
  }) {
    return TreeSceneCommand._(
      sessionId: sessionId,
      sequence: sequence,
      type: type,
      payload: payload,
    );
  }

  final String sessionId;
  final int sequence;
  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'protocolVersion': treeSceneProtocolVersion,
    'sceneSessionId': sessionId,
    'sequence': sequence,
    'type': type,
    'payload': payload,
  };
}

class TreeSceneEvent {
  const TreeSceneEvent({
    required this.sessionId,
    required this.sequence,
    required this.type,
    required this.payload,
  });

  factory TreeSceneEvent.fromJson(Map<String, Object?> json) {
    if (json['protocolVersion'] != treeSceneProtocolVersion) {
      throw const FormatException('不支持的魔树场景协议版本');
    }
    final sessionId = json['sceneSessionId'];
    final sequence = json['sequence'];
    final type = json['type'];
    final payload = json['payload'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException('sceneSessionId 必须是非空字符串');
    }
    if (sequence is! int || sequence < 0) {
      throw const FormatException('sequence 必须是非负整数');
    }
    if (type is! String || type.isEmpty) {
      throw const FormatException('type 必须是非空字符串');
    }
    if (payload != null && payload is! Map) {
      throw const FormatException('payload 必须是对象或 null');
    }
    return TreeSceneEvent(
      sessionId: sessionId,
      sequence: sequence,
      type: type,
      payload: payload == null
          ? const {}
          : Map<String, Object?>.from(payload as Map),
    );
  }

  final String sessionId;
  final int sequence;
  final String type;
  final Map<String, Object?> payload;
}
