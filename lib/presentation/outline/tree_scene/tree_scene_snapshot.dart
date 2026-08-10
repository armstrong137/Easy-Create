import 'dart:math' as math;

import '../../../domain/entities/outline_chapter.dart';

const _heightLockNodes = 19;

class TreeSceneSectionSnapshot {
  const TreeSceneSectionSnapshot({
    required this.id,
    required this.title,
    required this.sortOrder,
    required this.inspirationCount,
  });

  final int id;
  final String title;
  final int sortOrder;
  final int inspirationCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sortOrder': sortOrder,
    'inspirationCount': inspirationCount,
  };
}

class TreeSceneChapterSnapshot {
  const TreeSceneChapterSnapshot({
    required this.id,
    required this.title,
    required this.sortOrder,
    required this.inspirationCount,
    required this.sections,
  });

  final int id;
  final String title;
  final int sortOrder;
  final int inspirationCount;
  final List<TreeSceneSectionSnapshot> sections;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sortOrder': sortOrder,
    'inspirationCount': inspirationCount,
    'sections': sections.map((section) => section.toJson()).toList(),
  };
}

class TreeSceneSnapshot {
  const TreeSceneSnapshot({
    required this.novelId,
    required this.chapters,
    required this.structuralAge,
    required this.focusedChapterId,
  });

  factory TreeSceneSnapshot.fromOutline({
    required int novelId,
    required List<OutlineChapter> outline,
    required int? focusedChapterId,
    Map<int, int> chapterInspirationCounts = const {},
    Map<int, int> sectionInspirationCounts = const {},
  }) {
    final sortedOutline = [...outline]
      ..sort(
        (left, right) =>
            left.chapter.sortOrder.compareTo(right.chapter.sortOrder),
      );
    final chapters = [
      for (final item in sortedOutline)
        TreeSceneChapterSnapshot(
          id: item.chapter.id,
          title: item.chapter.title,
          sortOrder: item.chapter.sortOrder,
          inspirationCount: chapterInspirationCounts[item.chapter.id] ?? 0,
          sections: [
            for (final section in [
              ...item.sections,
            ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder)))
              TreeSceneSectionSnapshot(
                id: section.id,
                title: section.title,
                sortOrder: section.sortOrder,
                inspirationCount: sectionInspirationCounts[section.id] ?? 0,
              ),
          ],
        ),
    ];
    final sectionCount = chapters.fold<int>(
      0,
      (sum, chapter) => sum + chapter.sections.length,
    );
    final heightNodes = math.min(
      chapters.length + sectionCount,
      _heightLockNodes,
    );
    final visualNodes = math.max(chapters.length, heightNodes);
    final structuralAge = visualNodes == 0
        ? 0.0
        : 1 - math.exp(-visualNodes / 12);
    return TreeSceneSnapshot(
      novelId: novelId,
      chapters: chapters,
      structuralAge: structuralAge,
      focusedChapterId: focusedChapterId,
    );
  }

  final int novelId;
  final List<TreeSceneChapterSnapshot> chapters;
  final double structuralAge;
  final int? focusedChapterId;

  Map<String, Object?> toJson() => {
    'novelId': novelId,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'structuralAge': structuralAge,
    'focusedChapterId': focusedChapterId,
  };
}

enum TreeMutationType {
  none,
  addChapter,
  addSection,
  removeChapter,
  removeSection,
  renameNode,
  updateInspirationCount,
  focusChapter,
  syncSnapshot,
}

class TreeMutation {
  const TreeMutation({
    required this.type,
    this.nodeId,
    this.parentId,
    this.structuralAgeChanged = false,
  });

  final TreeMutationType type;
  final int? nodeId;
  final int? parentId;
  final bool structuralAgeChanged;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'nodeId': nodeId,
    'parentId': parentId,
    'structuralAgeChanged': structuralAgeChanged,
  };
}

