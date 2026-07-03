import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chinese_numbers.dart';
import '../../data/providers.dart';
import '../../domain/entities/outline_chapter.dart';
import '../section/section_page.dart';
import 'glass_plus_button.dart';
import 'label_layout.dart';
import 'pencil_tree_painter.dart';
import 'tree_model.dart';

/// 某小说的大纲流（章+节），铅笔树数据源
final outlineProvider =
    StreamProvider.family<List<OutlineChapter>, int>(
  (ref, novelId) => ref.watch(novelRepositoryProvider).watchOutline(novelId),
);

/// 大纲页｜黑白铅笔树 + 玻璃＋号 + 枝丫文字交互
///
/// 交互（定稿）：长按枝端文字 → 重命名/删除；双击 → 进入编辑
/// （章=弹重命名对话框；节=进小节页，顶部可改标题）
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

  /// 重命名对话框（章/节共用），确认后写库
  Future<void> _rename(PlacedLabel label) async {
    final controller = TextEditingController(text: label.text);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label.chapterId != null ? '重命名这一章' : '重命名这一节'),
        content: TextField(
          key: const Key('重命名输入框'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('重命名确认按钮'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == label.text) return;
    final repo = ref.read(novelRepositoryProvider);
    if (label.chapterId != null) {
      await repo.renameChapter(label.chapterId!, title);
    } else {
      await repo.renameSection(label.sectionId!, title);
    }
  }

  /// 删除（带确认；删章级联删节、灵感放回魔毯——数据层保证）
  Future<void> _delete(PlacedLabel label) async {
    final isChapter = label.chapterId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${label.text}」？'),
        content: Text(isChapter
            ? '这一章和它的所有小节都会被剪掉；挂在上面的灵感会放回魔毯。'
            : '这一节会被剪掉；挂在上面的灵感会放回魔毯。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('删除确认按钮'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('剪掉'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(novelRepositoryProvider);
    if (isChapter) {
      await repo.deleteChapter(label.chapterId!);
    } else {
      await repo.deleteSection(label.sectionId!);
    }
  }

  /// 长按：弹出 编辑/删除 选项
  Future<void> _showBranchMenu(PlacedLabel label) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('菜单重命名'),
              leading: const Icon(Icons.edit_outlined),
              title: Text('重命名「${label.text}」'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              key: const Key('菜单删除'),
              leading: const Icon(Icons.content_cut),
              title: const Text('剪掉这根枝丫'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(label);
    if (action == 'delete') await _delete(label);
  }

  /// 双击：章 → 重命名；节 → 进小节页（可改标题，卡堆阶段六）
  Future<void> _onDoubleTap(PlacedLabel label) async {
    if (label.sectionId != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SectionPage(
          sectionId: label.sectionId!,
          initialTitle: label.text,
        ),
      ));
    } else {
      await _rename(label);
    }
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final tree = layoutTree(size: size, outline: outline);
          // 布局/绘制/交互热区共享同一份标签几何
          final labels = placeLabels(tree);

          return Stack(
            children: [
              // 铅笔树
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _grow,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: PencilTreePainter(
                      tree: tree,
                      labels: labels,
                      growingChapterId: _growingChapterId,
                      growingSectionId: _growingSectionId,
                      growProgress: Curves.easeOut.transform(_grow.value),
                    ),
                  ),
                ),
              ),
              // 枝端文字的透明交互热区（外扩 8px 便于手指命中）
              for (final label in labels)
                Positioned.fromRect(
                  rect: label.rect.inflate(8),
                  child: GestureDetector(
                    key: Key(label.chapterId != null
                        ? '章热区_${label.chapterId}'
                        : '节热区_${label.sectionId}'),
                    behavior: HitTestBehavior.translucent,
                    onLongPress: () => _showBranchMenu(label),
                    onDoubleTap: () => _onDoubleTap(label),
                  ),
                ),
              // 左＋：长章（偏上放置，避开中部枝端标题）
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
          );
        },
      ),
    );
  }
}
