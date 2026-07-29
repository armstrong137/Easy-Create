import 'dart:io';
import 'dart:math' as math;
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
    chapter: Chapter(id: id, novelId: 1, title: '第$id章', sortOrder: id),
    sections: [
      for (var j = 0; j < sectionCount; j++)
        Section(
          id: id * 100 + j,
          chapterId: id,
          title: '第${j + 1}节',
          sortOrder: j,
        ),
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
    expect(
      layout.chapters[0].root.dy,
      lessThan(layout.chapters[1].root.dy),
      reason: '第一章根更高（y 更小），新章向土壤方向生长',
    );

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
    expect(
      top.trunkRect.top,
      greaterThanOrEqualTo(0),
      reason: '镜头在首章 → 树顶留在画内（画幅留了成长余量，故不再恒等于 0）',
    );
    expect(top.chapterBands.keys, contains(1));
    expect(top.chapterBands.keys, contains(2));
    expect(top.chapterBands.keys, isNot(contains(5)), reason: '一屏只两章');

    final bottom = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 3,
    );
    expect(
      bottom.soilBottomY,
      closeTo(size.height - 8, 0.5),
      reason: '镜头在末章 → 看到土壤（土堆底贴屏底）',
    );
    expect(bottom.chapterBands.keys, contains(4));
    expect(bottom.chapterBands.keys, contains(5));
    expect(bottom.chapterBands.keys, isNot(contains(1)));
  });

  test('树土分界线必须深过土堆冒头处（否则树干平切口露在泥土上）', () {
    // 用户 2026-07-29 截图实证：分界线取在土堆冒头处（0.807）时那一行土堆只有
    // 63px 宽，而幼藤树干 150px、巨藤 292px，切口整条露出来，整株浮在泥土上面。
    // 0.845 实测该行土堆宽 0.403，宽过所有档最粗的树干（0.310）。
    expect(kSoilSplitFrac, greaterThan(kSoilCrestFrac));
    expect(kSoilSplitFrac, greaterThanOrEqualTo(0.84));
    expect(kSoilSplitFrac, lessThan(kSoilBottomFrac));
  });

  test('枝丫绝不长进土里：所有枝根都在土堆冒头处之上', () {
    for (final n in [1, 2, 3, 6, 10, 18]) {
      final outline = [for (var i = 1; i <= n; i++) chapterWith(i, 1)];
      for (final offset in [0.0, (n - 2).clamp(0, 99).toDouble()]) {
        final l = layoutMagicTree(
          size: size,
          outline: outline,
          chapterOffset: offset,
        );
        for (final b in [...l.chapters, ...l.sections]) {
          expect(
            b.root.dy,
            lessThanOrEqualTo(l.soilCrestY),
            reason: '$n 章 镜头$offset：${b.title} 的枝根落到土堆里了',
          );
        }
      }
    }
  });

  test('窗口模式止血：完整魔树图恒定显示，不再随章数拉伸或分段拼接', () {
    // 止血的本意：禁止"按章数任意拉伸画幅"造假高树 + 禁止分段拼接。
    // 方案乙的连续成长是**有界**的（档内最多长到下一档素材的树高），
    // 且横向恒定、土层恒定，所以这里改成校验这些不变量。
    final first = layoutMagicTree(
      size: size,
      outline: [for (var i = 1; i <= 3; i++) chapterWith(i, 1)],
    );

    for (final count in [3, 8, 19, 40]) {
      final outline = [for (var i = 1; i <= count; i++) chapterWith(i, 1)];
      final topLayout = layoutMagicTree(size: size, outline: outline);
      final top = topLayout.imageRect;
      final bottomLayout = layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: (count - 2).toDouble(),
      );
      final bottom = bottomLayout.imageRect;

      expect(
        top.width,
        closeTo(first.imageRect.width, 0.5),
        reason: '$count 章树宽恒定',
      );
      expect(
        topLayout.soilRect,
        first.soilRect,
        reason: '$count 章时土层完全不动（泥土红线）',
      );
      expect(
        top.height,
        lessThanOrEqualTo(first.imageRect.height * 1.25 + 0.5),
        reason: '$count 章：成长有界，绝不按章数无限拉伸',
      );
      expect(
        topLayout.trunkRect.top,
        greaterThanOrEqualTo(0),
        reason: '$count 章：长到档尾时树冠仍在画内',
      );
      expect(bottom.width, closeTo(top.width, 0.5), reason: '镜头滚动时树宽不变');
      expect(bottom.height, closeTo(top.height, 0.5), reason: '镜头滚动时树高不变');
      expect(
        bottomLayout.soilBottomY,
        closeTo(size.height - 8, 0.5),
        reason: '末章镜头要看到泥土',
      );
      expect(
        layoutMagicTreeImagePieces(topLayout),
        isA<WholeTreeImagePieces>(),
      );
      expect(
        layoutMagicTreeImagePieces(bottomLayout),
        isA<WholeTreeImagePieces>(),
      );
    }
  });

  test('窗口模式止血：禁止再走分段平铺路线', () {
    for (final count in [3, 8, 40]) {
      final layout = layoutMagicTree(
        size: size,
        outline: [for (var i = 1; i <= count; i++) chapterWith(i, 1)],
      );
      final pieces = layoutMagicTreeImagePieces(layout);

      expect(pieces, isA<WholeTreeImagePieces>());
      expect(
        (pieces as WholeTreeImagePieces).asset,
        startsWith('assets/textures/magic_tree_'),
      );
    }
  });

  test('窗口模式止血：模型层禁止重新接入 tree_seg 分段素材', () {
    final src = File(
      'lib/presentation/outline/magic_tree_model.dart',
    ).readAsStringSync();

    expect(src, isNot(contains('SegmentedTreeImagePieces')));
    expect(src, isNot(contains('TreeSegmentSpec')));
    expect(src, isNot(contains('tree_seg')));
    expect(src, isNot(contains('tileOverlap')));
    expect(src, isNot(contains('tileStep')));
  });

  test('单章和双章仍使用整图素材，不进入分段拼接', () {
    final single = layoutMagicTree(size: size, outline: [chapterWith(1, 3)]);
    final two = layoutMagicTree(
      size: size,
      outline: [chapterWith(1, 1), chapterWith(2, 1)],
    );

    expect(layoutMagicTreeImagePieces(single), isA<WholeTreeImagePieces>());
    expect(layoutMagicTreeImagePieces(two), isA<WholeTreeImagePieces>());
  });

  test('窗口模式：首章小节落在章根之下（不飘到树顶/魔毯球旁）', () {
    // 3 章 → 窗口模式；首章带顶贴屏顶、远高于树干顶。
    // 修复前 contentTop=bandTop+34 让小节排到章根之上、窜到树顶（用户反馈错位）。
    final outline = [chapterWith(1, 2), chapterWith(2, 0), chapterWith(3, 0)];
    final layout = layoutMagicTree(size: size, outline: outline);
    expect(layout.windowMode, isTrue);

    final ch1Root = layout.chapters.firstWhere((c) => c.id == 1).root.dy;
    final ch1Sections = layout.sections.where((s) => s.id ~/ 100 == 1);
    expect(ch1Sections, isNotEmpty, reason: '首章小节应可见');
    for (final s in ch1Sections) {
      expect(
        s.root.dy,
        greaterThanOrEqualTo(ch1Root),
        reason: '首章小节 ${s.title} 须在章根之下，不得飘到章的上方',
      );
    }
  });

  test('窗口模式：节枝根点超出可见树干时不进入布局', () {
    // 镜头滑到末章时会看到土壤；修复前末章的底部小节仍会落到树干下方，
    // 页面随后把枝丫画在土堆/留白上。
    final outline = [chapterWith(1, 0), chapterWith(2, 0), chapterWith(3, 1)];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 1,
    );

    expect(layout.windowMode, isTrue);
    for (final s in layout.sections) {
      expect(
        s.root.dy,
        inInclusiveRange(layout.trunkRect.top, layout.trunkRect.bottom),
        reason: '${s.title} 的根点必须留在当前可见树干内，超出树干就不显示枝丫',
      );
    }
  });

  test('窗口模式：未铺满的小节从章带上方开始向下生长', () {
    final outline = [chapterWith(1, 0), chapterWith(2, 0), chapterWith(3, 1)];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 1,
    );

    final band3 = layout.chapterBands[3]!;
    final section = layout.sections.singleWhere((s) => s.id == 300);

    expect(
      section.root.dy,
      lessThan(band3.$1 + kSectionAddZone + kSectionRowHeight),
      reason: '只有一节时应从本章小节区顶部长出，而不是钉在章带最底部',
    );
  });

  test('窗口模式：靠近泥土的小节只隐藏枝丫不隐藏标签', () {
    final outline = [chapterWith(1, 0), chapterWith(2, 0), chapterWith(3, 6)];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 1,
    );
    final soilSafeBottom =
        layout.trunkRect.bottom - layout.trunkRect.height * 0.12;
    final chapter3Sections = layout.sections
        .where((s) => s.id ~/ 100 == 3)
        .toList();

    expect(chapter3Sections.length, greaterThan(3), reason: '泥土附近仍应保留小节标签');
    for (final s in chapter3Sections) {
      if (s.root.dy > soilSafeBottom) {
        expect(s.showTendril, isFalse, reason: '${s.title} 太靠近泥土时不显示枝丫');
      }
    }
  });

  test('窗口模式：泥土附近隐藏枝丫时仍保留足够小节标签', () {
    final outline = [
      chapterWith(1, 0),
      chapterWith(2, 0),
      chapterWith(3, 0),
      chapterWith(4, 14),
    ];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 2,
    );

    final chapter4Sections = layout.sections.where((s) => s.id ~/ 100 == 4);
    expect(
      chapter4Sections.length,
      greaterThanOrEqualTo(5),
      reason: '靠近泥土只应隐藏枝丫，不能把小节标签也裁到只剩三枚',
    );
  });

  test('窗口模式：一屏严格只两章（整数档与滚动中的分数档都不露第三章）', () {
    final outline = [for (var i = 1; i <= 6; i++) chapterWith(i, 1)];
    // offset 0（首档）
    expect(layoutMagicTree(size: size, outline: outline).chapters.length, 2);
    // 整数档
    expect(
      layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: 2,
      ).chapters.length,
      2,
    );
    // 分数档（滚动中）——修复前这里会出现 3 章
    expect(
      layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: 2.4,
      ).chapters.length,
      2,
      reason: '滚动中也不能同时看到三章',
    );
    // 末档
    expect(
      layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: 4,
      ).chapters.length,
      2,
    );
  });

  test('窗口模式：小节铺满时带顶仍有落在本章的空白加节区（可双击加节）', () {
    // 底部对齐后加节区从"带底"移到"带顶"：最新一节钉在带底，最老的节向上排、
    // 溢出则滚出带顶，带顶恒留一条落在本章带内的空白供双击加节。
    // 章1有 20 节（远超一屏）；offset 0 → 显示章1、章2
    final outline = [chapterWith(1, 20), chapterWith(2, 1), chapterWith(3, 1)];
    final layout = layoutMagicTree(size: size, outline: outline);
    final band1 = layout.chapterBands[1]!;

    // 章1当前可见小节的最高枝根 y（最靠上的一节）
    final sec1Ys = layout.sections
        .where((s) => s.id ~/ 100 == 1)
        .map((s) => s.root.dy)
        .toList();
    var highest = band1.$2;
    for (final y in sec1Ys) {
      if (y < highest) highest = y;
    }

    // 带顶往下 20px 处：应落在本章带内、且在所有小节之上（= 空白加节区）
    final probeY = band1.$1 + 20;
    expect(layout.chapterForY(probeY), 1, reason: '带顶空白应落回本章（双击加节到本章）');
    expect(probeY, lessThan(highest), reason: '带顶应留出小节之上的空白加节区，不被小节铺满');
  });

  test('窗口模式：每小节最多按三条灵感预览预留高度', () {
    final outline = [chapterWith(1, 12), chapterWith(2, 0), chapterWith(3, 0)];
    final withoutNotes = layoutMagicTree(size: size, outline: outline);
    final withThreeNotes = layoutMagicTree(
      size: size,
      outline: outline,
      sectionNoteCounts: {100: 3},
    );
    final withManyNotes = layoutMagicTree(
      size: size,
      outline: outline,
      sectionNoteCounts: {100: 99},
    );

    expect(
      withThreeNotes.sectionScrollMax[1]! - withoutNotes.sectionScrollMax[1]!,
      closeTo(kNoteRowHeight * 3, 0.1),
      reason: '小节有 3 条灵感时，应为 3 条预览小卡预留高度',
    );
    expect(
      withManyNotes.sectionScrollMax[1],
      closeTo(withThreeNotes.sectionScrollMax[1]!, 0.1),
      reason: '超过 3 条仍只按 3 条预览计算，避免撑坏画面',
    );
  });

  test('窗口模式小节溢出可滚：滚动量把后面的节带进带内', () {
    final outline = [chapterWith(1, 12), chapterWith(2, 0), chapterWith(3, 0)];
    final layout = layoutMagicTree(size: size, outline: outline);
    final max = layout.sectionScrollMax[1]!;
    expect(max, greaterThan(0), reason: '12 节放不下半屏，必须可滚');

    Set<int> ids(MagicTreeLayout l) => l.sections.map((s) => s.id).toSet();
    final before = ids(layout);
    final after = ids(
      layoutMagicTree(size: size, outline: outline, sectionScrolls: {1: 0}),
    );
    // 默认自动滚到末尾：最新的第十二节可见，最老的第一节在顶上溢出带外
    expect(before, contains(100 + 11), reason: '默认最新节(第12节)在带底可见');
    expect(before, isNot(contains(100)), reason: '最老的第一节在带外');
    // 滚回起点（scroll=0）→ 从顶部露出最老的第一节，最新节此时滚到带下方
    expect(after, contains(100), reason: '滚回起点后最老的第一节露出');
    expect(after, isNot(contains(100 + 11)), reason: '此时最新节在带下方');
  });

  test('单章多小节：默认自动滚到最新小节，且节标签保持单列', () {
    final outline = [chapterWith(1, 20)];
    final layout = layoutMagicTree(size: size, outline: outline);

    expect(layout.sectionScrollMax[1], greaterThan(0), reason: '单章小节过多时也必须可滚');

    final visibleIds = layout.sections.map((s) => s.id).toSet();
    expect(visibleIds, contains(100 + 19), reason: '默认应显示最新的第二十节');
    expect(visibleIds, isNot(contains(100)), reason: '超过容量后第一节应先滚出屏幕');

    final labels = placeMagicLabels(
      layout,
      canvasWidth: size.width,
    ).where((l) => l.sectionId != null).toList();
    expect(labels, isNotEmpty);
    final lefts = labels.map((l) => l.rect.left).toList();
    final minLeft = lefts.reduce(math.min);
    final maxLeft = lefts.reduce(math.max);
    expect(maxLeft - minLeft, lessThan(12), reason: '单章小节标签应始终保持右侧一列');
  });

  test('两章时单章小节过多：本章小节仍保持单列并默认显示最新', () {
    final outline = [chapterWith(1, 20), chapterWith(2, 0)];
    final layout = layoutMagicTree(size: size, outline: outline);

    expect(
      layout.sectionScrollMax[1],
      greaterThan(0),
      reason: '两章整树可见时，单章小节过多也必须可滚',
    );

    final chapter1Visible = layout.sections
        .where((s) => s.id ~/ 100 == 1)
        .map((s) => s.id)
        .toSet();
    expect(chapter1Visible, contains(100 + 19), reason: '引子默认显示最新的第二十节');
    expect(chapter1Visible, isNot(contains(100)), reason: '引子第一节应先滚出可见区');

    final labels = placeMagicLabels(
      layout,
      canvasWidth: size.width,
    ).where((l) => l.sectionId != null && l.sectionId! ~/ 100 == 1).toList();
    expect(labels, isNotEmpty);
    final lefts = labels.map((l) => l.rect.left).toList();
    final minLeft = lefts.reduce(math.min);
    final maxLeft = lefts.reduce(math.max);
    expect(maxLeft - minLeft, lessThan(12), reason: '引子的小节标签应保持右侧一列');
  });

  test('窗口模式：小节标签要么完整显示，要么不显示', () {
    final outline = [chapterWith(1, 14), chapterWith(2, 0), chapterWith(3, 0)];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      sectionScrolls: {
        1:
            layoutMagicTree(size: size, outline: outline).sectionScrollMax[1]! /
            2,
      },
    );
    final labels = placeMagicLabels(layout, canvasWidth: size.width);

    for (final label in labels.where((l) => l.sectionId != null)) {
      final section = layout.sections.singleWhere(
        (s) => s.id == label.sectionId,
      );
      final band = layout.chapterBands[section.clipChapterId]!;
      expect(
        label.rect.top,
        greaterThanOrEqualTo(band.$1 + 2),
        reason: '${label.text} 不能被本章上边界裁成半截',
      );
      expect(
        label.rect.bottom,
        lessThanOrEqualTo(band.$2 - 2),
        reason: '${label.text} 不能被本章下边界裁成半截',
      );
    }
  });

  test('窗口模式：靠近右下输入按钮的小节不进入布局', () {
    final outline = [
      chapterWith(1, 0),
      chapterWith(2, 0),
      chapterWith(3, 0),
      chapterWith(4, 12),
    ];
    final layout = layoutMagicTree(
      size: size,
      outline: outline,
      chapterOffset: 2,
    );
    final labels = placeMagicLabels(layout, canvasWidth: size.width);

    for (final label in labels.where((l) => l.sectionId != null)) {
      expect(
        label.rect.bottom,
        lessThanOrEqualTo(size.height - 96),
        reason: '${label.text} 靠近右下速记按钮时应整条隐藏',
      );
    }
  });

  test('整树模式：小节枝丫压到泥土时隐藏枝丫', () {
    final outline = [chapterWith(1, 10)];
    final layout = layoutMagicTree(size: size, outline: outline);
    final soilSafeBottom =
        layout.trunkRect.bottom - layout.trunkRect.height * 0.12;

    for (final section in layout.sections) {
      if (section.spriteRect.bottom > soilSafeBottom) {
        expect(
          section.showTendril,
          isFalse,
          reason: '${section.title} 的枝丫不能压到泥土上',
        );
      }
    }
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
        expect(
          labels[a].rect.overlaps(labels[b].rect),
          isFalse,
          reason: '${labels[a].text} 与 ${labels[b].text} 不应重叠',
        );
      }
      expect(labels[a].rect.left, greaterThanOrEqualTo(0), reason: '不出左缘');
      expect(
        labels[a].rect.right,
        lessThanOrEqualTo(size.width),
        reason: '不出右缘',
      );
    }
  });

  test('跨档立刻换档位：不再冻结旧档（冻结会把旧照片抻到新高度）', () {
    // 早先加章时会冻结旧档播交叉溶解，但目标树高已经跳到新值，
    // 旧照片就被纵向抻长（0→1 章要抻 1.89 倍，嫩芽拉成细面条）。
    // 现在换档即刻生效，视觉过渡交给自下而上的擦除。
    final before = [for (var i = 1; i <= 7; i++) chapterWith(i, 0)];
    final after = [for (var i = 1; i <= 8; i++) chapterWith(i, 0)];

    expect(layoutMagicTree(size: size, outline: before).stage, 3);
    expect(layoutMagicTree(size: size, outline: after).stage, 4);
  });

  test('方案A五档成长：加章跨阈值时整树照片依次换大（章多树长大）', () {
    // 用户反馈"第二章到第九章树木一点变化都没有"的根治：档位随创作量铺开，
    // 前十来章要能看到多次成长跨档（每档一张不同大小的完整树照片）。
    int stageOf(int chapters) => layoutMagicTree(
      size: size,
      outline: [for (var i = 1; i <= chapters; i++) chapterWith(i, 0)],
    ).stage;
    expect(stageOf(0), 1, reason: '空树=破土嫩芽');
    expect(stageOf(2), 2);
    expect(stageOf(5), 3);
    expect(stageOf(9), 4);
    expect(stageOf(20), 5, reason: '海量创作=巨藤封顶');
    // 2→9 章至少跨 2 次档（不再一动不动）
    final tiers = {stageOf(2), stageOf(5), stageOf(9)};
    expect(tiers.length, greaterThanOrEqualTo(3), reason: '2/5/9 章应各不相同');
    // 五张完整树素材都存在
    for (var s = 1; s <= 5; s++) {
      expect(
        File('assets/textures/magic_tree_$s.jpg').existsSync(),
        isTrue,
        reason: 'magic_tree_$s.jpg 必须存在',
      );
    }
  });

  test('方案乙连续成长：档内每加一节树都长高，且跨档换图时树高不跳', () {
    // 用户 2026-07-28 反馈"生长不连续"的根治：树高不再只跟档位走，
    // 而是随节点数连续变化，一档内加节也看得见长高。
    double treeH(int nodes) => layoutMagicTree(
      size: size,
      outline: [chapterWith(1, math.max(0, nodes - 1))],
    ).visibleTreeHeight;

    // 第 2 档（1~3 节点）档内逐级长高
    expect(treeH(2), greaterThan(treeH(1)), reason: '1→2 节点必须长高');
    expect(treeH(3), greaterThan(treeH(2)), reason: '2→3 节点必须长高');
    // 跨档（3→4 节点，第2档→第3档）换的是照片，树的**实际高度**必须连续
    final before = layoutMagicTree(size: size, outline: [chapterWith(1, 2)]);
    final after = layoutMagicTree(size: size, outline: [chapterWith(1, 3)]);
    expect(after.stage, before.stage + 1, reason: '3→4 节点应跨档换图');
    expect(
      after.visibleTreeHeight,
      closeTo(before.visibleTreeHeight, 1.0),
      reason:
          '跨档瞬间两棵**整株**等高，换图动效才读作生长而不是换幻灯片。'
          '按茎干对齐是不够的：茎顶之上还有一大片枝叶，各档比例差得远',
    );
  });

  test('方案乙：泥土钉死不动，树只纵向长高（横向恒定，接缝零台阶）', () {
    // 用户红线"泥土就不要动"：土层矩形与树的成长完全无关。
    final small = layoutMagicTree(size: size, outline: [chapterWith(1, 0)]);
    final big = layoutMagicTree(size: size, outline: [chapterWith(1, 2)]);
    expect(big.soilRect, small.soilRect, reason: '土层矩形不得随成长变化');
    expect(big.soilLineY, closeTo(small.soilLineY, 0.001));
    expect(
      big.imageRect.height,
      greaterThan(small.imageRect.height),
      reason: '树层必须长高',
    );
    expect(
      big.imageRect.width,
      closeTo(small.imageRect.width, 0.001),
      reason: '横向恒定：等比放大会让树干在土壤线上宽下窄，露出台阶',
    );
    // 分界线恒落在两个矩形的同一比例处 → 树干跨线宽度连续
    expect(
      small.soilLineY,
      closeTo(big.imageRect.top + kSoilSplitFrac * big.imageRect.height, 0.001),
    );
  });

  test('每档照片都按各自比例作画，绝不被抻长或压扁', () {
    // 成长倍数 = 目标整株高 ÷ 本档素材自带的整株高。档内该倍数从 1 起步、
    // 有界上探；跨档瞬间回到贴合新素材的值——任何时候都不会出现压扁（<1）。
    for (var n = 0; n <= 30; n++) {
      final outline = n == 0 ? <OutlineChapter>[] : [chapterWith(1, n - 1)];
      final l = layoutMagicTree(size: size, outline: outline);
      final growth = l.imageRect.height / l.soilRect.height;
      expect(
        growth,
        greaterThanOrEqualTo(0.999),
        reason: '$n 节点：素材被压扁了（成长倍数 $growth < 1）',
      );
      expect(
        growth,
        lessThanOrEqualTo(1.29),
        reason: '$n 节点：素材被抻得太长（成长倍数 $growth）',
      );
    }
  });

  test('窗口模式止血：完整魔树图首尾镜头同尺寸，末章贴底', () {
    (Rect, Rect) imageFor(int count) {
      final outline = [for (var i = 1; i <= count; i++) chapterWith(i, 0)];
      final layout = layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: (count - 2).toDouble(),
      );
      final pieces = layoutMagicTreeImagePieces(layout) as WholeTreeImagePieces;
      return (pieces.bounds, pieces.soilBounds);
    }

    final (image3, soil3) = imageFor(3);
    for (final count in [4, 8, 11]) {
      final (image, soil) = imageFor(count);
      expect(soil, soil3, reason: '$count 章土层完全不动（贴底、同尺寸、同位置）');
      expect(
        soil.top + kSoilBottomFrac * soil.height,
        closeTo(size.height - 8, 0.5),
        reason: '$count 章土堆底应贴屏底',
      );
      expect(image.left, closeTo(image3.left, 0.5), reason: '$count 章横向不漂移');
      expect(image.width, closeTo(image3.width, 0.5), reason: '$count 章宽度不变');
    }
  });

  test('新增章节动作计划：新章在窗口外时先定位，再长枝', () {
    final plan = chapterGrowthMotionPlan(
      oldCount: 4,
      newCount: 5,
      currentOffset: 2,
    );

    expect(plan.targetOffset, 3);
    expect(plan.steps, [
      ChapterGrowthStep.panCamera,
      ChapterGrowthStep.growBranch,
    ]);
    expect(plan.panDelay, const Duration(milliseconds: 620));
  });
}
