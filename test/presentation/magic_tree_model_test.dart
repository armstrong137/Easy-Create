import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
      bottom.imageRect,
      top.imageRect,
      reason: '画幅与镜头档位无关：帧序列自己表达生长，代码不缩放不平移',
    );
    expect(bottom.chapterBands.keys, contains(4));
    expect(bottom.chapterBands.keys, contains(5));
    expect(bottom.chapterBands.keys, isNot(contains(1)));
  });

  test('帧号映射：每加一个节点都前进，单调不退，到末帧封顶', () {
    // 候选素材 28 帧全部可用，一节点一帧。
    int frameOf(int nodes) => layoutMagicTree(
      size: size,
      outline: nodes == 0 ? const [] : [chapterWith(1, nodes - 1)],
    ).frame;
    expect(frameOf(0), kTreeFrameFirst, reason: '空书用首帧');
    final span = kTreeFrameLast - kTreeFrameFirst;
    for (var n = 1; n <= span; n++) {
      expect(
        frameOf(n),
        frameOf(n - 1) + 1,
        reason: '第 $n 个节点必须正好前进一帧——每一步都要看得见在长',
      );
    }
    expect(frameOf(span), kTreeFrameLast, reason: '$span 个节点长到末帧');
    expect(frameOf(200), kTreeFrameLast, reason: '超出后封顶，不越界');
  });

  test('画幅对所有帧完全相同；树在屏上逐节点长高', () {
    // 这套素材土堆与内容宽度逐帧恒定、生长完全由序列表达，
    // 所以画幅是死的（整帧照原样画），屏上变高的是植株本身。
    MagicTreeLayout at(int nodes) => layoutMagicTree(
      size: size,
      outline: nodes == 0 ? const [] : [chapterWith(1, nodes - 1)],
    );
    final base = at(0).imageRect;
    for (final n in [1, 3, 8, 15, 20, 40]) {
      expect(at(n).imageRect, base, reason: '$n 节点的画幅必须与首帧一致');
    }
    // 树高在序列后段会到顶（素材靠加密枝叶而非继续拔高表达成长），
    // 所以硬要求是"全程不降"，另加"前段必须实打实地变高"。
    double onScreen(int n) => at(n).soilCrestY - at(n).plantTopY;
    for (var n = 1; n <= kTreeFrameLast - kTreeFrameFirst; n++) {
      expect(
        onScreen(n),
        greaterThanOrEqualTo(onScreen(n - 1) - 0.001),
        reason: '第 $n 个节点树在屏上不得变矮',
      );
    }
    expect(
      onScreen(10),
      greaterThan(onScreen(0) * 1.2),
      reason: '前十个节点必须看得出明显长高',
    );
    for (var n = 0; n <= 40; n++) {
      final l = at(n);
      expect(l.plantTopY, greaterThanOrEqualTo(0), reason: '$n 节点：树冠出画布了');
      expect(
        l.imageRect.top + kFrameContentBottom * l.imageRect.height,
        lessThanOrEqualTo(size.height + 0.5),
        reason: '$n 节点：土堆底出画布了',
      );
    }
  });

  test('每一帧都有茎干轮廓，且素材文件都在（否则运行时直接崩）', () {
    for (var f = kTreeFrameFirst; f <= kTreeFrameLast; f++) {
      final l = layoutMagicTree(
        size: size,
        outline: [chapterWith(1, f - kTreeFrameFirst)],
      );
      expect(l.trunkRect.height, greaterThan(0), reason: '第 $f 帧缺茎干轮廓');
      expect(
        treeFrameAsset(f),
        allOf(contains('tree_frames_v3/'), endsWith('.png')),
        reason: '魔树帧必须用 PNG，避免 JPG 米白底压缩噪点形成矩形边',
      );
      expect(
        File(treeFrameAsset(f)).existsSync(),
        isTrue,
        reason: '${treeFrameAsset(f)} 必须存在',
      );
    }
  });

  test('魔树 PNG 帧必须是真透明背景，不能残留矩形底片', () {
    for (var f = kTreeFrameFirst; f <= kTreeFrameLast; f++) {
      final file = File(treeFrameAsset(f));
      expect(file.existsSync(), isTrue, reason: '第 $f 帧素材必须存在');
      final image = img.decodePng(file.readAsBytesSync());
      expect(image, isNotNull, reason: '第 $f 帧必须是可解码 PNG');

      var opaqueBorderPixels = 0;
      const border = 6;
      for (var y = 0; y < image!.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final inBorder =
              x < border ||
              y < border ||
              x >= image.width - border ||
              y >= image.height - border;
          if (inBorder && image.getPixel(x, y).a > 8) {
            opaqueBorderPixels++;
          }
        }
      }
      expect(
        opaqueBorderPixels,
        0,
        reason: '第 $f 帧外框必须全透明，否则贴到星空上会出现矩形分割感',
      );

      final corners = [
        image.getPixel(0, 0),
        image.getPixel(image.width - 1, 0),
        image.getPixel(0, image.height - 1),
        image.getPixel(image.width - 1, image.height - 1),
      ];
      expect(
        corners.every((p) => p.a <= 8),
        isTrue,
        reason: '第 $f 帧四角不能残留旧米白背景或抠图底片',
      );
    }
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
        topLayout.plantTopY,
        greaterThanOrEqualTo(0),
        reason: '$count 章：树冠留在画内',
      );
      expect(bottom, top, reason: '$count 章：画幅只由帧号决定，与镜头档位无关');
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
        startsWith('$kTreeFrameDir/magic_tree_f'),
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
    // 用"写了不少"的书：节点多 → 帧号靠后 → 树干长，章带才放得下多条小节。
    // （帧序列在节点少时树干很短，这是设定而非缺陷——书小树就小。）
    final outline = [chapterWith(1, 6), chapterWith(2, 6), chapterWith(3, 6)];
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
    // 阈值随帧序列素材下调：章带跟着树干走，18 个节点时树干 0.594 画幅，
    // 一屏两章 → 每带约 224px，放得下 4 行。原来的 5 是按旧五档素材（树干几乎
    // 满幅）定的。守住"不得被裁到只剩三枚"这条本意即可。
    expect(
      chapter4Sections.length,
      greaterThanOrEqualTo(4),
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

  test('窗口模式止血：画幅与章数、镜头档位都无关', () {
    // 画幅由帧号（=节点数）决定，同一本书在不同镜头档位下必须完全一致
    for (final count in [3, 4, 8, 11]) {
      final outline = [for (var i = 1; i <= count; i++) chapterWith(i, 0)];
      final a = layoutMagicTree(size: size, outline: outline).imageRect;
      final b = layoutMagicTree(
        size: size,
        outline: outline,
        chapterOffset: (count - 2).toDouble(),
      ).imageRect;
      expect(b, a, reason: '$count 章：滚镜头不得改变画幅');
      final pieces =
          layoutMagicTreeImagePieces(
                layoutMagicTree(size: size, outline: outline),
              )
              as WholeTreeImagePieces;
      expect(pieces.asset, startsWith(kTreeFrameDir));
    }
  });

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
}
