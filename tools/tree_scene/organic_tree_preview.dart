import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_viewport.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree.dart';
import 'package:novel_app/presentation/outline/tree_scene/organic_tree_projection.dart';
import 'package:novel_app/presentation/outline/tree_scene/illustrated_tree_scene.dart';

// 独立验收入口，不替换正式应用，也不读取小说数据库。
void main() => runApp(const MaterialApp(home: _Preview()));

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  double _age = .2;
  bool _overview = true;
  String _lastHit = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = math.max(
                constraints.maxHeight * 1.6,
                constraints.maxWidth * 1672 / 941,
              );
              return IllustratedTreeViewport(
                sceneHeight: height,
                sceneWidth: height * 941 / 1672,
                focusY: height * .63,
                chapterScale: 3.5,
                overview: _overview,
                child: OrganicTree(
                  age: _age,
                  foregroundBuilder: (context, frame) {
                    final projection = OrganicTreeProjection(
                      Size(height * 941 / 1672, height),
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final (index, right, title) in const [
                          (0, false, '左枝牌'),
                          (5, true, '右枝牌'),
                        ])
                          if (frame.chapterAnchor(index, 10) != null)
                            Positioned.fromRect(
                              key: ValueKey(title),
                              rect: projection.branchRect(
                                frame.chapterAnchor(index, 10)!,
                                const Size(300, 200),
                                right: right,
                              ),
                              child: Semantics(
                                label: title,
                                button: true,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _lastHit = title),
                                  child: ExcludeSemantics(
                                    child: IllustratedBranchPlaque(
                                      barkAge: frame.age,
                                      title: title,
                                      side: right
                                          ? IllustratedBranchSide.right
                                          : IllustratedBranchSide.left,
                                      selected: _lastHit == title,
                                      animateIn: false,
                                      organicGrowth: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('命中：$_lastHit'),
              TextButton(
                onPressed: () => setState(() => _age = .2),
                child: const Text('幼树'),
              ),
              TextButton(
                onPressed: () => setState(() => _age = 1),
                child: const Text('成熟'),
              ),
              TextButton(
                onPressed: () => setState(() => _overview = !_overview),
                child: Text(_overview ? '近景' : '全景'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
