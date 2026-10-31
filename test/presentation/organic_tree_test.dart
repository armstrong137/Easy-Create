import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_viewport.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_branch.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_study.dart';

void main() {
  Future<void> loadMaterials(WidgetTester tester) async {
    final loader = tester.widget<FutureBuilder<List<ui.Image>>>(
      find.descendant(
        of: find.byType(OrganicTree),
        matching: find.byType(FutureBuilder<List<ui.Image>>),
      ),
    );
    await tester.runAsync(() => loader.future!);
    await tester.pump();
  }

  OrganicTreeStudyPainter painter(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(OrganicTree),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is OrganicTreeStudyPainter,
                  ),
                ),
              )
              .painter!
          as OrganicTreeStudyPainter;

  testWidgets('真实材质只加载一次，树龄更新经过连续中间值', (tester) async {
    OrganicTreeFrame? overlayFrame;
    var foregroundPaints = 0;
    Future<void> show(double age) => tester.pumpWidget(
      MaterialApp(
        home: OrganicTree(
          age: age,
          foregroundBuilder: (context, frame, bark) {
            overlayFrame = frame;
            return CustomPaint(
              painter: _CountPainter(() => foregroundPaints++),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    await show(.2);
    await loadMaterials(tester);
    final initial = painter(tester);
    expect(initial.age, .2);
    final initialPaints = foregroundPaints;
    await show(.8);
    await tester.pump(const Duration(milliseconds: 700));
    final middle = painter(tester);
    expect(
      identical(middle.frame, overlayFrame),
      isTrue,
      reason: '枝牌必须使用正在绘制的同一几何帧，而非目标树龄',
    );
    expect(middle.age, greaterThan(.2));
    expect(middle.age, lessThan(.8));
    expect(overlayFrame!.age, middle.age,
        reason: '承托枝材质必须读取同帧真实树龄，不能提前变为目标树龄');
    expect(identical(middle.bark, initial.bark), isTrue);
    expect(identical(middle.leaf, initial.leaf), isTrue);
    expect(foregroundPaints, initialPaints, reason: '主树生长不能反复重画未变化的枝牌前景');
    await tester.pumpAndSettle();
    expect(painter(tester).age, .8);
  });

  testWidgets('历史与全景镜头变换保留材质、树龄和同一树体状态', (tester) async {
    Future<void> show(bool overview, double focusY, double age) =>
        tester.pumpWidget(
          MaterialApp(
            home: IllustratedTreeViewport(
              sceneWidth: 600,
              sceneHeight: 1500,
              focusY: focusY,
              overview: overview,
              child: OrganicTree(age: age),
            ),
          ),
        );
    await show(false, 900, .2);
    await loadMaterials(tester);
    final state = tester.state(find.byType(OrganicTree));
    final initial = painter(tester);
    await show(false, 900, .8);
    await tester.pump(const Duration(milliseconds: 350));
    for (final overview in [true, false]) {
      final before = painter(tester).age;
      await show(overview, 400, .8);
      expect(painter(tester).age, before);
      await tester.pump(const Duration(milliseconds: 200));
      expect(identical(tester.state(find.byType(OrganicTree)), state), isTrue);
      expect(identical(painter(tester).bark, initial.bark), isTrue);
      expect(painter(tester).age, greaterThan(before));
      expect(painter(tester).age, lessThan(.8));
    }
    await tester.pumpAndSettle();
    expect(painter(tester).age, .8);
    final settled = painter(tester).frame;
    await show(true, 400, .8);
    await tester.pump(const Duration(milliseconds: 200));
    expect(identical(painter(tester).frame, settled), isTrue,
        reason: '树龄和规模不变时，镜头只复用当前几何，不重新生成所有枝叶');
  });

  testWidgets('新枝首帧借用主树材质，卸载枝条不会释放主树图片', (tester) async {
    Future<void> show(bool branch) => tester.pumpWidget(
      MaterialApp(
        home: OrganicTree(
          age: .8,
          foregroundBuilder: (context, frame, bark) => branch
              ? Center(child: SizedBox(width: 220, height: 180,
                  child: OrganicBranch(progress: 1, right: false, bark: bark)))
              : const SizedBox.expand(),
        ),
      ),
    );
    await show(false);
    await loadMaterials(tester);
    final bark = painter(tester).bark;
    for (var i = 0; i < 2; i++) {
      await show(true);
      final branchPaint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(OrganicBranch), matching: find.byType(CustomPaint),
      )).painter! as OrganicBranchPainter;
      expect(identical(branchPaint.bark, bark), isTrue,
          reason: '新挂载的历史枝牌首帧就应有材质，不能等待重新解码');
      await show(false);
      expect(bark.debugDisposed, isFalse);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    expect(bark.debugDisposed, isTrue, reason: '最后由主树所有者释放');
  });

  testWidgets('成熟后新增章节仍有真实的主干生长中间帧', (tester) async {
    Future<void> show(int chapters) => tester.pumpWidget(MaterialApp(
      home: OrganicTree(age: 1, chapterCount: chapters),
    ));
    await show(10);
    await loadMaterials(tester);
    final initial = painter(tester);
    await show(30);
    await tester.pump(const Duration(milliseconds: 700));
    final middle = painter(tester);
    expect(middle.age, 1);
    expect(middle.frame.chapterCount, greaterThan(10));
    expect(middle.frame.chapterCount, lessThan(30));
    expect(identical(middle.bark, initial.bark), isTrue);
    expect(middle.frame.chapterAnchor(25, 30), isNull);
    Future<List<int>> pixels() async => (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.descendant(
        of: find.byType(OrganicTree), matching: find.byType(RepaintBoundary)).first);
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    final middlePixels = await pixels();
    await tester.pumpAndSettle();
    expect(painter(tester).frame.chapterCount, 30);
    expect(painter(tester).frame.chapterAnchor(29, 30), isNotNull);
    expect(await pixels(), isNot(orderedEquals(middlePixels)),
        reason: '树龄封顶后新增章节必须重绘真实树干，不能只更新前景和几何元数据');
  });

  testWidgets('材质解码期间退出后不会更新已卸载树体', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OrganicTree(age: .5)));
    final future = tester
        .widget<FutureBuilder<List<ui.Image>>>(
          find.byType(FutureBuilder<List<ui.Image>>),
        )
        .future!;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => future);
    expect(tester.takeException(), isNull);
  });
}

class _CountPainter extends CustomPainter {
  _CountPainter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawCircle(const Offset(10, 10), 3, Paint()..color = Colors.green);
  }

  @override
  bool shouldRepaint(_CountPainter oldDelegate) => false;
}
