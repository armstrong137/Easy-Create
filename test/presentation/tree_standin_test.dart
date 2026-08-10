import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_standin.dart';

void main() {
  test('树龄映射到六张静态替身且边界受限', () {
    expect(treeStandinIndex(-1), 0);
    expect(treeStandinIndex(0.19), 1);
    expect(treeStandinIndex(0.59), 3);
    expect(treeStandinIndex(1), 5);
    expect(treeStandinIndex(2), 5);
  });
}
