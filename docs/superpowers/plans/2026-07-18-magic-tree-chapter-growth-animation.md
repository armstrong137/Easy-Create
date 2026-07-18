# 大纲页魔树章节增长动画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复大纲页新增章节时“土壤跟着乱动、树体像图片被强行拉伸、阶段切换有鬼影”的问题，让新增章节表现为树本身自然生长、新枝从树干长出、镜头后置平滑跟随。

**Architecture:** 保留当前 Flutter + Riverpod + 本地图片素材路线，不引入新 3D 引擎。把魔树背景拆成“固定土壤层 + 可增长树干中段 + 树梢/叶片层 + 新枝/标签前景层”，并把新增章节流程拆成“数据落库 → 新枝生长 → 标签显现 → 必要时镜头跟随”的顺序动画。

**Tech Stack:** Flutter、Dart、Custom widget layout、现有 `assets/textures/tree_seg/` 分段素材、Flutter widget/unit tests。

## Global Constraints

- 对话、代码注释、文档必须使用中文。
- 修改代码后必须运行 `dart format`、相关测试、`flutter analyze`、全量测试。
- 每次 commit 前必须执行 `C:\Program Files\Git\bin\bash.exe scripts/update_code_map.sh` 更新 `docs/CODE_MAP.md`。
- 每完成一个可验证任务就提交一次，提交信息使用中文。
- 不改首页星球、灵感卷轴、小节页；本计划只处理大纲页魔树新增章节动画。
- 不允许用继续放大整张树图、延长整图高度、加大 `easeOutBack` 这类方式掩盖问题。

---

## 诊断结论

证据图：`docs/ui_review/video4_frames/contact_sheet.png`。

当前用户反馈对应到代码的根因如下：

1. `lib/presentation/outline/outline_page.dart:121` 在新增章节后立即 `_camera.animateTo(...)`，同时 `:127` 又启动 `_playGrow(...)`。结果是“镜头移动”和“枝条生长”同时发生，用户看到的不是树枝长出来，而是整棵树和土壤一起滑动。

2. `lib/presentation/outline/magic_tree_model.dart:60` 的 `treeGrowthFactor()` 让章节数直接改变整棵虚拟树高度；`:663` 用这个高度生成 `dispH`，`:669` 再用 `imageTop = -travel * offset / maxOffset` 推动整张树图。新增章节时 `n/maxOffset/dispH` 同时变化，土壤位置和树干比例都会跳。

3. `lib/presentation/outline/magic_tree_model.dart:53` 的 `stageForNodes()` 在节点数到 12 时从 stage 2 切 stage 3；`outline_page.dart:924` 的 `AnimatedSwitcher` keyed by `tree_segments_${pieces.spec.stage}` 会把整棵分段树交叉淡入淡出。视频中半透明灰树影就是这里产生的。

4. `_SegmentedMagicTreeImage` 当前虽然把素材分成 top/mid/bottom，但仍把它们包在同一个 `pieces.bounds` 里，底段 `bottomRect` 依赖 `layout.imageRect.bottom`。因此土壤仍是“树图的一部分”，没有被建模成固定地面。

5. `_tendril()` 用 `Transform.scale` 直接缩放整张卷须精灵。视觉上像图片从根部被拽大，不像枝条沿路径抽芽、伸展、显形。

正确方向：土壤是舞台地面，新增章节时不应该参与主动画；树干中段可以增长，但不能横向变粗；新枝应先从树干长出，镜头应在枝条长完后才平滑跟随。

---

## 文件结构

**Modify:**
- `lib/presentation/outline/magic_tree_model.dart`：增加稳定土壤/树干分层布局模型、视觉阶段冻结参数、章节增长动作计划。
- `lib/presentation/outline/outline_page.dart`：调整新增章节动画顺序；拆掉整树 `AnimatedSwitcher`；渲染固定土壤层；改进卷须生长动画。
- `test/presentation/magic_tree_model_test.dart`：新增模型级回归，覆盖土壤固定、阶段冻结、动作顺序。
- `test/presentation/outline_page_test.dart`：新增页面级/source guard 回归，覆盖不再整树 crossfade、加载固定土壤层。
- `DevelopmentPlan.md`：记录本轮修复和验证结果。
- `docs/CODE_MAP.md`：提交前自动更新。