TreeMutation diffTreeSnapshots(
  TreeSceneSnapshot before,
  TreeSceneSnapshot after,
) {
  final ageChanged = before.structuralAge != after.structuralAge;
  final beforeChapters = {
    for (final chapter in before.chapters) chapter.id: chapter,
  };
  final afterChapters = {
    for (final chapter in after.chapters) chapter.id: chapter,
  };

  for (final chapter in after.chapters) {
    if (!beforeChapters.containsKey(chapter.id)) {
      return TreeMutation(
        type: TreeMutationType.addChapter,
        nodeId: chapter.id,
        structuralAgeChanged: ageChanged,
      );
    }
  }
  for (final chapter in before.chapters) {
    if (!afterChapters.containsKey(chapter.id)) {
      return TreeMutation(
        type: TreeMutationType.removeChapter,
        nodeId: chapter.id,
        structuralAgeChanged: ageChanged,
      );
    }
  }

  for (final chapter in after.chapters) {
    final previous = beforeChapters[chapter.id]!;
    final beforeSections = {
      for (final section in previous.sections) section.id: section,
    };
    final afterSections = {
      for (final section in chapter.sections) section.id: section,
    };
    for (final section in chapter.sections) {
      if (!beforeSections.containsKey(section.id)) {
        return TreeMutation(
          type: TreeMutationType.addSection,
          nodeId: section.id,
          parentId: chapter.id,
          structuralAgeChanged: ageChanged,
        );
      }
    }
    for (final section in previous.sections) {
      if (!afterSections.containsKey(section.id)) {
        return TreeMutation(
          type: TreeMutationType.removeSection,
          nodeId: section.id,
          parentId: chapter.id,
          structuralAgeChanged: ageChanged,
        );
      }
    }
  }

  for (final chapter in after.chapters) {
    final previous = beforeChapters[chapter.id]!;
    if (chapter.title != previous.title ||
        chapter.sortOrder != previous.sortOrder) {
      return TreeMutation(
        type: TreeMutationType.renameNode,
        nodeId: chapter.id,
      );
    }
    final previousSections = {
      for (final section in previous.sections) section.id: section,
    };
    for (final section in chapter.sections) {
      final oldSection = previousSections[section.id]!;
      if (section.title != oldSection.title ||
          section.sortOrder != oldSection.sortOrder) {
        return TreeMutation(
          type: TreeMutationType.renameNode,
          nodeId: section.id,
          parentId: chapter.id,
        );
      }
    }
  }

  for (final chapter in after.chapters) {
    final previous = beforeChapters[chapter.id]!;
    if (chapter.inspirationCount != previous.inspirationCount) {
      return TreeMutation(
        type: TreeMutationType.updateInspirationCount,
        nodeId: chapter.id,
      );
    }
    final previousSections = {
      for (final section in previous.sections) section.id: section,
    };
    for (final section in chapter.sections) {
      if (section.inspirationCount !=
          previousSections[section.id]!.inspirationCount) {
        return TreeMutation(
          type: TreeMutationType.updateInspirationCount,
          nodeId: section.id,
          parentId: chapter.id,
        );
      }
    }
  }

  if (before.focusedChapterId != after.focusedChapterId) {
    return TreeMutation(
      type: TreeMutationType.focusChapter,
      nodeId: after.focusedChapterId,
      structuralAgeChanged: false,
    );
  }
  if (!_sameSnapshot(before, after)) {
    return TreeMutation(
      type: TreeMutationType.syncSnapshot,
      structuralAgeChanged: ageChanged,
    );
  }
  return const TreeMutation(type: TreeMutationType.none);
}

bool _sameSnapshot(TreeSceneSnapshot left, TreeSceneSnapshot right) {
  if (left.novelId != right.novelId ||
      left.structuralAge != right.structuralAge ||
      left.focusedChapterId != right.focusedChapterId ||
      left.chapters.length != right.chapters.length) {
    return false;
  }
  for (var index = 0; index < left.chapters.length; index += 1) {
    final a = left.chapters[index];
    final b = right.chapters[index];
    if (a.id != b.id ||
        a.title != b.title ||
        a.sortOrder != b.sortOrder ||
        a.inspirationCount != b.inspirationCount ||
        a.sections.length != b.sections.length) {
      return false;
    }
    for (
      var sectionIndex = 0;
      sectionIndex < a.sections.length;
      sectionIndex += 1
    ) {
      final x = a.sections[sectionIndex];
      final y = b.sections[sectionIndex];
      if (x.id != y.id ||
          x.title != y.title ||
          x.sortOrder != y.sortOrder ||
          x.inspirationCount != y.inspirationCount) {
        return false;
      }
    }
  }
  return true;
}
