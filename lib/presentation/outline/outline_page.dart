import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import '../section/section_page.dart';
import '../home/planet_scene/planet_scene.dart' show advanced3DProvider;
import '../shared/soft_toast.dart';
import 'label_layout.dart';
import 'magic_carpet.dart';
import 'outline_controller.dart';
import 'tree_scene/tree_scene.dart';
import 'tree_scene/tree_scene_controller.dart';
import 'tree_scene/tree_scene_gestures.dart';
import 'tree_scene/illustrated_tree_scene.dart';
import 'tree_scene/tree_standin.dart';
import 'tree_scene/illustrated_tree_viewport.dart';
import 'tree_scene/illustrated_tree_trunk.dart';
import 'tree_scene/sapling_plaque.dart';
import 'tree_scene/illustrated_tree_camera_layout.dart';
import 'tree_scene/organic_tree.dart';
import 'tree_scene/organic_branch.dart' show organicBranchRootRatio, OrganicBranchPainter;
import 'tree_scene/organic_tree_camera_layout.dart';

/// 某小说的大纲流（章+节），魔树数据源
final outlineProvider = StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

/// 某小说下"已挂靠小节的灵感"，按 section_id 分组（新的在前）。
/// 大纲页在每个小节标签下显示最新几条。
final sectionInspirationsProvider =
    StreamProvider.family<Map<int, List<Inspiration>>, int>(
      (ref, novelId) =>
          ref.watch(novelRepositoryProvider).watchSectionInspirations(novelId),
    );

/// 某小说下"直接挂靠到章的灵感"，按 chapter_id 分组（新的在前）。
final chapterInspirationsProvider =
    StreamProvider.family<Map<int, List<Inspiration>>, int>(
      (ref, novelId) =>
          ref.watch(novelRepositoryProvider).watchChapterInspirations(novelId),
    );

/// 羊皮纸背景与深树皮文字色。
const _parchment = Color(0xFFFDF6EC);
const _ink = Color(0xFF3A2A18);
const _enableExperimentalTree3D = bool.fromEnvironment(
  'ENABLE_EXPERIMENTAL_TREE_3D',
);

/// 大纲页｜高保真 2D 魔树正式场景
///
/// Flutter 持有数据库、树龄、枝牌与弹层；实验 3D 仅由编译期开关启用。
/// 左半屏切章，右半屏切当前章的小节；双击空白分别新增章或节。
/// 枝牌支持进入小节、重命名与删除，灵感可以拖放到章或节。
class OutlinePage extends ConsumerStatefulWidget {
  const OutlinePage({
    super.key,
    required this.novelId,
    required this.title,
    this.treeSceneBuilder,
    this.enableIllustratedCamera = const bool.fromEnvironment('ENABLE_ILLUSTRATED_TREE_CAMERA'),
  });

  final int novelId;
  final String title;
  final bool enableIllustratedCamera;
  final Widget Function(TreeSceneController controller)? treeSceneBuilder;

