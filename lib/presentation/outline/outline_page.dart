import 'dart:async';

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
import 'tree_scene/tree_standin.dart';

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

/// 大纲页｜完整实时 3D 魔树
///
/// Flutter 持有数据库与弹层，three.js 持有树龄、枝丫、镜头和标签投影。
/// 左半屏切章，右半屏切当前章的小节；双击空白分别新增章或节。
/// 标签支持进入小节、重命名与删除，灵感通过三维射线命中挂靠到章或节。
class OutlinePage extends ConsumerStatefulWidget {
  const OutlinePage({
    super.key,
    required this.novelId,
    required this.title,
    this.treeSceneBuilder,
  });

  final int novelId;
  final String title;
  final Widget Function(TreeSceneController controller)? treeSceneBuilder;

  @override
  ConsumerState<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends ConsumerState<OutlinePage> {
  late final TreeSceneController _treeSceneController;
  late final OutlineController _outlineController;
  StreamSubscription? _treeSceneEvents;
  final TreeSceneGestures _realtimeGestures = TreeSceneGestures();
  late final TreeDragBridge _realtimeDragBridge;
  final GlobalKey _realtimeTreeKey = GlobalKey();
  final Set<String> _awaitingProjection = {};
  final Set<String> _projectedOnce = {};
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
    if (_projectedOnce.contains(key)) return;
    _awaitingProjection.add(key);
  }

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

  Future<void> _createChapter() async {
    if (_creatingChapter) return;
    setState(() => _creatingChapter = true);
    HapticFeedback.lightImpact();
    try {
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

    return Expanded(
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

              Widget staticLabel(PlacedLabel label, Rect rect) {
                final key = label.chapterId != null
                    ? Key('静态章热区_${label.chapterId}')
                    : Key('静态节热区_${label.sectionId}');
                final interactionKey = label.chapterId != null
                    ? Key('静态章交互_${label.chapterId}')
                    : Key('静态节交互_${label.sectionId}');
                return Positioned.fromRect(
                  rect: rect,
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
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xEAFDF6EC),
                                border: Border.all(
                                  color: candidates.isEmpty
                                      ? const Color(0x996D4B24)
                                      : const Color(0xFFD9A441),
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33241408),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    label.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'LXGWWenKai',
                                      fontSize: label.chapterId != null
                                          ? 16
                                          : 14,
                                      fontWeight: label.chapterId != null
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                );
              }

              final staticMode =
                  !enable3D || _treeSceneController.useStaticFallback;
              final windowLabels = <({PlacedLabel label, Rect rect})>[];
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
                final chapters = outline
                    .skip(firstChapter)
                    .take(2)
                    .toList(growable: false);
                for (var index = 0; index < chapters.length; index += 1) {
                  final chapter = chapters[index];
                  windowLabels.add((
                    label: PlacedLabel(
                      text: chapter.chapter.title,
                      chapterId: chapter.chapter.id,
                    ),
                    rect: Rect.fromLTWH(
                      18,
                      constraints.maxHeight * 0.34 + index * 74,
                      112,
                      48,
                    ),
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
                final firstSection = (focusedSectionIndex - 2).clamp(
                  0,
                  (focusedChapter.sections.length - 5).clamp(
                    0,
                    focusedChapter.sections.length,
                  ),
                );
                final sections = focusedChapter.sections
                    .skip(firstSection)
                    .take(5)
                    .toList(growable: false);
                for (var index = 0; index < sections.length; index += 1) {
                  final section = sections[index];
                  windowLabels.add((
                    label: PlacedLabel(
                      text: section.title,
                      sectionId: section.id,
                    ),
                    rect: Rect.fromLTWH(
                      constraints.maxWidth - 130,
                      constraints.maxHeight * 0.30 + index * 58,
                      112,
                      42,
                    ),
                  ));
                }
              }

              bool awaitsProjection(PlacedLabel label) {
                final key = label.chapterId != null
                    ? 'chapter:${label.chapterId}'
                    : 'section:${label.sectionId}';
                return _awaitingProjection.contains(key);
              }

              return Stack(
                key: _realtimeTreeKey,
                children: [
                  if (enable3D && !_treeSceneController.useStaticFallback)
                    Positioned.fill(
                      child:
                          widget.treeSceneBuilder?.call(_treeSceneController) ??
                          TreeScene(controller: _treeSceneController),
                    ),
                  if (!enable3D ||
                      !_treeSceneController.isReady ||
                      _treeSceneController.useStaticFallback)
                    Positioned.fill(
                      child: TreeStandin(
                        age: _outlineController.snapshot?.structuralAge ?? 0,
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: constraints.maxWidth / 2,
                    child: GestureDetector(
                      key: const Key('左空白区'),
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: _createChapter,
                      onVerticalDragStart: (_) => _realtimeGestures.begin(
                        x: 0,
                        width: constraints.maxWidth,
                      ),
                      onVerticalDragUpdate: (details) {
                        _realtimeGestures.update(
                          deltaY: details.delta.dy,
                          x: 0,
                          width: constraints.maxWidth,
                        );
                        _treeSceneController.pan(-details.delta.dy * 0.014);
                      },
                      onVerticalDragEnd: (_) =>
                          moveChapter(_realtimeGestures.end()),
                      onVerticalDragCancel: _realtimeGestures.cancel,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: constraints.maxWidth / 2,
                    child: GestureDetector(
                      key: const Key('右空白区'),
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () => _createSection(outline),
                      onVerticalDragStart: (_) => _realtimeGestures.begin(
                        x: constraints.maxWidth,
                        width: constraints.maxWidth,
                      ),
                      onVerticalDragUpdate: (details) =>
                          _realtimeGestures.update(
                            deltaY: details.delta.dy,
                            x: constraints.maxWidth,
                            width: constraints.maxWidth,
                          ),
                      onVerticalDragEnd: (_) =>
                          moveSection(_realtimeGestures.end()),
                      onVerticalDragCancel: _realtimeGestures.cancel,
                    ),
                  ),
                  for (final projection in _treeSceneController.visibleLabels)
                    if (!staticMode) labelHotspot(projection),
                  for (final item in windowLabels)
                    if (staticMode || awaitsProjection(item.label))
                      staticLabel(item.label, item.rect),
                  Positioned(
                    left: 8,
                    top: constraints.maxHeight * 0.16,
                    child: _SproutAction(
                      semanticKey: const Key('新增章节入口'),
                      semanticLabel: '新增章节',
                      pending: _creatingChapter,
                      progressKey: const Key('新增章节进度'),
                      onPressed: _creatingChapter ? null : _createChapter,
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }

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
    final enable3D = ref.watch(advanced3DProvider);
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
    }

    return Scaffold(
      backgroundColor: _parchment,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header(context)),
          _realtimeTreeBody(outline, enable3D: enable3D),
        ],
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
              width: 62,
              height: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: pending
                        ? CircularProgressIndicator(
                            key: progressKey,
                            strokeWidth: 2,
                            color: _ink,
                          )
                        : const Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.eco_outlined,
                                  size: 25,
                                  color: _ink,
                                ),
                              ),
                              Positioned(
                                right: -2,
                                top: -5,
                                child: Text(
                                  '+',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Text(
                    pending ? '生长中' : '新芽 +',
                    style: const TextStyle(
                      fontFamily: 'LXGWWenKai',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink,
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
