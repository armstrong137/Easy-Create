import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'card_deck_sheet.dart';
import 'card_editor_page.dart';
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
          return Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: InspirationCard(
                    key: Key('主区卡_${latest.id}'),
                    content: latest.content,
                    // 点开单卡 → 全文编辑器（无字数上限）
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CardEditorPage(inspiration: latest),
                      ),
                    ),
                  ),
                ),
              ),
              // 底部中央：卡片包入口（点开 Dock 式展开全部卡片）
              Align(
                alignment: const Alignment(0, 0.96),
                child: _DeckButton(
                  count: cards.length,
                  onTap: () =>
                      showCardDeckSheet(context, widget.sectionId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 卡片包入口按钮：叠层卡片图标 + 张数
class _DeckButton extends StatelessWidget {
  const _DeckButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.black, width: 1.2),
      ),
      child: InkWell(
        key: const Key('卡片包按钮'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style_outlined, size: 18),
              const SizedBox(width: 6),
              Text('卡片包 $count',
                  style: const TextStyle(
                      fontFamily: 'LXGWWenKai', fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
