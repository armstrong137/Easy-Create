import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_snapshot.dart';

OutlineChapter chapter(int id, {String? title, int sections = 0}) {
  return OutlineChapter(
    chapter: Chapter(
      id: id,
      novelId: 1,
      title: title ?? '第$id章',
      sortOrder: id,
    ),
    sections: [
      for (var index = 0; index < sections; index += 1)
        Section(
          id: id * 100 + index,
          chapterId: id,
          title: '第${index + 1}节',
          sortOrder: index,
        ),
    ],
  );
}

TreeSceneSnapshot snapshot(
  List<OutlineChapter> outline, {
  int? focus,
  Map<int, int> chapterCounts = const {},
  Map<int, int> sectionCounts = const {},
}) {
  return TreeSceneSnapshot.fromOutline(
    novelId: 1,
    outline: outline,
    focusedChapterId: focus,
    chapterInspirationCounts: chapterCounts,
    sectionInspirationCounts: sectionCounts,
  );
}

void main() {
  test('新增章、新增节、删除章、删除节各自产生唯一主差异', () {
    final one = snapshot([chapter(1, sections: 1)], focus: 1);
    final twoChapters = snapshot([
      chapter(1, sections: 1),
      chapter(2),
    ], focus: 2);
    final twoSections = snapshot([chapter(1, sections: 2)], focus: 1);

    expect(
      diffTreeSnapshots(one, twoChapters).type,
      TreeMutationType.addChapter,
    );
    expect(
      diffTreeSnapshots(one, twoSections).type,
      TreeMutationType.addSection,
    );
    expect(
      diffTreeSnapshots(twoChapters, one).type,
      TreeMutationType.removeChapter,
    );
    expect(
      diffTreeSnapshots(twoSections, one).type,
      TreeMutationType.removeSection,
    );
  });

  test('重命名、灵感数和无变化差异互不混淆', () {
    final original = snapshot([chapter(1, sections: 1)], focus: 1);
    final renamed = snapshot([
      chapter(1, title: '新的章名', sections: 1),
    ], focus: 1);
    final counted = snapshot(
      [chapter(1, sections: 1)],
      focus: 1,
      sectionCounts: const {100: 3},
    );

    expect(
      diffTreeSnapshots(original, renamed).type,
      TreeMutationType.renameNode,
    );
    expect(
      diffTreeSnapshots(original, counted).type,
      TreeMutationType.updateInspirationCount,
    );
    expect(diffTreeSnapshots(original, original).type, TreeMutationType.none);
  });

  test('十章回看引子只改变聚焦，不改变结构树龄', () {
    final outline = [
      for (var id = 1; id <= 10; id += 1) chapter(id, sections: 2),
    ];
    final latest = snapshot(outline, focus: 10);
    final prologue = snapshot(outline, focus: 1);
    final mutation = diffTreeSnapshots(latest, prologue);

    expect(prologue.structuralAge, latest.structuralAge);
    expect(mutation.type, TreeMutationType.focusChapter);
    expect(mutation.structuralAgeChanged, isFalse);
  });

  test('树高封顶后新增小节不再改变主树龄', () {
    final before = snapshot([chapter(1, sections: 18)], focus: 1);
    final after = snapshot([chapter(1, sections: 19)], focus: 1);

    expect(after.structuralAge, before.structuralAge);
    expect(diffTreeSnapshots(before, after).type, TreeMutationType.addSection);
  });

  test('快照输出只包含可 JSON 编码的稳定字段', () {
    final value = snapshot(
      [chapter(1, sections: 1)],
      focus: 1,
      chapterCounts: const {1: 2},
      sectionCounts: const {100: 4},
    ).toJson();

    expect(value['novelId'], 1);
    expect(value['focusedChapterId'], 1);
    final chapters = value['chapters']! as List<Object?>;
    expect(chapters.single, isA<Map<String, Object?>>());
  });
}
