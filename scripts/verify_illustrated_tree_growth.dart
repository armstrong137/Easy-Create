import 'dart:io';

import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_growth.dart';

void _expectEqual(Object actual, Object expected, String label) {
  if (actual != expected) {
    throw StateError('$label：期望 $expected，实际 $actual');
  }
}

void main() {
  const stages = {0: 0, 1: 1, 2: 2, 3: 2, 4: 3, 6: 3, 7: 4, 9: 4, 10: 5, 40: 5};
  for (final entry in stages.entries) {
    _expectEqual(
      illustratedTreeStageForNodeCount(entry.key),
      entry.value,
      '${entry.key} 个结构节点的树龄档',
    );
  }

  var previous = -1;
  for (var nodes = 0; nodes <= 40; nodes += 1) {
    final stage = illustratedTreeStageForNodeCount(nodes);
    if (stage < previous) {
      throw StateError('树龄档不得倒退：$nodes 个节点从 $previous 退到 $stage');
    }
    previous = stage;
  }

  _expectEqual(
    illustratedTreeAssetForNodeCount(10),
    'assets/tree_scene/illustrated/age_5.png',
    '成熟古树素材',
  );
  stdout.writeln('二维魔树树龄映射验收通过');
}
