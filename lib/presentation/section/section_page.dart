import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'inspiration_card.dart';

/// 某小节的卡堆流（按 card_order 升序，最后一张=最新拖入）
final sectionCardsProvider =
    StreamProvider.family<List<Inspiration>, int>(
  (ref, sectionId) =>
      ref.watch(inspirationRepositoryProvider).watchSectionCards(sectionId),
);

/// 小节页｜信用卡卡堆（阶段六·1：标题 + 主区最新一张灵感卡）
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
      body: Consumer(
        builder: (context, ref, _) {
          final cards =
              ref.watch(sectionCardsProvider(widget.sectionId)).value ??
                  const [];
          if (cards.isEmpty) {
            return const Center(
              child: Text(
                '还没有灵感卡\n去魔毯上拖一条过来，或随手速记',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38, height: 1.8),
              ),
            );
          }
          // 主区默认只显示最新一张（卡堆顺序最后 = 最新拖入，假设待终审）
          final latest = cards.last;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: InspirationCard(
                key: Key('主区卡_${latest.id}'),
                content: latest.content,
                // TODO(阶段六·4)：点开单卡进入全文编辑器
                onTap: () {},
              ),
            ),
          );
          // TODO(阶段六·2)：底部卡片包 Dock 式展开全部卡片
        },
      ),
    );
  }
}
