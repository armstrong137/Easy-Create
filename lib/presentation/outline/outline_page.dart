import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import 'pencil_tree_painter.dart';
import 'tree_model.dart';

/// 某小说的大纲流（章+节），铅笔树数据源
final outlineProvider =
    StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

/// 大纲页｜黑白铅笔树（阶段四·1：静态树；＋号与交互在后续步骤）
class OutlinePage extends ConsumerWidget {
  const OutlinePage({super.key, required this.novelId, required this.title});

  final int novelId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outline = ref.watch(outlineProvider(novelId)).value ?? const [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(fontFamily: 'LXGWWenKai', fontSize: 18)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return CustomPaint(
            size: size,
            painter: PencilTreePainter(
              tree: layoutTree(size: size, outline: outline),
            ),
          );
        },
      ),
    );
  }
}
