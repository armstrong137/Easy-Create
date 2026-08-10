enum TreeGestureOwner { chapter, section }

enum TreeGestureDirection { none, previous, next }

class TreeSceneGestures {
  TreeGestureOwner? _owner;
  double _distanceY = 0;

  TreeGestureOwner? get owner => _owner;

  TreeGestureOwner begin({required double x, required double width}) {
    _distanceY = 0;
    _owner = x < width / 2
        ? TreeGestureOwner.chapter
        : TreeGestureOwner.section;
    return _owner!;
  }

  void update({
    required double deltaY,
    required double x,
    required double width,
  }) {
    if (_owner == null) return;
    _distanceY += deltaY;
  }

  TreeGestureDirection end() {
    final distance = _distanceY;
    _owner = null;
    _distanceY = 0;
    if (distance.abs() < 20) return TreeGestureDirection.none;
    return distance > 0
        ? TreeGestureDirection.previous
        : TreeGestureDirection.next;
  }

  void cancel() {
    _owner = null;
    _distanceY = 0;
  }
}

class TreeDragBridge {
  TreeDragBridge({required this.now, required this.send});

  final DateTime Function() now;
  final void Function(double x, double y) send;
  DateTime? _lastSentAt;

  void update({required double x, required double y}) {
    final time = now();
    final last = _lastSentAt;
    if (last != null &&
        time.difference(last) < const Duration(milliseconds: 34)) {
      return;
    }
    _lastSentAt = time;
    send(x.clamp(0, 1), y.clamp(0, 1));
  }

  void reset() {
    _lastSentAt = null;
  }
}