**Do not modify:**
- `lib/presentation/home/**`
- `lib/presentation/section/**`
- `lib/presentation/outline/magic_carpet.dart`
- 数据库表结构

---

## 成功标准

- 新增章节时，土壤层底边固定在屏幕底部，不跟着新章动画上下抖动。
- 新增章节时，先看到新章卷须从树干根点生长，标签后半段淡入；镜头平移在枝条基本长完后才发生。
- 章节从 11 增到 12、12 增到 13 时，不出现整棵树半透明叠影。
- 章节到 18 个以上时，树干宽度不继续变粗，树不是“被强拉伸的照片柱子”。
- 快速连续新增章节时，动画不中断、不反复重置土壤、不出现大幅跳帧。

---

### Task 1: 写失败测试固定根因

**Files:**
- Modify: `test/presentation/magic_tree_model_test.dart`
- Modify: `test/presentation/outline_page_test.dart`

**Interfaces:**
- Consumes: 当前 `layoutMagicTree()`、`layoutMagicTreeImagePieces()`、页面源码。
- Produces: 后续任务必须满足的回归测试。

- [ ] **Step 1: 在 `magic_tree_model_test.dart` 增加阶段冻结测试**

追加测试：

```dart
test('窗口模式：新增章节跨阶段时可冻结视觉阶段，避免整树鬼影切换', () {
  final before = [for (var i = 1; i <= 11; i++) chapterWith(i, 0)];
  final after = [for (var i = 1; i <= 12; i++) chapterWith(i, 0)];

  final oldLayout = layoutMagicTree(size: size, outline: before);
  expect(oldLayout.stage, 2);

  final frozenLayout = layoutMagicTree(
    size: size,
    outline: after,
    visualStageOverride: oldLayout.stage,
  );
  expect(frozenLayout.stage, 2, reason: '新增章节生长期间必须沿用旧视觉阶段');

  final settledLayout = layoutMagicTree(size: size, outline: after);
  expect(settledLayout.stage, 3, reason: '动画结束后才允许切到新视觉阶段');
});
```

Expected now: FAIL，`visualStageOverride` 参数不存在。

- [ ] **Step 2: 在 `magic_tree_model_test.dart` 增加土壤固定测试**

追加测试：

```dart
test('窗口模式：土壤层固定在视口底部，不随章节数增长上下跳动', () {
  Rect soilFor(int count) {
    final outline = [for (var i = 1; i <= count; i++) chapterWith(i, 0)];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: (count - 2).toDouble(),
    );
    final pieces = layoutMagicTreeImagePieces(layout);
    expect(pieces, isA<SegmentedTreeImagePieces>());
    return (pieces as SegmentedTreeImagePieces).soilRect;
  }

  final soil3 = soilFor(3);
  for (final count in [4, 8, 11]) {
    final soil = soilFor(count);
    expect(soil.bottom, closeTo(size.height, 0.5), reason: '$count 章土壤底边固定');
    expect(soil.left, closeTo(soil3.left, 0.5), reason: '$count 章土壤横向不漂移');
    expect(soil.width, closeTo(soil3.width, 0.5), reason: '$count 章土壤宽度不变');
  }
});
```

Expected now: FAIL，`soilRect` 字段不存在。

- [ ] **Step 3: 在 `magic_tree_model_test.dart` 增加新增章节动作顺序测试**

追加测试：

```dart
test('新增章节动作计划：先长枝，再镜头跟随', () {
  final plan = chapterGrowthMotionPlan(
    oldCount: 4,
    newCount: 5,
    currentOffset: 2,
  );

  expect(plan.targetOffset, 3);
  expect(plan.steps, [
    ChapterGrowthStep.growBranch,
    ChapterGrowthStep.panCamera,
  ]);
  expect(plan.panDelay, const Duration(milliseconds: 620));
});
```

Expected now: FAIL，`chapterGrowthMotionPlan` 与相关类型不存在。

- [ ] **Step 4: 在 `outline_page_test.dart` 增加整树 crossfade source guard**

追加测试：

```dart
test('分段魔树不得用整树 AnimatedSwitcher 交叉淡入淡出', () {
  final src = File('lib/presentation/outline/outline_page.dart')
      .readAsStringSync();
  expect(
    src,
    isNot(contains("ValueKey('tree_segments_")),
    reason: '阶段切换不能把整棵树交叉淡入淡出，否则会出现半透明鬼影',
  );
});
```

