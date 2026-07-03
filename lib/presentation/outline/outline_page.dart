import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chinese_numbers.dart';
import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import 'glass_plus_button.dart';
import 'pencil_tree_painter.dart';
import 'tree_model.dart';

/// 某小说的大纲流（章+节），铅笔树数据源
final outlineProvider =
    StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

/// 大纲页｜黑白铅笔树 + 玻璃＋号（左＋长章 / 右＋长节，含生长动画）
class OutlinePage extends ConsumerStatefulWidget {
  const OutlinePage({super.key, required this.novelId, required this.title});

  final int novelId;
  final String title;

  @override
  ConsumerState<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends ConsumerState<OutlinePage>
    with SingleTickerProviderStateMixin {
  /// 枝丫生长动画（新建章/节时从根到端画出）
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// 正在生长的枝（章/节 id，动画结束后清空）
  int? _growingChapterId;
  int? _growingSectionId;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  /// 播放一根新枝的生长动画
  Future<void> _playGrow({int? chapterId, int? sectionId}) async {
    setState(() {
      _growingChapterId = chapterId;
      _growingSectionId = sectionId;
    });
    await _grow.forward(from: 0);
    if (mounted) {
      setState(() {
        _growingChapterId = null;
        _growingSectionId = null;
      });
    }
  }

  /// 左＋：长出章级枝丫（自动命名：引子 → 第一章 → …）
  Future<void> _addChapter(List<OutlineChapter> outline) async {
    final chapter = await ref.read(novelRepositoryProvider).createChapter(
          novelId: widget.novelId,
          title: defaultChapterTitle(outline.length),
        );
    await _playGrow(chapterId: chapter.id);
  }

  /// 右＋：给最新一章长出节级枝丫（假设待终审：节挂在最后一章）
  Future<void> _addSection(List<OutlineChapter> outline) async {
    if (outline.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先点左边的＋，长出第一根章枝吧')),
      );
      return;
    }
    final last = outline.last;
    final section = await ref.read(novelRepositoryProvider).createSection(
          chapterId: last.chapter.id,
          title: defaultSectionTitle(last.sections.length),
        );
    await _playGrow(sectionId: section.id);
  }

  @override
  Widget build(BuildContext context) {
    final outline =
        ref.watch(outlineProvider(widget.novelId)).value ?? const [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.title,
            style: const TextStyle(fontFamily: 'LXGWWenKai', fontSize: 18)),
      ),
      body: Stack(
        children: [
          // 铅笔树
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return AnimatedBuilder(
                  animation: _grow,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: PencilTreePainter(
                      tree: layoutTree(size: size, outline: outline),
                      growingChapterId: _growingChapterId,
                      growingSectionId: _growingSectionId,
                      growProgress: Curves.easeOut.transform(_grow.value),
                    ),
                  ),
                );
              },
            ),
          ),
          // 左＋：长章（偏上放置，避开中部枝端标题；玻璃可透底兜底）
          Align(
            alignment: const Alignment(-0.92, -0.55),
            child: GlassPlusButton(
              key: const Key('长章按钮'),
              semanticLabel: '添加新章',
              onTap: () => _addChapter(outline),
            ),
          ),
          // 右＋：长节
          Align(
            alignment: const Alignment(0.92, -0.55),
            child: GlassPlusButton(
              key: const Key('长节按钮'),
              semanticLabel: '添加新节',
              onTap: () => _addSection(outline),
            ),
          ),
        ],
      ),
    );
  }
}
