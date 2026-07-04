import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/label_layout.dart';
import 'package:novel_app/presentation/outline/magic_tree_model.dart';

/// 魔树布局（2026-07-03 镜头窗口改版）：
/// 章序自上而下（第一章树顶方向）；>2 章进入窗口模式一屏两章
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

  const size = Size(400, 800);

  test('空大纲：无枝，仅幼苗树干（光杆魔树）', () {
    final layout = layoutMagicTree(size: size, outline: []);
    expect(layout.chapters, isEmpty);
    expect(layout.sections, isEmpty);
    expect(layout.age, 0);
    expect(layout.windowMode, isFalse);
    expect(layout.trunkRect.height, greaterThan(0));
  });

  test('章枝全部向左、节枝全部向右（tip 相对树干中线）', () {
    final layout = layoutMagicTree(
      size: size,
      outline: [chapterWith(1, 2), chapterWith(2, 1)],
    );
    for (final c in layout.chapters) {
      expect(c.tip.dx, lessThan(size.width / 2), reason: '章枝端在左半屏');
    }
    for (final s in layout.sections) {
      expect(s.tip.dx, greaterThan(size.width / 2), reason: '节枝端在右半屏');
    }
  });

  test('章序自上而下：第一章最高；节落在本章高度带内（左右对应）', () {
    final layout = layoutMagicTree(
      size: size,
      outline: [chapterWith(1, 2), chapterWith(2, 2)],
    );
    expect(layout.chapters[0].root.dy,
        lessThan(layout.chapters[1].root.dy),
        reason: '第一章根更高（y 更小），新章向土壤方向生长');

    final band1 = layout.chapterBands[1]!;
    for (final s in layout.sections.where((s) => s.id ~/ 100 == 1)) {
      expect(s.root.dy, inInclusiveRange(band1.$1, band1.$2));
    }
  });

  test('chapterForY：点击高度映射到对应章（上早下晚）', () {
    final layout = layoutMagicTree(
      size: size,
      outline: [chapterWith(1, 0), chapterWith(2, 0)],
    );
    final band1 = layout.chapterBands[1]!;
    final band2 = layout.chapterBands[2]!;
    expect(layout.chapterForY((band1.$1 + band1.$2) / 2), 1);
    expect(layout.chapterForY((band2.$1 + band2.$2) / 2), 2);
    expect(layout.chapterForY(0), 1, reason: '树梢之上归第一章');
    expect(layout.chapterForY(size.height), 2, reason: '土壤之下归最后一章');
  });

  test('>2 章进入窗口模式：一屏两章，镜头从树顶滑到土壤', () {
    final outline = [for (var i = 1; i <= 5; i++) chapterWith(i, 1)];

    final top = layoutMagicTree(size: size, outline: outline);
    expect(top.windowMode, isTrue);
    expect(top.maxChapterOffset, 3);
    expect(top.imageRect.top, 0, reason: '镜头在首章 → 看到树顶');
    expect(top.chapterBands.keys, contains(1));
    expect(top.chapterBands.keys, contains(2));
    expect(top.chapterBands.keys, isNot(contains(5)), reason: '一屏只两章');

    final bottom =
        layoutMagicTree(size: size, outline: outline, chapterOffset: 3);
    expect(bottom.imageRect.bottom, closeTo(size.height, 0.5),
        reason: '镜头在末章 → 看到土壤');
    expect(bottom.chapterBands.keys, contains(4));
    expect(bottom.chapterBands.keys, contains(5));
    expect(bottom.chapterBands.keys, isNot(contains(1)));
  });

  test('虚拟树高随章数增长（生长速度变化，有封顶）', () {
    expect(treeGrowthFactor(2), 1);
    expect(treeGrowthFactor(5), greaterThan(treeGrowthFactor(3)));
    expect(treeGrowthFactor(50), lessThanOrEqualTo(2.15));
  });

  test('窗口模式小节溢出可滚：滚动量把后面的节带进带内', () {
    final outline = [chapterWith(1, 12), chapterWith(2, 0), chapterWith(3, 0)];
    final layout = layoutMagicTree(size: size, outline: outline);
    final max = layout.sectionScrollMax[1]!;
    expect(max, greaterThan(0), reason: '12 节放不下半屏，必须可滚');

    Set<int> ids(MagicTreeLayout l) =>
        l.sections.map((s) => s.id).toSet();
    final before = ids(layout);
    final after = ids(layoutMagicTree(
        size: size, outline: outline, sectionScrolls: {1: max}));
    expect(before, contains(100), reason: '未滚动时第一节可见');
    expect(after, contains(100 + 11), reason: '滚到底后最后一节可见');
    expect(after, isNot(contains(100)), reason: '第一节被滚出带外');
  });

  test('窗口模式标签两两不重叠且不出画布', () {
    final layout = layoutMagicTree(
      size: size,
      outline: [for (var i = 1; i <= 6; i++) chapterWith(i, 3)],
      chapterOffset: 2,
    );
    final labels = placeMagicLabels(layout, canvasWidth: size.width);
    expect(labels, isNotEmpty);
    for (var a = 0; a < labels.length; a++) {
      for (var b = a + 1; b < labels.length; b++) {
        expect(labels[a].rect.overlaps(labels[b].rect), isFalse,
            reason: '${labels[a].text} 与 ${labels[b].text} 不应重叠');
      }
      expect(labels[a].rect.left, greaterThanOrEqualTo(0), reason: '不出左缘');
      expect(labels[a].rect.right, lessThanOrEqualTo(size.width),
          reason: '不出右缘');
    }
  });
}