同时给文件顶部补：

```dart
import 'dart:io';
```

Expected now: FAIL，当前源码包含 `ValueKey('tree_segments_${pieces.spec.stage}')`。

- [ ] **Step 5: 运行失败测试**

Run:

```powershell
flutter test test\presentation\magic_tree_model_test.dart --timeout 2m
flutter test test\presentation\outline_page_test.dart --timeout 2m
```

Expected: 新增测试失败，失败原因与上述一致。

- [ ] **Step 6: Commit**

```powershell
git add test\presentation\magic_tree_model_test.dart test\presentation\outline_page_test.dart
git commit -m "添加魔树章节增长动画回归测试"
```

---

### Task 2: 在模型层拆出稳定土壤和动作计划

**Files:**
- Modify: `lib/presentation/outline/magic_tree_model.dart`
- Test: `test/presentation/magic_tree_model_test.dart`

**Interfaces:**
- Produces:
  - `enum ChapterGrowthStep { growBranch, panCamera }`
  - `class ChapterGrowthMotionPlan`
  - `ChapterGrowthMotionPlan chapterGrowthMotionPlan(...)`
  - `layoutMagicTree(..., int? visualStageOverride)`
  - `SegmentedTreeImagePieces.soilRect`

- [ ] **Step 1: 增加章节增长动作计划类型**

在 `magic_tree_model.dart` 的 `stageForNodes` 下方加入：

```dart
/// 新增章节的视觉流程：先让新枝生长，再移动镜头。
enum ChapterGrowthStep { growBranch, panCamera }

class ChapterGrowthMotionPlan {
  const ChapterGrowthMotionPlan({
    required this.targetOffset,
    required this.steps,
    required this.panDelay,
  });

  final double targetOffset;
  final List<ChapterGrowthStep> steps;
  final Duration panDelay;
}

ChapterGrowthMotionPlan chapterGrowthMotionPlan({
  required int oldCount,
  required int newCount,
  required double currentOffset,
}) {
  final target = newCount > 2 ? (newCount - 2).toDouble() : 0.0;
  final shouldPan = (target - currentOffset).abs() > 0.01;
  return ChapterGrowthMotionPlan(
    targetOffset: target,
    steps: shouldPan
        ? const [ChapterGrowthStep.growBranch, ChapterGrowthStep.panCamera]
        : const [ChapterGrowthStep.growBranch],
    panDelay: const Duration(milliseconds: 620),
  );
}
```

- [ ] **Step 2: 给 `layoutMagicTree` 增加视觉阶段冻结参数**

把函数签名改为：

```dart
MagicTreeLayout layoutMagicTree({
  required Size size,
  required List<OutlineChapter> outline,
  double chapterOffset = 0,
  Map<int, double> sectionScrolls = const {},
  Map<int, int> sectionNoteCounts = const {},
  int? visualStageOverride,
}) {
```

把 stage 计算改为：

```dart
final computedStage = stageForNodes(totalNodes);
final stage = visualStageOverride ?? computedStage;
```

其余调用 `_layoutSingleChapter/_layoutWholeTree/_layoutWindow` 继续传 `stage`。

- [ ] **Step 3: 给 `SegmentedTreeImagePieces` 增加 `soilRect`**

把构造函数改为：

```dart
const SegmentedTreeImagePieces({
  required super.bounds,
  required this.spec,
  required this.topRect,
  required this.middleRect,
  required this.bottomRect,
  required this.soilRect,
  required this.tileHeight,
});
```

增加字段：

```dart
/// 固定在视口底部的土壤层；新增章节动画期间不得跟随树干/镜头跳动。
final Rect soilRect;
```

- [ ] **Step 4: 在 `layoutMagicTreeImagePieces` 中固定土壤层**

保留 `bottomRect` 作为兼容字段，但新增 `soilRect`：

```dart
final soilRect = Rect.fromLTWH(
  layout.imageRect.left,
  layout.viewportHeight - bottomH,
  layout.imageRect.width,
  bottomH,
);
```

为此需要给 `MagicTreeLayout` 增加 `viewportHeight`：

```dart
required this.viewportHeight,
...
final double viewportHeight;
```

所有 `MagicTreeLayout(...)` return 处补：

```dart
viewportHeight: size.height,
```

