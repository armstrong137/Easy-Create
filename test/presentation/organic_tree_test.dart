import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_viewport.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree.dart';
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
    Future<void> show(double age) =>
        tester.pumpWidget(MaterialApp(home: OrganicTree(age: age)));
    await show(.2);
    await loadMaterials(tester);
    final initial = painter(tester);
    expect(initial.age, .2);
    await show(.8);
    await tester.pump(const Duration(milliseconds: 700));
    final middle = painter(tester);
    expect(middle.age, greaterThan(.2));
    expect(middle.age, lessThan(.8));
    expect(identical(middle.bark, initial.bark), isTrue);
    expect(identical(middle.leaf, initial.leaf), isTrue);
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
