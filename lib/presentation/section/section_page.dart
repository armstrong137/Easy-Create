import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// 小节页（阶段四·3 雏形：顶部可编辑标题；卡堆与编辑器在阶段六实现）
class SectionPage extends ConsumerStatefulWidget {
  const SectionPage({
    super.key,
    required this.sectionId,
    required this.initialTitle,
  });

  final int sectionId;
  final String initialTitle;

  @override
  ConsumerState<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends ConsumerState<SectionPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// 标题失焦/提交时保存（空标题不保存）
  Future<void> _saveTitle() async {
    final text = _title.text.trim();
    if (text.isEmpty || text == widget.initialTitle) return;
    await ref
        .read(novelRepositoryProvider)
        .renameSection(widget.sectionId, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        // 顶部可编辑标题（定稿）
        title: TextField(
          key: const Key('小节标题输入框'),
          controller: _title,
          style: const TextStyle(fontFamily: 'LXGWWenKai', fontSize: 18),
          decoration: const InputDecoration(border: InputBorder.none),
          onSubmitted: (_) => _saveTitle(),
          onTapOutside: (_) => _saveTitle(),
        ),
      ),
      body: const Center(
        child: Text(
          '灵感卡堆（阶段六实现）',
          style: TextStyle(color: Colors.black38),
        ),
      ),
    );
  }
}