然后返回：

```dart
return SegmentedTreeImagePieces(
  bounds: layout.imageRect,
  spec: spec,
  topRect: topRect,
  middleRect: middleRect,
  bottomRect: bottomRect,
  soilRect: soilRect,
  tileHeight: tileH,
);
```

注意：这里先只暴露稳定土壤几何，不在模型层强行改所有树干算法，避免一次改太大。

- [ ] **Step 5: 跑模型测试**

Run:

```powershell
dart format lib\presentation\outline\magic_tree_model.dart test\presentation\magic_tree_model_test.dart
flutter test test\presentation\magic_tree_model_test.dart --timeout 2m
```

Expected: 模型测试通过；页面 source guard 仍失败。

- [ ] **Step 6: Commit**

```powershell
git add lib\presentation\outline\magic_tree_model.dart test\presentation\magic_tree_model_test.dart
git commit -m "拆出魔树土壤层与章节增长动作计划"
```

---

### Task 3: 调整新增章节动画顺序，先长枝后镜头

**Files:**
- Modify: `lib/presentation/outline/outline_page.dart`
- Test: `test/presentation/outline_page_test.dart`

**Interfaces:**
- Consumes: `chapterGrowthMotionPlan(...)`、`visualStageOverride`。
- Produces: 新增章节期间冻结视觉阶段，不再同时移动镜头和生长枝条。

- [ ] **Step 1: 增加视觉阶段冻结状态**

在 `_OutlinePageState` 字段区加入：

```dart
/// 新增章节生长期间冻结旧视觉阶段，避免 11→12 章时整树鬼影切换。
int? _visualStageOverride;
```

- [ ] **Step 2: 修改 `_addChapter` 顺序**

把当前 `_addChapter` 替换为：

```dart
Future<void> _addChapter(List<OutlineChapter> outline) async {
  HapticFeedback.lightImpact();
  final oldCount = outline.length;
  final frozenStage = _layout?.stage;

  final chapter = await ref
      .read(novelRepositoryProvider)
      .createChapter(novelId: widget.novelId);

  final newCount = oldCount + 1;
  final motion = chapterGrowthMotionPlan(
    oldCount: oldCount,
    newCount: newCount,
    currentOffset: _camera.value,
  );

  setState(() => _visualStageOverride = frozenStage);
  await _playGrow(isChapter: true, id: chapter.id);
  if (!mounted) return;

  if (motion.steps.contains(ChapterGrowthStep.panCamera)) {
    await _camera.animateTo(
      motion.targetOffset,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
  }

  if (mounted) setState(() => _visualStageOverride = null);
}
```

- [ ] **Step 3: 把冻结阶段传给布局**

在 build 中调用 `layoutMagicTree(...)` 的地方加入：

```dart
visualStageOverride: _visualStageOverride,
```

- [ ] **Step 4: 调整 `_growthFor` 曲线**

把 `Curves.easeOutBack` 改为更自然、不反弹过度的曲线：

```dart
return Curves.easeOutCubic.transform(_grow.value);
```

原因：新增章节不应该像 UI 弹簧按钮一样过冲，枝条更适合柔和伸展。

- [ ] **Step 5: 跑页面测试**

Run:

```powershell
dart format lib\presentation\outline\outline_page.dart
flutter test test\presentation\outline_page_test.dart --timeout 2m
```

Expected: 页面已有交互测试不退化；source guard 仍可能失败，留到 Task 4。

- [ ] **Step 6: Commit**

```powershell
git add lib\presentation\outline\outline_page.dart test\presentation\outline_page_test.dart
git commit -m "调整魔树新增章节动画顺序"
```

---

### Task 4: 拆掉整树 AnimatedSwitcher，渲染固定土壤层

**Files:**
- Modify: `lib/presentation/outline/outline_page.dart`
- Test: `test/presentation/outline_page_test.dart`

**Interfaces:**
- Consumes: `SegmentedTreeImagePieces.soilRect`。
- Produces: 土壤独立渲染，不参与树干/阶段 crossfade。

- [ ] **Step 1: 移除 `_SegmentedMagicTreeImage` 内层 `AnimatedSwitcher`**

把 `_SegmentedMagicTreeImage.build` 中：

```dart
child: AnimatedSwitcher(
  duration: const Duration(milliseconds: 600),
  child: Stack(
    key: ValueKey('tree_segments_${pieces.spec.stage}'),
```

