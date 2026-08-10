import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tree_scene_protocol.dart';
import 'tree_scene_snapshot.dart';

typedef TreeSceneSender = FutureOr<void> Function(Map<String, Object?> command);

class TreeSceneController extends ChangeNotifier {
  TreeSceneController({String? sessionId})
    : sessionId = sessionId ?? _nextSessionId();

  static int _sessionSequence = 0;

  static String _nextSessionId() {
    _sessionSequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_sessionSequence';
  }

  final String sessionId;
  final List<TreeSceneCommand> _pending = [];
  final StreamController<TreeSceneEvent> _events =
      StreamController<TreeSceneEvent>.broadcast();
  TreeSceneSender? _sender;
  TreeSceneSnapshot? _latestSnapshot;
  int _sequence = 1;
  bool _ready = false;
  bool _paused = false;

  bool get isReady => _ready;
  Stream<TreeSceneEvent> get events => _events.stream;

  void attachSender(TreeSceneSender sender) {
    _sender = sender;
  }

  void detachSender() {
    _sender = null;
    _ready = false;
  }

  Future<void> initializeTransport() async {
    final sender = _sender;
    if (sender == null) return;
    final command = TreeSceneCommand.scene(
      sessionId: sessionId,
      sequence: 0,
      action: 'init',
    );
    await sender(command.toJson());
  }

  void syncSnapshot(TreeSceneSnapshot snapshot) {
    _latestSnapshot = snapshot;
    _enqueue(
      TreeSceneCommand.sync(
        sessionId: sessionId,
        sequence: _sequence++,
        snapshot: snapshot,
      ),
    );
  }

  void playMutation(TreeMutation mutation, TreeSceneSnapshot snapshot) {
    _latestSnapshot = snapshot;
    _enqueue(
      TreeSceneCommand.playMutation(
        sessionId: sessionId,
        sequence: _sequence++,
        mutation: mutation,
        snapshot: snapshot,
      ),
    );
  }

  void focusChapter(int chapterId, {bool animate = true}) {
    _enqueue(
      TreeSceneCommand.focusChapter(
        sessionId: sessionId,
        sequence: _sequence++,
        chapterId: chapterId,
        animate: animate,
      ),
    );
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    _enqueue(_sceneCommand('pause'));
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _enqueue(_sceneCommand('resume'));
  }

  void disposeAssets() {
    _enqueue(_sceneCommand('disposeAssets'));
  }

  Future<void> handleEvent(TreeSceneEvent event) async {
    if (event.sessionId != sessionId) return;
    _events.add(event);
    switch (event.type) {
      case 'scene.ready':
        await _markReady();
        return;
      case 'scene.contextLost':
        _ready = false;
        _pending.clear();
        final snapshot = _latestSnapshot;
        if (snapshot != null) {
          _pending.add(
            TreeSceneCommand.sync(
              sessionId: sessionId,
              sequence: _sequence++,
              snapshot: snapshot,
            ),
          );
        }
        notifyListeners();
        return;
      default:
        return;
    }
  }

  @visibleForTesting
  Future<void> markReadyForTest() => _markReady();

  TreeSceneCommand _sceneCommand(String action) => TreeSceneCommand.scene(
    sessionId: sessionId,
    sequence: _sequence++,
    action: action,
  );

  void _enqueue(TreeSceneCommand command) {
    if (!_ready || _sender == null) {
      _pending.add(command);
      return;
    }
    unawaited(_send(command));
  }

  Future<void> _markReady() async {
    _ready = true;
    final queued = [..._pending]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    _pending.clear();
    for (final command in queued) {
      await _send(command);
    }
    notifyListeners();
  }

  Future<void> _send(TreeSceneCommand command) async {
    final sender = _sender;
    if (sender == null) {
      _pending.add(command);
      return;
    }
    await sender(command.toJson());
  }

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
}