  @override
  ConsumerState<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends ConsumerState<OutlinePage> {
  bool _treeOverview = false;
  late final TreeSceneController _treeSceneController;
  late final OutlineController _outlineController;
  StreamSubscription? _treeSceneEvents;
  final TreeSceneGestures _realtimeGestures = TreeSceneGestures();
  late final TreeDragBridge _realtimeDragBridge;
  final GlobalKey _realtimeTreeKey = GlobalKey();
  final Set<String> _awaitingProjection = {};
  final Set<String> _projectedOnce = {};
  Set<String>? _knownIllustratedNodeKeys;
  final Set<String> _growingIllustratedNodeKeys = {};
  bool _creatingChapter = false;
  bool _creatingSection = false;

  /// 上次设给魔毯的缩边栏状态，避免每帧重复通知。
  bool _lastTuck = false;

  @override
  void initState() {
    super.initState();
    _treeSceneController = TreeSceneController();
    _realtimeDragBridge = TreeDragBridge(
      now: DateTime.now,
      send: _treeSceneController.setDragPoint,
    );
    final repository = ref.read(novelRepositoryProvider);
    _outlineController = OutlineController(
      novelId: widget.novelId,
      scene: _treeSceneController,
      createChapter: () => repository.createChapter(novelId: widget.novelId),
      createSection: (chapterId) =>
          repository.createSection(chapterId: chapterId),
      renameChapter: repository.renameChapter,
      renameSection: repository.renameSection,
      deleteChapter: repository.deleteChapter,
      deleteSection: repository.deleteSection,
    );
    _treeSceneEvents = _treeSceneController.events.listen(
      _outlineController.onSceneEvent,
    );
    _treeSceneController.addListener(_clearProjectedBridges);
  }

  void _clearProjectedBridges() {
    final projected = {
      for (final item in _treeSceneController.visibleLabels)
        '${item.kind}:${item.id}',
    };
    _projectedOnce.addAll(projected);
    if (_awaitingProjection.isEmpty) return;
    _awaitingProjection.removeWhere(projected.contains);
  }

  void _bridgeUntilProjected(String key) {
    if (_knownIllustratedNodeKeys?.contains(key) ?? false) return;
    if (_projectedOnce.contains(key)) return;
    _awaitingProjection.add(key);
  }

  void _markIllustratedGrowthStarted(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_growingIllustratedNodeKeys.remove(key)) return;
      setState(() {});
    });
  }

  int _illustratedNodeCount(List<OutlineChapter> outline) => outline.fold<int>(
    outline.length,
    (total, chapter) => total + chapter.sections.length,
  );

  Set<String> _illustratedNodeKeys(List<OutlineChapter> outline) => {
    for (final chapter in outline) ...{
      'chapter:${chapter.chapter.id}',
      for (final section in chapter.sections) 'section:${section.id}',
    },
  };

  void _syncIllustratedNodeGrowth(
    List<OutlineChapter> outline, {
    required bool enabled,
  }) {
    if (!enabled) {
      _knownIllustratedNodeKeys = null;
      _growingIllustratedNodeKeys.clear();
      return;
    }
    final current = _illustratedNodeKeys(outline);
    final known = _knownIllustratedNodeKeys;
    if (known != null) {
      _growingIllustratedNodeKeys.addAll(current.difference(known));
    }
    _knownIllustratedNodeKeys = current;
    _awaitingProjection.removeAll(current);
  }

  Future<void> _precacheIllustratedMutation(int nextNodeCount) => Future.wait([
    precacheImage(
      AssetImage(illustratedTreeAssetForNodeCount(nextNodeCount)),
      context,
    ),
    precacheImage(const AssetImage(illustratedBranchAsset), context),
  ]);

  @override
  void dispose() {
    carpetTucked.value = false; // 离开大纲页恢复完整魔毯球
    _treeSceneEvents?.cancel();
    _treeSceneController.removeListener(_clearProjectedBridges);
    _outlineController.dispose();
    _treeSceneController.dispose();
    super.dispose();
  }

  int? _currentChapterId(List<OutlineChapter> outline) {
    final focused = _outlineController.focusedChapterId;
    if (focused != null && outline.any((item) => item.chapter.id == focused)) {
      return focused;
    }
    return outline.isEmpty ? null : outline.last.chapter.id;
  }

  Future<void> _createChapter(List<OutlineChapter> outline) async {
    if (_creatingChapter) return;
    setState(() => _creatingChapter = true);
    HapticFeedback.lightImpact();
    try {
      await _precacheIllustratedMutation(_illustratedNodeCount(outline) + 1);
      if (!mounted) return;
      final chapter = await _outlineController.addChapter();
      if (mounted) {
        setState(() => _bridgeUntilProjected('chapter:${chapter.id}'));
      }
    } catch (_) {
      if (mounted) showSoftToast(context, '创建章节失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _creatingChapter = false);
    }
  }

  Future<void> _createSection(List<OutlineChapter> outline) async {
    if (_creatingSection) return;
    final chapterId = _currentChapterId(outline);
    if (chapterId == null) {
      showSoftToast(context, '先点左边空白，长出第一根章枝吧');
      return;
    }
    setState(() => _creatingSection = true);
    HapticFeedback.lightImpact();
    try {
      await _precacheIllustratedMutation(_illustratedNodeCount(outline) + 1);
      if (!mounted) return;
      final section = await _outlineController.addSection(chapterId);
      if (mounted) {
        setState(() => _bridgeUntilProjected('section:${section.id}'));
      }
    } catch (_) {
      if (mounted) showSoftToast(context, '创建小节失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _creatingSection = false);
    }
  }

  Widget _realtimeTreeBody(
    List<OutlineChapter> outline, {
    required bool enable3D,
  }) {
    void focusChapter(int chapterId, {bool animate = true}) {
      _outlineController.focusChapter(chapterId, animate: animate);
      if (mounted) setState(() {});
    }

    void moveChapter(TreeGestureDirection direction) {
      if (direction == TreeGestureDirection.none || outline.isEmpty) return;
      final focused = _outlineController.focusedChapterId;
      var index = outline.indexWhere((item) => item.chapter.id == focused);
      if (index < 0) index = outline.length - 1;
      final delta = direction == TreeGestureDirection.previous ? -1 : 1;
      final next = (index + delta).clamp(0, outline.length - 1);
      focusChapter(outline[next].chapter.id);
    }

    void moveSection(TreeGestureDirection direction) {
      if (direction == TreeGestureDirection.none || outline.isEmpty) return;
      final chapterId =
          _outlineController.focusedChapterId ?? outline.last.chapter.id;
      OutlineChapter? chapter;
      for (final item in outline) {
        if (item.chapter.id == chapterId) chapter = item;
      }
      if (chapter == null || chapter.sections.isEmpty) return;
      final focused = _outlineController.focusedSectionId(chapterId);
      var index = chapter.sections.indexWhere(
        (section) => section.id == focused,
      );
      if (index < 0) index = chapter.sections.length - 1;
      final delta = direction == TreeGestureDirection.previous ? -1 : 1;
      final next = (index + delta).clamp(0, chapter.sections.length - 1);
      final sectionId = chapter.sections[next].id;
      _outlineController.focusSection(chapterId, sectionId);
      setState(() {});
    }

    PlacedLabel? projectedLabel(TreeLabelProjection projection) {
      if (projection.kind == 'chapter') {
        for (final item in outline) {
          if (item.chapter.id == projection.id) {
            return PlacedLabel(
              text: item.chapter.title,
              chapterId: item.chapter.id,
            );
          }
        }
      } else {
        for (final item in outline) {
          for (final section in item.sections) {
            if (section.id == projection.id) {
              return PlacedLabel(text: section.title, sectionId: section.id);
            }
          }
        }
      }
      return null;
    }

    Future<void> assignInspiration(
      Inspiration inspiration,
      PlacedLabel label,
    ) async {
      final repository = ref.read(inspirationRepositoryProvider);
      if (label.chapterId != null) {
        await repository.assignToChapter(inspiration.id, label.chapterId!);
      } else if (label.sectionId != null) {
        await repository.assignToSection(inspiration.id, label.sectionId!);
      } else {
        return;
      }
      magicCarpetKey.currentState?.collapse();
    }

    Future<void> acceptInspiration(Inspiration inspiration) async {
      final hit = _treeSceneController.dragHit;
      _treeSceneController.endDrag();
      _realtimeDragBridge.reset();
      if (hit == null) return;
      await assignInspiration(
        inspiration,
        PlacedLabel(
          text: '',
          chapterId: hit.kind == 'chapter' ? hit.id : null,
          sectionId: hit.kind == 'section' ? hit.id : null,
        ),
      );
    }

    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) => DragTarget<Inspiration>(
          onWillAcceptWithDetails: (_) => outline.isNotEmpty,
          onMove: (details) {
            final box =
                _realtimeTreeKey.currentContext?.findRenderObject()
                    as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            _realtimeDragBridge.update(
              x: local.dx / box.size.width,
              y: local.dy / box.size.height,
            );
          },
          onLeave: (_) {
            _treeSceneController.endDrag();
            _realtimeDragBridge.reset();
          },
          onAcceptWithDetails: (details) => acceptInspiration(details.data),
          builder: (context, candidates, rejected) => AnimatedBuilder(
            animation: _treeSceneController,
            builder: (context, _) {
              final staticMode =
                  !enable3D || _treeSceneController.useStaticFallback;

              Widget labelHotspot(TreeLabelProjection projection) {
                final label = projectedLabel(projection);
                if (label == null) return const SizedBox.shrink();
                return Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    projection.rect.left * constraints.maxWidth,
                    projection.rect.top * constraints.maxHeight,
                    projection.rect.width * constraints.maxWidth,
                    projection.rect.height * constraints.maxHeight,
                  ),
                  child: Semantics(
                    label: label.text,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: label.sectionId != null
                          ? () => _openSection(label)
                          : () => focusChapter(label.chapterId!),
                      onDoubleTap: label.chapterId != null
                          ? () => _onDoubleTap(label)
                          : null,
                      onLongPress: () => _showBranchMenu(label),
                      child: _treeSceneController.dragHit?.id == projection.id
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0x99D9A441),
                                  width: 2,
                                ),
                              ),
                            )
                          : const SizedBox.expand(),
                    ),
                  ),
                );
              }

              Widget staticLabel(
                PlacedLabel label,
                Rect rect, {
                required IllustratedBranchSide side,
                required bool selected,
                double? maxSupportRadius,
                double treeScale = 1,
                Path? trunkMask,
                double barkAge = 1,
                ui.Image? bark,
              }) {
                final key = label.chapterId != null
                    ? Key('静态章热区_${label.chapterId}')
                    : Key('静态节热区_${label.sectionId}');
                final interactionKey = label.chapterId != null
                    ? Key('静态章交互_${label.chapterId}')
                    : Key('静态节交互_${label.sectionId}');
                final revealKey = label.chapterId != null
                    ? 'chapter:${label.chapterId}'
                    : 'section:${label.sectionId}';
                final animateIn = _growingIllustratedNodeKeys.contains(
                  revealKey,
                );
                if (animateIn && staticMode) {
                  _markIllustratedGrowthStarted(revealKey);
                }
                return AnimatedPositioned(
                  key: ValueKey(revealKey),
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  duration: const Duration(milliseconds: 460),
                  curve: Curves.easeOutCubic,
                  child: Semantics(
                    label: label.text,
                    button: true,
                    child: GestureDetector(
                      key: interactionKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (label.sectionId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SectionPage(
                                sectionId: label.sectionId!,
                                initialTitle: label.text,
                              ),
                            ),
                          );
                          return;
                        }
                        focusChapter(label.chapterId!, animate: false);
                      },
                      onDoubleTap: label.chapterId != null
                          ? () => _onDoubleTap(label)
                          : null,
                      onLongPress: () => _showBranchMenu(label),
                      child: DragTarget<Inspiration>(
                        key: key,
                        onWillAcceptWithDetails: (_) => true,
                        onAcceptWithDetails: (details) =>
                            assignInspiration(details.data, label),
                        builder: (context, candidates, rejected) =>
                            ExcludeSemantics(
                              child: _illustratedNodeCount(outline) == 1 && !widget.enableIllustratedCamera
                                ? SaplingPlaqueTitle(title: label.text,
                                    selected: selected || candidates.isNotEmpty)
                                : IllustratedBranchPlaque(
                                title: label.text,
                                side: side,
                                selected: selected || candidates.isNotEmpty,
                                animateIn: animateIn,
                                organicGrowth: widget.enableIllustratedCamera,
                                maxSupportRadius: maxSupportRadius,
                                treeScale: treeScale,
                                trunkMask: trunkMask,
                                barkAge: barkAge,
                                bark: bark,
                              ),
                            ),
                      ),
                    ),
                  ),
                );
              }

              final chapterStep = constraints.maxHeight * 0.22;
              final cameraMode = staticMode && widget.enableIllustratedCamera;
              IllustratedTreeCameraLayout cameraLayout = cameraMode
                  ? OrganicTreeCameraLayout(Size(constraints.maxWidth, constraints.maxHeight), outline.length, 0, focusedChapter: 0)
                  : IllustratedTreeCameraLayout(Size(constraints.maxWidth, constraints.maxHeight), outline.length, 0);
              final sceneHeight = cameraMode ? cameraLayout.sceneHeight : constraints.maxHeight;
              var cameraRow = 0;
              final windowLabels =
                  <
                    ({
                      PlacedLabel label,
                      Rect rect,
                      IllustratedBranchSide side,
                      bool selected,
                      double? nativeFraction,
                    })
                  >[];
              if (outline.isNotEmpty) {
                final focusedChapterId =
                    _outlineController.focusedChapterId ??
                    outline.last.chapter.id;
                var focusedIndex = outline.indexWhere(
                  (item) => item.chapter.id == focusedChapterId,
                );
                if (focusedIndex < 0) focusedIndex = outline.length - 1;
                final firstChapter = (focusedIndex - 1).clamp(
                  0,
                  (outline.length - 2).clamp(0, outline.length),
                );
                cameraRow = cameraMode ? firstChapter : 0;
                cameraLayout = cameraMode
                    ? OrganicTreeCameraLayout(Size(constraints.maxWidth, constraints.maxHeight), outline.length, firstChapter, focusedChapter: focusedIndex)
                    : IllustratedTreeCameraLayout(Size(constraints.maxWidth, constraints.maxHeight), outline.length, firstChapter);
                final chapters = outline
                    .skip(firstChapter)
                    .take(2)
                    .toList(growable: false);
                final nodeCount = _illustratedNodeCount(outline);
                final age = illustratedTreeLayoutAgeForNodeCount(nodeCount);
                final branchWidth = math
                    .min(
                      constraints.maxWidth * 0.72,
                      constraints.maxHeight * 0.42,
                    )
                    .clamp(180.0, 320.0);
                final branchHeight = branchWidth / 1.5;
                final chapterTop =
                    constraints.maxHeight * (0.17 + (1 - age) * 0.34);
                for (var index = 0; index < chapters.length; index += 1) {
                  final chapter = chapters[index];
                  windowLabels.add((
                    label: PlacedLabel(
                      text: chapter.chapter.title,
                      chapterId: chapter.chapter.id,
                    ),
                      rect: cameraMode ? cameraLayout.branchRect(right: false, index: index) : nodeCount == 1 ? saplingPlaqueRect(Size(constraints.maxWidth, constraints.maxHeight)) : Rect.fromLTWH(
                      -branchWidth * 0.06,
                      chapterTop + (index + cameraRow) * chapterStep,
                      branchWidth,
                      branchHeight,
                    ),
                    side: IllustratedBranchSide.left,
                    nativeFraction: cameraMode ? (cameraLayout as OrganicTreeCameraLayout).anchorFraction(right: false, index: index) : null,
                    selected: chapter.chapter.id == focusedChapterId,
                  ));
                }

                final focusedChapter = outline[focusedIndex];
                final focusedSectionId = _outlineController.focusedSectionId(
                  focusedChapter.chapter.id,
                );
                var focusedSectionIndex = focusedChapter.sections.indexWhere(
                  (section) => section.id == focusedSectionId,
                );
                if (focusedSectionIndex < 0) {
                  focusedSectionIndex = focusedChapter.sections.length - 1;
                }
                final firstSection = (focusedSectionIndex - 1).clamp(
                  0,
                  (focusedChapter.sections.length - 2).clamp(
                    0,
                    focusedChapter.sections.length,
                  ),
                );
                final sections = focusedChapter.sections
                    .skip(firstSection)
                    .take(2)
                    .toList(growable: false);
                final selectedSectionId =
                    focusedSectionId ??
                    (focusedChapter.sections.isEmpty
                        ? null
                        : focusedChapter.sections.last.id);
                final sectionTop =
                    constraints.maxHeight * (0.29 + (1 - age) * 0.22);
                final sectionStep = constraints.maxHeight * 0.22;
                for (var index = 0; index < sections.length; index += 1) {
                  final section = sections[index];
                  windowLabels.add((
                    label: PlacedLabel(
                      text: section.title,
                      sectionId: section.id,
                    ),
                    rect: cameraMode ? cameraLayout.branchRect(right: true, index: index) : Rect.fromLTWH(
                      constraints.maxWidth - branchWidth * 0.94,
                      sectionTop + cameraRow * chapterStep + index * sectionStep,
                      branchWidth,
                      branchHeight,
                    ),
                    side: IllustratedBranchSide.right,
                    nativeFraction: cameraMode ? (cameraLayout as OrganicTreeCameraLayout).anchorFraction(right: true, index: index) : null,
                    selected: section.id == selectedSectionId,
                  ));
                }
              }

              bool awaitsProjection(PlacedLabel label) {
                final key = label.chapterId != null
                    ? 'chapter:${label.chapterId}'
                    : 'section:${label.sectionId}';
                return _awaitingProjection.contains(key);
              }

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (details) {
                  _realtimeGestures.begin(
                    x: details.localPosition.dx,
                    width: constraints.maxWidth,
                  );
                },
                onVerticalDragUpdate: (details) {
                  _realtimeGestures.update(
                    deltaY: details.delta.dy,
                    x: details.localPosition.dx,
                    width: constraints.maxWidth,
                  );
                  if (_realtimeGestures.owner == TreeGestureOwner.chapter) {
                    _treeSceneController.pan(-details.delta.dy * 0.014);
                  }
                },
                onVerticalDragEnd: (_) {
                  final owner = _realtimeGestures.owner;
                  final direction = _realtimeGestures.end();
                  if (owner == TreeGestureOwner.chapter) {
                    moveChapter(direction);
                  } else if (owner == TreeGestureOwner.section) {
                    moveSection(direction);
                  }
                },
                onVerticalDragCancel: _realtimeGestures.cancel,
                child: Stack(
                  key: _realtimeTreeKey,
                  children: [
                    if (enable3D && !_treeSceneController.useStaticFallback)
                      Positioned.fill(
                        child:
                            widget.treeSceneBuilder?.call(
                              _treeSceneController,
                            ) ??
                            TreeScene(controller: _treeSceneController),
                      ),
                    if (!enable3D ||
                        !_treeSceneController.isReady ||
                        _treeSceneController.useStaticFallback)
                      Positioned.fill(
                        child: IllustratedTreeViewport(
                          sceneHeight: sceneHeight,
                          sceneWidth: cameraMode ? cameraLayout.sceneWidth : null,
                          chapterScale: cameraMode ? cameraLayout.chapterScale : 1,
                          focusX: cameraMode ? cameraLayout.focusX : null,
                          overview: cameraMode && _treeOverview,
                          focusY: cameraMode ? cameraLayout.focusY : constraints.maxHeight * 0.5,
                          child: cameraMode ? OrganicTree(
                            age: (_illustratedNodeCount(outline) / 10).clamp(0.0, 1.0),
                            foregroundBuilder: (context, frame, bark) => Stack(
                              fit: StackFit.expand,
                              children: [
                                _creationZones(outline),
                                for (final item in windowLabels)
                                  if (frame.anchorAt(item.nativeFraction!) != null)
                                    staticLabel(item.label, item.rect, side: item.side, selected: item.selected,
                                      treeScale: (cameraLayout as OrganicTreeCameraLayout).projection.scale,
                                      barkAge: frame.age,
                                      bark: bark,
                                      trunkMask: OrganicBranchPainter.sectionPath(frame.limbs.first.sections)
                                        .transform(Matrix4.diagonal3Values(cameraLayout.projection.scale,
                                          cameraLayout.projection.scale, 1).storage)
                                        .shift(cameraLayout.projection.origin - item.rect.topLeft),
                                      maxSupportRadius: math.min(item.rect.height * organicBranchRootRatio,
                                        frame.trunkRadiusAt(item.nativeFraction!) *
                                          cameraLayout.projection.scale * .75)),
                              ],
                            ),
                          ) : Stack(
                            fit: StackFit.expand,
                            children: [
                              TreeStandin(
                                showGrowthLight: false,
                                stage: illustratedTreeStageForNodeCount(
                                  _illustratedNodeCount(outline),
                                ),
                                growthRevision: _illustratedNodeCount(outline),
                                completeCrown: cameraMode && outline.length > 2,
                              ),
                              if (staticMode) _creationZones(outline),
                              if (staticMode)
                                for (final item in windowLabels)
                                  staticLabel(item.label, item.rect,
                                    side: item.side, selected: item.selected),
                              if (staticMode)
                                IllustratedTreeTrunk(
                                  branchNecks: cameraMode ? [
                                    for (final item in windowLabels)
                                      Rect.fromCenter(
                                        center: Offset(item.rect.left + item.rect.width *
                                            (item.side == IllustratedBranchSide.left ? .88 : .12),
                                          item.rect.top + item.rect.height * .7),
                                        width: item.rect.width * .2,
                                        height: item.rect.height * .22,
                                      ),
                                  ] : null,
                                  stage: illustratedTreeStageForNodeCount(
                                    _illustratedNodeCount(outline),
                                  ),
                                  completeCrown: cameraMode && outline.length > 2,
                                ),
                              IllustratedTreeGrowthLight(
                                growthRevision: _illustratedNodeCount(outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!staticMode) Positioned.fill(child: _creationZones(outline)),
                    for (final projection in _treeSceneController.visibleLabels)
                      if (!staticMode) labelHotspot(projection),
                    for (final item in windowLabels)
                      if (!staticMode && awaitsProjection(item.label))
                        staticLabel(
                          item.label,
                          item.rect,
                          side: item.side,
                          selected: item.selected,
                        ),
                    Positioned(
                      left: 8,
                      top: constraints.maxHeight * 0.16,
                      child: _SproutAction(
                        semanticKey: const Key('新增章节入口'),
                        semanticLabel: '新增章节',
                        pending: _creatingChapter,
                        progressKey: const Key('新增章节进度'),
                        onPressed: _creatingChapter
                            ? null
                            : () => _createChapter(outline),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: constraints.maxHeight * 0.16,
                      child: _SproutAction(
                        semanticKey: const Key('新增小节入口'),
                        semanticLabel: '新增小节',
                        semanticHint: outline.isEmpty ? '请先创建章节' : null,
                        pending: _creatingSection,
                        progressKey: const Key('新增小节进度'),
                        onPressed: outline.isEmpty || _creatingSection
                            ? null
                            : () => _createSection(outline),
                      ),
                    ),
                    if (cameraMode)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Center(
                          child: TextButton.icon(
                            key: const Key('魔树全景切换'),
                            onPressed: () => setState(() => _treeOverview = !_treeOverview),
                            icon: Icon(_treeOverview ? CupertinoIcons.zoom_in : CupertinoIcons.zoom_out, color: _ink),
                            label: Text(_treeOverview ? '返回章节' : '全景', style: const TextStyle(color: _ink)),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 空白新增手势位于枝牌下层，不能覆盖章牌或延迟新芽按钮的轻点。
  Widget _creationZones(List<OutlineChapter> outline) => Row(children: [
    Expanded(child: GestureDetector(
      key: const Key('左空白区'),
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => _createChapter(outline),
      child: const SizedBox.expand(),
    )),
    Expanded(child: GestureDetector(
      key: const Key('右空白区'),
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => _createSection(outline),
      child: const SizedBox.expand(),
    )),
  ]);

  TextStyle _dlgStyle({double size = 17, FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: 'LXGWWenKai',
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  /// 重命名弹窗（章/节共用，iOS 质感）
  Future<void> _rename(PlacedLabel label) async {
    final controller = TextEditingController(text: label.text);
    final newTitle = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          label.chapterId != null ? '重命名这一章' : '重命名这一节',
          style: _dlgStyle(weight: FontWeight.w600),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            key: const Key('重命名输入框'),
            controller: controller,
            autofocus: true,
            style: _dlgStyle(size: 15, color: _ink),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('重命名确认按钮'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('保存', style: _dlgStyle(weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == label.text) return;
    final repo = ref.read(novelRepositoryProvider);
    if (label.chapterId != null) {
      await repo.renameChapter(label.chapterId!, title);
    } else {
      await repo.renameSection(label.sectionId!, title);
    }
  }

  /// 删除（带确认；删章级联删节、灵感放回魔毯）
  Future<void> _delete(PlacedLabel label) async {
    final isChapter = label.chapterId != null;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          '剪掉「${label.text}」？',
          style: _dlgStyle(weight: FontWeight.w600),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            isChapter
                ? '这一章和它的所有小节都会被剪掉；挂在上面的灵感会放回灵感卷轴。'
                : '这一节会被剪掉；挂在上面的灵感会放回灵感卷轴。',
            style: _dlgStyle(size: 13),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('删除确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '剪掉',
              style: _dlgStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final repo = ref.read(novelRepositoryProvider);
    if (isChapter) {
      await repo.deleteChapter(label.chapterId!);
    } else {
      await repo.deleteSection(label.sectionId!);
    }
  }

  /// 长按枝端标签：iOS 动作面板（重命名 / 剪掉）
  Future<void> _showBranchMenu(PlacedLabel label) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(label.text, style: _dlgStyle(size: 14)),
        actions: [
          CupertinoActionSheetAction(
            key: const Key('菜单重命名'),
            onPressed: () => Navigator.of(context).pop('rename'),
            child: Text(
              label.chapterId != null ? '重命名这一章' : '重命名这一节',
              style: _dlgStyle(),
            ),
          ),
          CupertinoActionSheetAction(
            key: const Key('菜单删除'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('delete'),
            child: Text(
              '剪掉这根枝丫',
              style: _dlgStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: _dlgStyle(weight: FontWeight.w600)),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(label);
    if (action == 'delete') await _delete(label);
  }

  /// 单击节标签 → 直接进小节页（用户定稿：单击即进）
  void _openSection(PlacedLabel label) {
    if (label.sectionId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SectionPage(sectionId: label.sectionId!, initialTitle: label.text),
      ),
    );
  }

  /// 双击：章 → 重命名（节的进入改为单击，见 _openSection）
  Future<void> _onDoubleTap(PlacedLabel label) async {
    if (label.sectionId != null) {
      _openSection(label);
    } else {
      await _rename(label);
    }
  }

  /// 极简自绘头部（替代 Material AppBar）。
  /// 标题用 Stack 相对**整屏**居中（Row+Expanded 会因左箭头/右留白
  /// 不对称而偏移，用户反馈"名字要左右居中"）；两侧对称避让魔毯球。
  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 104),
              child: Text(
                widget.title,
                key: const Key('大纲页书名'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  // 深色树皮经过标题下方时，细浅轮廓保留字形，不遮住树体。
                  shadows: [
                    Shadow(color: _parchment, offset: Offset(-1, -1), blurRadius: 1),
                    Shadow(color: _parchment, offset: Offset(1, -1), blurRadius: 1),
                    Shadow(color: _parchment, offset: Offset(-1, 1), blurRadius: 1),
                    Shadow(color: _parchment, offset: Offset(1, 1), blurRadius: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => Navigator.of(context).maybePop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(CupertinoIcons.back, color: _ink, size: 26),
            ),
          ),
        ),
      ],
    ),
  );

  /// 生长中枝的当前比例（未在生长的枝恒为 1）
  @override
  Widget build(BuildContext context) {
    final outlineState = ref.watch(outlineProvider(widget.novelId));
    final outline = outlineState.value ?? const <OutlineChapter>[];
    final requested3D = ref.watch(advanced3DProvider);
    final enable3D =
        requested3D &&
        (_enableExperimentalTree3D || widget.treeSceneBuilder != null);
    _treeSceneController.setTransportEnabled(
      enable3D && !_treeSceneController.useStaticFallback,
    );

    final wantTuck = outline.length > 2;
    if (_lastTuck != wantTuck) {
      _lastTuck = wantTuck;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => carpetTucked.value = wantTuck,
      );
    }

    final sectionInspirations =
        ref.watch(sectionInspirationsProvider(widget.novelId)).value ??
        const <int, List<Inspiration>>{};
    final chapterInspirations =
        ref.watch(chapterInspirationsProvider(widget.novelId)).value ??
        const <int, List<Inspiration>>{};

    if (outlineState.hasValue) {
      _outlineController.onOutlineChanged(
        outline,
        chapterInspirationCounts: {
          for (final entry in chapterInspirations.entries)
            entry.key: entry.value.length,
        },
        sectionInspirationCounts: {
          for (final entry in sectionInspirations.entries)
            entry.key: entry.value.length,
        },
        animateMutations: enable3D && !_treeSceneController.useStaticFallback,
      );
      _syncIllustratedNodeGrowth(
        outline,
        enabled: !enable3D || _treeSceneController.useStaticFallback,
      );
    }

    return Scaffold(
      backgroundColor: _parchment,
      body: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox(
            width: math.min(constraints.maxWidth, constraints.maxHeight * 0.6),
            height: constraints.maxHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _realtimeTreeBody(outline, enable3D: enable3D),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(bottom: false, child: _header(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SproutAction extends StatelessWidget {
  const _SproutAction({
    required this.semanticKey,
    required this.semanticLabel,
    required this.pending,
    required this.progressKey,
    required this.onPressed,
    this.semanticHint,
  });

  final Key semanticKey;
  final String semanticLabel;
  final String? semanticHint;
  final bool pending;
  final Key progressKey;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !pending;
    return Semantics(
      key: semanticKey,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      hint: semanticHint,
      value: pending ? '创建中' : null,
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          pressedOpacity: 0.55,
          onPressed: enabled ? onPressed : null,
          child: AnimatedOpacity(
            opacity: enabled || pending ? 1 : 0.38,
            duration: const Duration(milliseconds: 140),
            child: SizedBox(
              width: 46,
              height: 46,
              child: pending
                  ? Padding(
                      padding: const EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        key: progressKey,
                        strokeWidth: 2,
                        color: _ink,
                      ),
                    )
                  : const Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.eco_outlined,
                            size: 27,
                            color: _ink,
                          ),
                        ),
                        Positioned(
                          right: 5,
                          top: 3,
                          child: Text(
                            '+',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFC18B2E),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
