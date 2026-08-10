import 'dart:async';

import '../../data/database/app_database.dart';
import '../../domain/entities/outline_chapter.dart';
import 'tree_scene/tree_scene_controller.dart';
import 'tree_scene/tree_scene_protocol.dart';
import 'tree_scene/tree_scene_snapshot.dart';

enum TreeTargetKind { chapter, section }

class TreeTarget {
  const TreeTarget.chapter(this.id)
    : kind = TreeTargetKind.chapter,
      chapterId = null;

  const TreeTarget.section(this.id, {required this.chapterId})
    : kind = TreeTargetKind.section;

  final TreeTargetKind kind;
  final int id;
  final int? chapterId;
}

class OutlineController {
  OutlineController({
    required this.novelId,
    required this.scene,
    required this.createChapter,
    required this.createSection,
    required this.renameChapter,
    required this.renameSection,
    required this.deleteChapter,
    required this.deleteSection,
  });

  final int novelId;
  final TreeSceneController scene;
  final Future<Chapter> Function() createChapter;
  final Future<Section> Function(int chapterId) createSection;
  final Future<void> Function(int id, String title) renameChapter;
  final Future<void> Function(int id, String title) renameSection;
  final Future<void> Function(int id) deleteChapter;
  final Future<void> Function(int id) deleteSection;

  TreeSceneSnapshot? _snapshot;
  TreeSceneSnapshot? _deferredSnapshot;
  bool _mutationInFlight = false;
  bool _disposed = false;

  TreeSceneSnapshot? get snapshot => _snapshot;

  Future<void> addChapter() async {
    await createChapter();
  }

  Future<void> addSection(int chapterId) async {
    await createSection(chapterId);
  }

  Future<void> rename(TreeTarget target, String title) {
    return target.kind == TreeTargetKind.chapter
        ? renameChapter(target.id, title)
        : renameSection(target.id, title);
  }

  Future<void> remove(TreeTarget target) {
    return target.kind == TreeTargetKind.chapter
        ? deleteChapter(target.id)
        : deleteSection(target.id);
  }

  void focusChapter(int chapterId, {bool animate = true}) {
    final current = _snapshot;
    if (current == null || current.focusedChapterId == chapterId) return;
    _snapshot = TreeSceneSnapshot(
      novelId: current.novelId,
      chapters: current.chapters,
      structuralAge: current.structuralAge,
      focusedChapterId: chapterId,
    );
    scene.focusChapter(chapterId, animate: animate);
  }

  void onOutlineChanged(
    List<OutlineChapter> outline, {
    Map<int, int> chapterInspirationCounts = const {},
    Map<int, int> sectionInspirationCounts = const {},
  }) {
    if (_disposed) return;
    final currentFocus = _snapshot?.focusedChapterId;
    final latestChapter = outline.isEmpty ? null : outline.last.chapter.id;
    final next = TreeSceneSnapshot.fromOutline(
      novelId: novelId,
      outline: outline,
      focusedChapterId: currentFocus ?? latestChapter,
      chapterInspirationCounts: chapterInspirationCounts,
      sectionInspirationCounts: sectionInspirationCounts,
    );
    final before = _snapshot;
    if (before == null) {
      _snapshot = next;
      scene.syncSnapshot(next);
      return;
    }
    final mutation = diffTreeSnapshots(before, next);
    if (mutation.type == TreeMutationType.none) return;
    if (_mutationInFlight) {
      _deferredSnapshot = next;
      return;
    }
    _dispatchMutation(mutation, next);
  }

  Future<void> onSceneEvent(TreeSceneEvent event) async {
    if (_disposed || event.type != 'tree.mutationCompleted') return;
    _mutationInFlight = false;
    final deferred = _deferredSnapshot;
    _deferredSnapshot = null;
    if (deferred == null) return;
    final before = _snapshot;
    if (before == null) {
      _snapshot = deferred;
      scene.syncSnapshot(deferred);
      return;
    }
    final mutation = diffTreeSnapshots(before, deferred);
    if (mutation.type != TreeMutationType.none) {
      _dispatchMutation(mutation, deferred);
    }
  }

  void _dispatchMutation(TreeMutation mutation, TreeSceneSnapshot next) {
    _snapshot = next;
    if (mutation.type == TreeMutationType.focusChapter) {
      final chapterId = mutation.nodeId;
      if (chapterId != null) scene.focusChapter(chapterId);
      return;
    }
    _mutationInFlight = true;
    scene.playMutation(mutation, next);
  }

  void dispose() {
    _disposed = true;
    _deferredSnapshot = null;
  }
}
