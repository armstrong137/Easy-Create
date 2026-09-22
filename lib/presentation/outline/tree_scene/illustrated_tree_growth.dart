const _illustratedTreeStageThresholds = <int>[1, 2, 4, 7, 10];

int illustratedTreeStageForNodeCount(int nodeCount) {
  final bounded = nodeCount < 0 ? 0 : nodeCount;
  var stage = 0;
  for (final threshold in _illustratedTreeStageThresholds) {
    if (bounded < threshold) break;
    stage += 1;
  }
  return stage;
}

double illustratedTreeLayoutAgeForNodeCount(int nodeCount) =>
    illustratedTreeStageForNodeCount(nodeCount) / 5;

String illustratedTreeAssetForStage(int stage) {
  final bounded = stage.clamp(0, 5);
  if (bounded == 1) return 'assets/tree_scene/illustrated/age_1_integrated.png';
  return 'assets/tree_scene/illustrated/age_$bounded.png';
}

String illustratedTreeAssetForNodeCount(int nodeCount) =>
    illustratedTreeAssetForStage(illustratedTreeStageForNodeCount(nodeCount));