替换为普通 `Stack`：

```dart
child: Stack(
  clipBehavior: Clip.hardEdge,
  children: [
```

并删除对应的 `key` 和多余闭合括号。

- [ ] **Step 2: 土壤使用固定视口 rect**

在 `_SegmentedMagicTreeImage.build` 中，新增局部函数：

```dart
Rect localToBounds(Rect rect) => rect.shift(-origin);
```

顶段/中段仍使用 `local(pieces.topRect)`、`local(pieces.middleRect)`。

泥土段不要再使用 `pieces.bottomRect`，改用 `pieces.soilRect` 对齐视口：

```dart
Positioned.fromRect(
  rect: localToBounds(pieces.soilRect),
  child: Image.asset(
    pieces.spec.bottomAsset,
    key: const Key('魔树固定土壤层'),
    fit: BoxFit.fill,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
  ),
),
```

如果 `pieces.soilRect` 超出 `pieces.bounds` 局部坐标，说明 `bounds` 仍用整树世界坐标包不住固定土壤。此时把最外层 `Positioned.fromRect(rect: pieces.bounds)` 改为 `Positioned.fill(...)`，内部 top/mid/soil 全部使用视口坐标即可。推荐直接改成：

```dart
return Positioned.fill(
  child: ClipRect(
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // top/mid 仍按 pieces 中的视口 rect 放置
        ...
      ],
    ),
  ),
);
```

这样土壤固定不再被 `pieces.bounds.topLeft` 影响。

- [ ] **Step 3: 给页面测试补固定土壤 key**

修改已有测试 `窗口模式：魔树使用顶段/中段/泥土分段素材，避免整图纵向拉伸`：

```dart
expect(find.byKey(const Key('魔树固定土壤层')), findsOneWidget);
```

旧的 `Key('魔树泥土段')` 可以保留一版兼容，也可以改成新 key；推荐只保留新 key，避免概念继续叫“段”。

- [ ] **Step 4: 跑页面 source guard**

Run:

```powershell
flutter test test\presentation\outline_page_test.dart --timeout 2m
```

Expected: `分段魔树不得用整树 AnimatedSwitcher...` 通过。

- [ ] **Step 5: Commit**

```powershell
git add lib\presentation\outline\outline_page.dart test\presentation\outline_page_test.dart
git commit -m "固定魔树土壤层并移除整树淡切"
```

---

### Task 5: 改进卷须生长动画，避免图片被强行缩放

**Files:**
- Modify: `lib/presentation/outline/outline_page.dart`
- Test: `test/presentation/outline_page_test.dart`

**Interfaces:**
- Consumes: `_growthFor(...)`。
- Produces: 新枝沿根点方向显露，而不是整张精灵等比弹大。

- [ ] **Step 1: 替换 `_tendril` 的 `Transform.scale`**

把 `_tendril` 中的 `Transform.scale(...)` 替换为：

```dart
final growth = _growthFor(isChapter: b.isChapter, id: b.id).clamp(0.0, 1.0);
final align = b.isChapter ? Alignment.centerRight : Alignment.centerLeft;

return Positioned.fromRect(
  rect: b.spriteRect.shift(-shift),
  child: Opacity(
    opacity: growth <= 0.02 ? 0 : (0.25 + growth * 0.75).clamp(0.0, 1.0),
    child: ClipRect(
      child: Align(
        alignment: align,
        widthFactor: growth,
        child: SizedBox(
          width: b.spriteRect.width,
          height: b.spriteRect.height,
          child: Image.asset(
            b.isChapter
                ? 'assets/textures/tendril_chapter.png'
                : 'assets/textures/tendril_section.png',
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    ),
  ),
);
```

视觉含义：
- 章枝从右侧根点向左显露。
- 节枝从左侧根点向右显露。
- 不再整体放大整张图片。

- [ ] **Step 2: 增加源码回归，防止回到 `Transform.scale`**

在 `outline_page_test.dart` 增加：

```dart
test('卷须生长使用裁剪显露，不再整体缩放精灵', () {
  final src = File('lib/presentation/outline/outline_page.dart')
      .readAsStringSync();
  expect(
    src,
    isNot(contains('Transform.scale')),
    reason: '卷须整体缩放会产生强拉伸图片感，应使用 ClipRect + Align 显露',
  );
  expect(src, contains('widthFactor: growth'));
});
```

