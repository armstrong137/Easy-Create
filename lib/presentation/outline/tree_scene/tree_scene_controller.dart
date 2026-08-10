import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'tree_scene_protocol.dart';
import 'tree_scene_snapshot.dart';

typedef TreeSceneSender = FutureOr<void> Function(Map<String, Object?> command);

class TreeLabelProjection {
  const TreeLabelProjection({
    required this.kind,
    required this.id,
    required this.rect,
  });

  final String kind;
  final int id;
  final Rect rect;
}

class TreeSceneHit {
  const TreeSceneHit({required this.kind, required this.id});

  final String kind;
  final int id;
}

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
  List<TreeLabelProjection> _visibleLabels = const [];
  TreeSceneHit? _dragHit;

  bool get isReady => _ready;
  Stream<TreeSceneEvent> get events => _events.stream;
  List<TreeLabelProjection> get visibleLabels => _visibleLabels;
  TreeSceneHit? get dragHit => _dragHit;

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

  void focusSection(int chapterId, int sectionId, {bool animate = true}) {
    _enqueue(
      _action('tree.focusSection', {
        'chapterId': chapterId,
        'id': sectionId,
        'animate': animate,
      }),
    );
  }

  void pan(double delta) {
    _enqueue(_action('scene.pan', {'delta': delta}));
  }

  void setDragPoint(double x, double y) {
    _enqueue(
      _action('tree.setDragPoint', {
        'x': x.clamp(0, 1) * 2 - 1,
        'y': 1 - y.clamp(0, 1) * 2,
      }),
    );
  }

  void endDrag() {
    _dragHit = null;
    _enqueue(_action('tree.endDrag'));
    notifyListeners();
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
    if (event.type == 'tree.visibleLabels') {
      final labels = event.payload['labels'];
      if (labels is List) {
        _visibleLabels = labels
            .whereType<Map>()
            .map((item) {
              final map = Map<String, Object?>.from(item);
              return TreeLabelProjection(
                kind: map['kind']! as String,
                id: map['id']! as int,
                rect: Rect.fromLTWH(
                  (map['x']! as num).toDouble(),
                  (map['y']! as num).toDouble(),
                  (map['width']! as num).toDouble(),
                  (map['height']! as num).toDouble(),
                ),
              );
            })
            .toList(growable: false);
        notifyListeners();
      }
    } else if (event.type == 'tree.hit') {
      final kind = event.payload['kind'];
      final id = event.payload['id'];
      _dragHit = kind is String && id is int
          ? TreeSceneHit(kind: kind, id: id)
          : null;
      notifyListeners();
    }
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

  TreeSceneCommand _action(
    String type, [
    Map<String, Object?> payload = const {},
  ]) => TreeSceneCommand.action(
    sessionId: sessionId,
    sequence: _sequence++,
    type: type,
    payload: payload,
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
