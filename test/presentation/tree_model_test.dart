import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/label_layout.dart';
import 'package:novel_app/presentation/outline/tree_model.dart';

/// 阶段四·1：树龄模型与枝丫布局（纯函数）
void main() {
  OutlineChapter chapterWith(int id, int sectionCount) => OutlineChapter(
        chapter:
            Chapter(id: id, novelId: 1, title: '第$id章', sortOrder: id),
        sections: [
          for (var j = 0; j < sectionCount; j++)
            Section(
                id: id * 100 + j,
                chapterId: id,
                title: '第${j + 1}节',
                sortOrder: j),
        ],
      );

  group('树龄 treeAge（生态成长）', () {
    test('零章节 = 幼苗 0；随规模单调增长；封顶不超过 1', () {
      expect(treeAge(0), 0);
      expect(treeAge(3), greaterThan(treeAge(1)));
      expect(treeAge(30), greaterThan(treeAge(3)));
      expect(treeAge(100000), lessThanOrEqualTo(1));
    });
  });

  group('layoutTree 布局', () {
    const size = Size(400, 800);

    test('空大纲：无枝丫，树龄 0（秃树）', () {
      final tree = layoutTree(size: size, outline: []);
      expect(tree.branches, isEmpty);
      expect(tree.age, 0);
    });

    test('章数 = 枝数，左右交替，第一章最低', () {
      final tree = layoutTree(
        size: size,
        outline: [chapterWith(1, 0), chapterWith(2, 0), chapterWith(3, 0)],
      );
      expect(tree.branches, hasLength(3));
      expect(tree.branches[0].leftSide, isTrue);
      expect(tree.branches[1].leftSide, isFalse);
      expect(tree.branches[2].leftSide, isTrue);
      expect(tree.branches[0].start.dy, greaterThan(tree.branches[1].start.dy),
          reason: '第一章枝根在树干更低处（y 更大）');
    });

    test('节数 = 所属章枝的节枝数', () {
      final tree =
          layoutTree(size: size, outline: [chapterWith(1, 3)]);
      expect(tree.branches.single.twigs, hasLength(3));
      expect(tree.branches.single.twigs[0].title, '第1节');
    });

    test('placeLabels：密集树上标签两两不重叠', () {
      final tree = layoutTree(
        size: size,
        outline: [for (var i = 1; i <= 6; i++) chapterWith(i, 3)],
      );
      final labels = placeLabels(tree);
      expect(labels, hasLength(6 + 18), reason: '每章每节各一枚标签');
      for (var a = 0; a < labels.length; a++) {
        for (var b = a + 1; b < labels.length; b++) {
          expect(labels[a].rect.overlaps(labels[b].rect), isFalse,
              reason: '标签 ${labels[a].text} 与 ${labels[b].text} 不应重叠');
        }
      }
    });

    test('树随章节增多而长高变粗（生态成长）', () {
      final sapling = layoutTree(size: size, outline: [chapterWith(1, 0)]);
      final old = layoutTree(size: size, outline: [
        for (var i = 1; i <= 8; i++) chapterWith(i, 4),
      ]);
      final saplingHeight = sapling.trunkBase.dy - sapling.trunkTop.dy;
      final oldHeight = old.trunkBase.dy - old.trunkTop.dy;
      expect(oldHeight, greaterThan(saplingHeight), reason: '老树更高');
      expect(old.trunkWidth, greaterThan(sapling.trunkWidth), reason: '老树干更粗');
      expect(old.age, greaterThan(sapling.age));
    });
  });
}
