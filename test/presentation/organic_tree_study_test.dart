import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_branch.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_projection.dart';

void main() {
  test('冠层末段自然收尖，真实挂点之前不削细或移动母枝', () {
    for (final count in [10.5, 10.8, 10.9, 11.0, 30.0]) {
      final frame = OrganicTreeFrame(1, chapterCount: count);
      for (var index = 10; index < count.ceil(); index++) {
        final branch = OrganicTreeFrame.canopyBranch(index);
        final limb = frame.limbs.singleWhere((limb) => identical(limb.spine, branch.spine));
        final original = OrganicBranchPainter.sampleStem(limb.spine, limb.growth,
            limb.radius, tipRatio: limb.tipRatio);
        for (var sample = 0; sample < limb.sections.length; sample++) {
          final section = limb.sections[sample];
          expect(section.center, original[sample].center);
          if (section.distance / branch.metric.length <= .8 + 1e-10) {
            expect(section.radius, closeTo(original[sample].radius, 1e-10));
          } else {
            expect(section.radius, lessThan(original[sample].radius));
          }
        }
        if (limb.growth == 1) {
          expect(limb.sections.last.radius, closeTo(0, 1e-10));
          final mother = frame.chapterAttachment(index)!;
          expect(mother.radius, OrganicBranchPainter.radiusAt(.8, 1, limb.radius, limb.tipRatio));
          expect(mother.wood.contains(mother.point), isTrue);
        }
      }
    }
  });
  test('冠层追加连续展叶，已出生叶节不搬动且叶柄留在木质内', () {
    var previous = <(Offset, double), double>{};
    for (var step = 0; step <= 100; step++) {
      final frame = OrganicTreeFrame(1, chapterCount: 10 + step * .2);
      final current = {
        for (final leaf in frame.leaves)
          if (frame.wood.contains(leaf.point))
            (leaf.point, leaf.angle): leaf.scale,
      };
      for (final entry in previous.entries) {
        expect(current[entry.key], greaterThanOrEqualTo(entry.value),
            reason: '冠层追加中已展开的叶片不能消失或反向缩小');
      }
      previous = current;
    }
    expect(previous.length, greaterThan(50));
  });
  test('只复用上一帧参数完全相同的枝干截面，成长变化不沿用旧几何', () {
    var previous = OrganicTreeFrame(.55, chapterCount: 15);
    var reused = 0;
    for (final state in [(1.0, 20.0), (1.0, 20.1), (1.0, 21.0), (.7, 12.0)]) {
      final frame = OrganicTreeFrame(state.$1, chapterCount: state.$2, previous: previous);
      final fresh = OrganicTreeFrame(state.$1, chapterCount: state.$2);
      final old = {for (final limb in previous.limbs) limb.spine: limb};
      expect(frame.limbs.length, fresh.limbs.length);
      for (var index = 0; index < frame.limbs.length; index++) {
        final limb = frame.limbs[index];
        expect(limb.sections, orderedEquals(fresh.limbs[index].sections));
        if (identical(limb.sections, old[limb.spine]?.sections)) reused++;
      }
      expect(frame.leaves, orderedEquals(fresh.leaves));
      previous = frame;
    }
    expect(reused, greaterThan(100), reason: '成熟后的固定细枝应避免反复求取切线');
  });
  test('快速批量增章时先连通基础主干，不生成悬空或负半径上干', () {
    for (final count in [10.000000001, 22.5, 47.5, 72.5]) {
      expect(OrganicTreeFrame(1, chapterCount: count).wood.getBounds().isFinite, isTrue);
    }
    for (var step = 0; step <= 50; step++) {
      final progress = step / 50;
      final count = 1 + 29 * progress;
      final frame = OrganicTreeFrame(.2 + .8 * progress, chapterCount: count);
      if (count > 10) expect(frame.anchorAt(1), isNotNull);
      for (final limb in frame.limbs) {
        expect(limb.sections.every((section) => section.radius >= 0), isTrue);
      }
    }
  });
  test('成熟后章节进入有限冠层，既有章锚点和叶节不搬动', () {
    final base = OrganicTreeFrame(1);
    final expanded = OrganicTreeFrame(1, chapterCount: 30);
    final middle = OrganicTreeFrame(1, chapterCount: 20);
    expect(expanded.wood.getBounds().top, greaterThanOrEqualTo(0));
    expect(middle.wood.getBounds().top, greaterThanOrEqualTo(0));
    expect(OrganicTreeFrame.upperExtentFor(1000), 0);
    expect(expanded.rootBounds.bottom, base.rootBounds.bottom);
    for (var index = 0; index < 10; index++) {
      expect(expanded.chapterAnchor(index, 30), base.chapterAnchor(index, 10));
    }
    final leaves = expanded.leaves.map((leaf) => (leaf.point, leaf.angle)).toSet();
    for (final leaf in base.leaves) {
      expect(leaves.contains((leaf.point, leaf.angle)), isTrue);
    }
    final next = OrganicTreeFrame(1, chapterCount: 30.01);
    expect((next.wood.getBounds().top - expanded.wood.getBounds().top).abs(), lessThan(2));
  });
  test('章枝连接真实树干，浏览及继续成长不移动已有锚点', () {
    final mature = OrganicTreeFrame(1);
    final matureCurves = mature.limbs.map((limb) => limb.spine).toSet();
    for (final limb in OrganicTreeFrame(.2).limbs) {
      expect(
        matureCurves.contains(limb.spine),
        isTrue,
        reason: '固定中心线应复用，不为每个树龄重建原生路径',
      );
    }
    expect(
      identical(
        OrganicTreeFrame(.2).limbs.first.sections,
        mature.limbs.first.sections,
      ),
      isFalse,
      reason: '只缓存固定曲线，生长截面必须逐帧生成',
    );
    for (var count = 1; count <= 10; count++) {
      final growing = OrganicTreeFrame(count / 10);
      for (var index = 0; index < count; index++) {
        final anchor = growing.chapterAnchor(index, count);
        expect(anchor, isNotNull, reason: '$count 个节点的第 $index 章');
        expect(growing.wood.contains(anchor!), isTrue,
            reason: '$count 个节点的第 $index 章锚点 $anchor 不应出现空洞');
        expect(anchor, mature.chapterAnchor(index, count));
      }
    }
    final young = OrganicTreeFrame(.1);
    expect(young.chapterAnchor(9, 10), isNull, reason: '不能把成熟树锚点用在幼树尚未长出的部分');
    for (final count in [30, 100, 1000]) {
      final expanded = OrganicTreeFrame(1, chapterCount: count.toDouble());
      expect(expanded.wood.getBounds().left, greaterThanOrEqualTo(OrganicTreeProjection.nativeBounds.left));
      expect(expanded.wood.getBounds().right, lessThanOrEqualTo(OrganicTreeProjection.nativeBounds.right));
      for (var index = 0; index < count; index++) {
        final anchor = expanded.chapterAnchor(index, count)!;
        expect(expanded.wood.contains(anchor), isTrue,
            reason: '$count 章的第 $index 个锚点 $anchor 不应出现空洞');
        expect(anchor.dy, inInclusiveRange(0, 1672));
        if (index >= 10) {
          final attachment = expanded.chapterAttachment(index)!;
          expect(attachment.wood.contains(anchor), isTrue);
          expect(attachment.radius, greaterThan(0));
          expect(anchor, OrganicTreeFrame.chapterPoint(index));
        }
      }
    }
  });
  test('冠层母子枝真实连接，新增只伸展新枝且挂点未长到时隐藏', () {
    final base = OrganicTreeFrame(1, chapterCount: 30);
    final next = OrganicTreeFrame(1, chapterCount: 31);
    for (var index = 10; index < 30; index++) {
      expect(base.chapterAttachment(index)!.point, next.chapterAttachment(index)!.point);
      expect(base.chapterAttachment(index)!.radius, next.chapterAttachment(index)!.radius);
      final branch = OrganicTreeFrame.canopyBranch(index);
      final start = branch.metric.getTangentForOffset(0)!.position;
      final parent = branch.parent == null
          ? OrganicTreeFrame.trunkPoint(.72)
          : OrganicTreeFrame.chapterPoint(branch.parent! + 10);
      expect(start, parent);
      expect(base.wood.contains(start), isTrue);
    }
    expect(OrganicTreeFrame(1, chapterCount: 30.79).chapterAttachment(30), isNull);
    final partial = OrganicTreeFrame(1, chapterCount: 30.9);
    expect(partial.chapterAttachment(30), isNotNull);
    final old = base.limbs.map((limb) => limb.spine).toSet();
    final growing = partial.limbs.where((limb) => !old.contains(limb.spine)).single;
    expect(growing.growth, closeTo(.9, 1e-10));
    expect((growing.sections.last.center - OrganicTreeFrame.canopyBranch(30).metric
        .getTangentForOffset(OrganicTreeFrame.canopyBranch(30).metric.length)!.position).distance,
        greaterThan(0));
  });
  test('主树由同一根部连续延伸，枝叶随树龄生成', () {
    final young = OrganicTreeFrame(.2);
    final middle = OrganicTreeFrame(.55);
    final mature = OrganicTreeFrame(1);
    for (final frame in [young, middle, mature]) {
      expect(frame.wood.contains(const Offset(490, 1410)), isTrue);
    }
    expect(
      young.wood.getBounds().top,
      greaterThan(middle.wood.getBounds().top),
    );
    expect(
      middle.wood.getBounds().top,
      greaterThan(mature.wood.getBounds().top),
    );
    expect(mature.leaves.length, greaterThan(middle.leaves.length));
    expect(
      OrganicTreeFrame(.551).wood.getBounds().top - middle.wood.getBounds().top,
      inInclusiveRange(-10, 0),
    );
  });

  test('十二条根颈的完整截面始终埋在主干内部，不露出平切台阶', () {
    final rootNeck = OrganicTreeFrame.trunkPoint(.08);
    for (var step = 0; step <= 100; step++) {
      final frame = OrganicTreeFrame(step / 100);
      final trunk = OrganicBranchPainter.sectionPath(frame.limbs.first.sections);
      final roots = frame.limbs.skip(1).where((limb) =>
          (limb.sections.first.center - rootNeck).distance < 25);
      expect(roots.length, 12);
      for (final root in roots) {
        final neck = root.sections.first;
        for (final point in [neck.center + neck.normal * neck.radius,
          neck.center - neck.normal * neck.radius]) {
          expect(trunk.contains(point), isTrue,
              reason: '树龄 $step 根颈截面 $point 不能越出母干');
        }
      }
    }
  });

  test('连续树龄的枝干交叠不会产生空洞或无效轮廓', () {
    for (var step = 0; step <= 100; step++) {
      final frame = OrganicTreeFrame(step / 100);
      final bounds = frame.wood.getBounds();
      expect(bounds.isFinite, isTrue, reason: '树龄 $step');
      expect(bounds.left, greaterThanOrEqualTo(OrganicTreeProjection.nativeBounds.left));
      expect(bounds.right, lessThanOrEqualTo(OrganicTreeProjection.nativeBounds.right));
      for (final limb in frame.limbs) {
        final metric = limb.spine.computeMetrics().first;
        final center = metric
            .getTangentForOffset(metric.length * limb.growth * .5)!
            .position;
        expect(frame.wood.contains(center), isTrue, reason: '树龄 $step 枝干交叠');
      }
    }
  });

  test('叶柄固定在已生长的枝条上，树龄增加不搬动已有叶节', () {
    final mature = OrganicTreeFrame(1);
    final anchors = mature.leaves
        .map((leaf) => (leaf.point, leaf.angle))
        .toSet();
    var previous = <(Offset, double), double>{};
    for (var step = 0; step <= 100; step++) {
      final age = step / 100;
      final frame = OrganicTreeFrame(age);
      expect(frame.leaves, isNotEmpty);
      final current = {
        for (final leaf in frame.leaves) (leaf.point, leaf.angle): leaf.scale,
      };
      for (final entry in previous.entries) {
        expect(current[entry.key], greaterThanOrEqualTo(entry.value),
            reason: '树龄 $age 已展开的叶片不能消失或反向缩小');
      }
      for (final leaf in frame.leaves) {
        expect(frame.wood.contains(leaf.point), isTrue, reason: '树龄 $age 叶柄悬空');
        expect(
          anchors.contains((leaf.point, leaf.angle)),
          isTrue,
          reason: '树龄 $age 已有叶节发生位移',
        );
      }
      previous = current;
    }
  });

  testWidgets('渲染主树连续形态美术样件', (tester) async {
    await tester.runAsync(() async {
      Future<ui.Image> load(String file) async {
        final codec = await ui.instantiateImageCodec(
          await File(file).readAsBytes(),
          targetWidth: 512,
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return image;
      }

      final bark = await load('assets/tree_scene/illustrated/bark_detail.png');
      final leaf = await load('assets/tree_scene/illustrated/leaf_detail.png');
      final size = OrganicTreeProjection.nativeSize;
      final width = size.width.toInt();
      final baseHeight = size.height.toInt();
      const writeFrames = bool.fromEnvironment('WRITE_TREE_STUDY_FRAMES');
      final ages = writeFrames
          ? List.generate(121, (index) => index / 120)
          : [0.0, .05, .2, .55, 1.0];
      for (var index = 0; index < ages.length; index++) {
        final age = ages[index];
        final recorder = ui.PictureRecorder();
        OrganicTreeStudyPainter(
          age,
          bark,
          leaf,
        ).paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, baseHeight);
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(raw!.getUint8(3), 0, reason: '全景画布角落必须透明，不能形成缩放色块');
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        for (final chapterCount in [null, 30.0]) {
          for (final area in [const Rect.fromLTWH(300, 900, 600, 650),
            const Rect.fromLTWH(0, 200, 1200, 700)]) {
            Future<Uint8List> clipped(bool cull) async {
              final clipRecorder = ui.PictureRecorder();
              final canvas = Canvas(clipRecorder)..clipRect(area);
              OrganicTreeStudyPainter(age, bark, leaf, chapterCount: chapterCount,
                visibleRect: cull ? area : null)
                  .paint(canvas, size);
              final clipPicture = clipRecorder.endRecording();
              final clipImage = await clipPicture.toImage(width, baseHeight);
              final data = await clipImage.toByteData(format: ui.ImageByteFormat.png);
              clipImage.dispose();
              clipPicture.dispose();
              return data!.buffer.asUint8List();
            }
            expect(await clipped(true), orderedEquals(await clipped(false)),
                reason: '视野外剔除不能改变可见区域的枝叶、边缘或根颈像素');
          }
        }
        final nextRecorder = ui.PictureRecorder();
        OrganicTreeStudyPainter(age == 1 ? .2 : 1, bark, leaf)
            .paint(Canvas(nextRecorder), size);
        nextRecorder.endRecording().dispose();
        final replay = await picture.toImage(width, baseHeight);
        final replayBytes = await replay.toByteData(format: ui.ImageByteFormat.png);
        expect(replayBytes!.buffer.asUint8List(),
            orderedEquals(bytes!.buffer.asUint8List()),
            reason: '后续树龄绘制不能覆写已经提交的画面');
        replay.dispose();
        if (const bool.fromEnvironment('WRITE_TREE_STUDY') || writeFrames) {
          final output = Directory(
            writeFrames
                ? 'build/qa/main-tree-study/frames'
                : 'build/qa/main-tree-study',
          )..createSync(recursive: true);
          final name = writeFrames
              ? 'frame_${index.toString().padLeft(3, '0')}'
              : 'age_${(age * 100).round()}';
          await File(
            '${output.path}/$name.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
        picture.dispose();
      }
      if (const bool.fromEnvironment('WRITE_TREE_STUDY')) {
        final height = (size.height + OrganicTreeFrame.upperExtentFor(30)).ceil();
        final recorder = ui.PictureRecorder();
        OrganicTreeStudyPainter(1, bark, leaf, chapterCount: 30)
            .paint(Canvas(recorder), Size(size.width, height.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/qa/main-tree-study/chapters_30.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
      bark.dispose();
      leaf.dispose();
    });
  });
}
