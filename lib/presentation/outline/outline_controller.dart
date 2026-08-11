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
  }) {
    _wasStaticFallback = scene.useStaticFallback;
    scene.addListener(_handleSceneChanged);
  }

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
  List<OutlineChapter> _latestOutline = const [];
  final Map<int, int> _focusedSectionIds = {};
  int? _focusedChapterId;
  ({int id, int focusRevision})? _pendingCreatedChapter;
  ({int chapterId, int sectionId, int focusRevision})? _pendingCreatedSection;
  ({int chapterId, int? sectionId})? _pendingSceneFocus;
  bool _pendingSceneFocusIsManual = false;
  bool _mutationInFlight = false;
  bool _disposed = false;
  bool _wasStaticFallback = false;
  int _manualFocusRevision = 0;

  TreeSceneSnapshot? get snapshot => _snapshot;
  int? get focusedChapterId => _focusedChapterId;
  int? focusedSectionId(int chapterId) => _focusedSectionIds[chapterId];

  Future<Chapter> addChapter() async {
    final focusRevision = _manualFocusRevision;
    final chapter = await createChapter();
    if (_manualFocusRevision != focusRevision) return chapter;
    _pendingCreatedChapter = (id: chapter.id, focusRevision: focusRevision);
    _confirmCreatedFocusFromLatestOutline();
    return chapter;
  }

  Future<Section> addSection(int chapterId) async {
    final focusRevision = _manualFocusRevision;
    final section = await createSection(chapterId);
    if (_manualFocusRevision != focusRevision) return section;
    _pendingCreatedSection = (
      chapterId: section.chapterId,
      sectionId: section.id,
      focusRevision: focusRevision,
    );
    _confirmCreatedFocusFromLatestOutline();
    return section;
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
    _manualFocusRevision += 1;
    _pendingSceneFocus = null;
    _pendingSceneFocusIsManual = false;
    if (_mutationInFlight) {
      _pendingSceneFocus = (chapterId: chapterId, sectionId: null);
      _pendingSceneFocusIsManual = true;
    }
    if (_focusedChapterId == chapterId) {
      scene.focusChapter(chapterId, animate: animate);
      return;
    }
    _focusedChapterId = chapterId;
    _updateStoredSnapshotFocus(chapterId);
    scene.focusChapter(chapterId, animate: animate);
  }

  void focusSection(int chapterId, int sectionId, {bool animate = true}) {
    _manualFocusRevision += 1;
    _pendingSceneFocus = null;
    _pendingSceneFocusIsManual = false;
    if (_mutationInFlight) {
      _pendingSceneFocus = (chapterId: chapterId, sectionId: sectionId);
      _pendingSceneFocusIsManual = true;
    }
    _focusedSectionIds[chapterId] = sectionId;
    scene.focusSection(chapterId, sectionId, animate: animate);
  }

  void onOutlineChanged(
    List<OutlineChapter> outline, {
    Map<int, int> chapterInspirationCounts = const {},
    Map<int, int> sectionInspirationCounts = const {},
    bool animateMutations = true,
  }) {
    if (_disposed) return;
    _latestOutline = outline;
    final confirmedFocus = _takeConfirmedCreatedFocus(outline);
    if (confirmedFocus != null) _applyConfirmedFocus(confirmedFocus);
    final latestChapter = outline.isEmpty ? null : outline.last.chapter.id;
    if (_focusedChapterId == null ||
        !outline.any((item) => item.chapter.id == _focusedChapterId)) {
      _focusedChapterId = latestChapter;
    }
    final next = TreeSceneSnapshot.fromOutline(
      novelId: novelId,
      outline: outline,
      focusedChapterId: _focusedChapterId,
      chapterInspirationCounts: chapterInspirationCounts,
      sectionInspirationCounts: sectionInspirationCounts,
    );
    final before = _snapshot;
    if (before == null) {
      _snapshot = next;
      scene.syncSnapshot(next);
      if (confirmedFocus?.sectionId != null) {
        _scheduleSceneFocus(confirmedFocus!);
      }
      return;
    }
    final mutation = diffTreeSnapshots(before, next);
    if (!animateMutations) {
      if (mutation.type != TreeMutationType.none || _mutationInFlight) {
        _snapshot = next;
        _mutationInFlight = false;
        _deferredSnapshot = null;
        scene.syncSnapshot(next);
      }
      if (confirmedFocus?.sectionId != null) {
        _scheduleSceneFocus(confirmedFocus!);
      }
      return;
    }
    if (mutation.type == TreeMutationType.none) {
      if (confirmedFocus?.sectionId != null) {
        _scheduleSceneFocus(confirmedFocus!);
      }
      return;
    }
    if (_mutationInFlight) {
      _deferredSnapshot = next;
      if (confirmedFocus?.sectionId != null) {
        _scheduleSceneFocus(confirmedFocus!);
      }
      return;
    }
    _dispatchMutation(mutation, next);
    if (confirmedFocus?.sectionId != null) {
      _scheduleSceneFocus(confirmedFocus!);
    }
  }

  Future<void> onSceneEvent(TreeSceneEvent event) async {
    if (_disposed || event.type != 'tree.mutationCompleted') return;
    _mutationInFlight = false;
    final deferred = _deferredSnapshot;
    _deferredSnapshot = null;
    if (deferred == null) {
      _flushPendingSceneFocus();
      return;
    }
    final before = _snapshot;
    if (before == null) {
      _snapshot = deferred;
      scene.syncSnapshot(deferred);
      _flushPendingSceneFocus();
      return;
    }
    final mutation = diffTreeSnapshots(before, deferred);
    if (mutation.type != TreeMutationType.none) {
      _dispatchMutation(mutation, deferred);
    }
    _flushPendingSceneFocus();
  }

  void _handleSceneChanged() {
    final useStaticFallback = scene.useStaticFallback;
    if (useStaticFallback && !_wasStaticFallback) {
      _enterStaticFallback();
    }
    _wasStaticFallback = useStaticFallback;
  }

  void _enterStaticFallback() {
    if (_disposed) return;
    final latest = _deferredSnapshot ?? _snapshot;
    _mutationInFlight = false;
    _deferredSnapshot = null;
    _pendingSceneFocus = null;
    _pendingSceneFocusIsManual = false;
    if (latest == null) return;
    _snapshot = latest;
    scene.syncSnapshot(latest);
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

  ({int chapterId, int? sectionId})? _takeConfirmedCreatedFocus(
    List<OutlineChapter> outline,
  ) {
    ({int chapterId, int? sectionId})? confirmed;
    final chapter = _pendingCreatedChapter;
    if (chapter != null &&
        outline.any((item) => item.chapter.id == chapter.id)) {
      _pendingCreatedChapter = null;
      if (chapter.focusRevision == _manualFocusRevision) {
        confirmed = (chapterId: chapter.id, sectionId: null);
      }
    }

    final section = _pendingCreatedSection;
    if (section != null &&
        outline.any(
          (item) =>
              item.chapter.id == section.chapterId &&
              item.sections.any((value) => value.id == section.sectionId),
        )) {
      _pendingCreatedSection = null;
      if (section.focusRevision == _manualFocusRevision) {
        confirmed = (
          chapterId: section.chapterId,
          sectionId: section.sectionId,
        );
      }
    }
    return confirmed;
  }

  void _confirmCreatedFocusFromLatestOutline() {
    final confirmed = _takeConfirmedCreatedFocus(_latestOutline);
    if (confirmed == null) return;
    _applyConfirmedFocus(confirmed);
    _updateStoredSnapshotFocus(confirmed.chapterId);
    _scheduleSceneFocus(confirmed);
  }

  void _applyConfirmedFocus(({int chapterId, int? sectionId}) confirmed) {
    _focusedChapterId = confirmed.chapterId;
    final sectionId = confirmed.sectionId;
    if (sectionId != null) {
      _focusedSectionIds[confirmed.chapterId] = sectionId;
    }
  }

  void _updateStoredSnapshotFocus(int chapterId) {
    final current = _snapshot;
    if (current != null &&
        current.chapters.any((chapter) => chapter.id == chapterId)) {
      _snapshot = _withFocusedChapter(current, chapterId);
    }
    final deferred = _deferredSnapshot;
    if (deferred != null &&
        deferred.chapters.any((chapter) => chapter.id == chapterId)) {
      _deferredSnapshot = _withFocusedChapter(deferred, chapterId);
    }
  }

  TreeSceneSnapshot _withFocusedChapter(
    TreeSceneSnapshot snapshot,
    int chapterId,
  ) => TreeSceneSnapshot(
    novelId: snapshot.novelId,
    chapters: snapshot.chapters,
    structuralAge: snapshot.structuralAge,
    focusedChapterId: chapterId,
  );

  void _scheduleSceneFocus(({int chapterId, int? sectionId}) focus) {
    if (_pendingSceneFocusIsManual) return;
    _pendingSceneFocus = focus;
    _flushPendingSceneFocus();
  }

  void _flushPendingSceneFocus() {
    if (_mutationInFlight) return;
    final focus = _pendingSceneFocus;
    final current = _snapshot;
    if (focus == null || current == null) return;
    TreeSceneChapterSnapshot? chapter;
    for (final item in current.chapters) {
      if (item.id == focus.chapterId) chapter = item;
    }
    if (chapter == null) {
      _pendingSceneFocus = null;
      _pendingSceneFocusIsManual = false;
      return;
    }
    final sectionId = focus.sectionId;
    if (sectionId != null &&
        !chapter.sections.any((section) => section.id == sectionId)) {
      _pendingSceneFocus = null;
      _pendingSceneFocusIsManual = false;
      return;
    }
    _pendingSceneFocus = null;
    _pendingSceneFocusIsManual = false;
    if (sectionId == null) {
      scene.focusChapter(focus.chapterId);
    } else {
      scene.focusSection(focus.chapterId, sectionId);
    }
  }

  void dispose() {
    _disposed = true;
    _deferredSnapshot = null;
    _pendingSceneFocus = null;
    _pendingSceneFocusIsManual = false;
    scene.removeListener(_handleSceneChanged);
  }
}
