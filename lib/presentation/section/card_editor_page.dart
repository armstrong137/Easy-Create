import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';

/// 全文编辑器：点开单卡查看/编辑全文，无字数上限（可写完整小说）
///
/// 长文本策略：单 TextField maxLines:null + 外层滚动即可支撑数万字
/// （Flutter 文本编辑为惰性绘制，仅渲染可视行；实测流畅性在阶段七压测）。
/// 保存：返回/失焦时自动保存（写作类 App 惯例，不设显式保存按钮）。
class CardEditorPage extends ConsumerStatefulWidget {
  const CardEditorPage({super.key, required this.inspiration});

  final Inspiration inspiration;

  @override
  ConsumerState<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends ConsumerState<CardEditorPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.inspiration.content,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 内容有变更才写库（保留 created_at 与魔毯排序不受影响）
  Future<void> _save() async {
    final text = _controller.text;
    if (text == widget.inspiration.content || text.trim().isEmpty) return;
    await ref
        .read(inspirationRepositoryProvider)
        .updateContent(widget.inspiration.id, text);
  }

  /// 从小节删卡：灵感放回魔毯（生命周期规则三，非真删）
  Future<void> _removeFromSection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('把这张卡放回魔毯？'),
        content: const Text('卡片会从这一节消失，灵感本身回到魔毯（按创建时间归位），不会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('放回魔毯确认按钮'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放回魔毯'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(inspirationRepositoryProvider)
        .removeFromSection(widget.inspiration.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 返回时自动保存
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          title: const Text(
            '灵感全文',
            style: TextStyle(fontFamily: 'LXGWWenKai', fontSize: 17),
          ),
          actions: [
            IconButton(
              key: const Key('放回魔毯按钮'),
              tooltip: '从这一节删卡（放回魔毯）',
              icon: const Icon(Icons.eject_outlined),
              onPressed: _removeFromSection,
            ),
          ],
        ),
        body: TextField(
          key: const Key('全文编辑框'),
          controller: _controller,
          maxLines: null, // 无上限
          expands: true,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 16,
            height: 1.8,
            color: Colors.black87,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(20),
            hintText: '在这里尽情写，没有字数上限…',
          ),
        ),
      ),
    );
  }
}