- [ ] **Step 3: 跑页面测试**

Run:

```powershell
dart format lib\presentation\outline\outline_page.dart test\presentation\outline_page_test.dart
flutter test test\presentation\outline_page_test.dart --timeout 2m
```

Expected: 页面测试通过。

- [ ] **Step 4: Commit**

```powershell
git add lib\presentation\outline\outline_page.dart test\presentation\outline_page_test.dart
git commit -m "优化魔树卷须自然生长动画"
```

---

### Task 6: 手动视频验收与性能回归

**Files:**
- Modify: `DevelopmentPlan.md`
- Modify: `docs/CODE_MAP.md`

**Interfaces:**
- Consumes: 前五个任务代码。
- Produces: 可验收记录和最终提交。

- [ ] **Step 1: 自动验证**

Run:

```powershell
dart format lib\presentation\outline\magic_tree_model.dart lib\presentation\outline\outline_page.dart test\presentation\magic_tree_model_test.dart test\presentation\outline_page_test.dart
flutter test test\presentation\magic_tree_model_test.dart --timeout 2m
flutter test test\presentation\outline_page_test.dart --timeout 2m
flutter analyze --no-pub
flutter test --timeout 2m
flutter build web --release
```

Expected:
- `magic_tree_model_test` 全绿。
- `outline_page_test` 全绿。
- analyze 无问题。
- 全量测试全绿。
- web release 构建成功。

- [ ] **Step 2: 真机/浏览器视觉验收**

在浏览器或手机上执行：

1. 进入一本空小说的大纲页。
2. 连续双击左侧空白新增章节，至少加到 18 章。
3. 重点观察第 3、4、11、12、13、18 章新增时的动画。

验收必须满足：
- 土壤底边不抖，不出现上下漂移。
- 新枝先长，镜头后动。
- 11→12 章不出现半透明整树叠影。
- 树干不横向变粗，不像一张图被拉伸。
- 快速连续新增时，动画可以排队或自然覆盖，但不能反复闪烁重置。

- [ ] **Step 3: 更新 `DevelopmentPlan.md`**

在 P3 下新增一条：

```markdown
    - ✅ P3-R3 魔树新增章节动画重构（2026-07-18）：修复新增章节时土壤跟随镜头抖动、树体强拉伸、阶段切换整树鬼影问题。将新增章节流程改为“新枝生长 → 标签显现 → 镜头跟随”，冻结生长期间视觉阶段；分段魔树移除整树 AnimatedSwitcher，土壤层固定在视口底部；卷须生长从整体缩放改为 ClipRect 显露。验证：...
```

把 Step 1 的实际测试结果补完整。

- [ ] **Step 4: 更新代码地图**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' scripts/update_code_map.sh
```

- [ ] **Step 5: 最终提交**

```powershell
git add DevelopmentPlan.md docs\CODE_MAP.md lib\presentation\outline\magic_tree_model.dart lib\presentation\outline\outline_page.dart test\presentation\magic_tree_model_test.dart test\presentation\outline_page_test.dart
git commit -m "重构魔树新增章节自然生长动画"
```

---

## Claude 执行注意事项

- 不要再把 `treeGrowthFactor` 调大来追求“树长高”；当前问题不是不够高，而是增长方式不自然。
- 不要再给整棵树套 `AnimatedSwitcher` 或整图 `Transform.scale`。
- 如果发现固定土壤后树干和土壤连接处有缝，优先用一个 16-24px 的暗部渐变遮罩压住接缝，不要移动土壤。
- 如果连续新增章节期间动画状态冲突，使用“最后一次目标 offset 覆盖前一次 pan，但不中断当前 growBranch”的策略。
- 如果某个测试因为现有 widget 层私有状态不好测，优先把判断抽到 `magic_tree_model.dart` 的纯函数，再用单测覆盖。

## 自检清单

- [ ] 方案没有要求新增重型依赖。
- [ ] 每个任务都有独立测试和 commit。
- [ ] 根因覆盖用户两点反馈：土壤乱动、树后期比例失调。
- [ ] 额外覆盖视频里可见问题：整树鬼影、卷须整体缩放。
- [ ] 验收包含自动测试和实际视频/真机观察。
