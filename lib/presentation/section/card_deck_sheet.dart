import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'card_editor_page.dart';
import 'inspiration_card.dart';
import 'section_page.dart' show sectionCardsProvider;

/// 弹出卡片包：全部卡片展开浏览（羊皮纸 Dock 式滑出），右侧手柄拖动重排序
Future<void> showCardDeckSheet(BuildContext context, int sectionId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSectionParchment,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _CardDeckSheet(sectionId: sectionId),
  );
}

class _CardDeckSheet extends ConsumerWidget {
  const _CardDeckSheet({required this.sectionId});

  final int sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(sectionCardsProvider(sectionId)).value ?? const [];

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: [
          // iOS 抓手
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0x333A2A18),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.rectangle_stack,
                  size: 18,
                  color: kInk,
                ),
                const SizedBox(width: 8),
                Text(
                  '卡片包 · ${cards.length} 张',
                  style: const TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
                const Spacer(),
                const Text(
                  '拖动右侧手柄可重排',
                  style: TextStyle(
                    fontFamily: 'LXGWWenKai',
                    color: Color(0x803A2A18),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // ReorderableListView：重排交给右侧手柄，卡片主体长按用于拖回魔毯。
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              itemCount: cards.length,
              // onReorderItem：新回调已自动修正 newIndex（不含自身占位）
              onReorderItem: (oldIndex, newIndex) async {
                final ids = cards.map((c) => c.id).toList();
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                await ref.read(inspirationRepositoryProvider).reorderCards(ids);
              },
              itemBuilder: (context, i) => _DeckTile(
                key: ValueKey(cards[i].id),
                card: cards[i],
                index: i,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片包中的缩略卡（羊皮纸暖调紧凑版）
class _DeckTile extends StatelessWidget {
  const _DeckTile({super.key, required this.card, required this.index});

  final Inspiration card;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('包内卡_${card.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: LongPressDraggable<Inspiration>(
        data: card,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: HapticFeedback.selectionClick,
        feedback: InspirationDragFeedback(content: card.content),
        childWhenDragging: Opacity(opacity: 0.28, child: _tile(context)),
        child: _tile(context),
      ),
    );
  }

  Widget _tile(BuildContext context) {
    return GestureDetector(
      // 点缩略卡 → 全文编辑器
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardEditorPage(inspiration: card)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: kCardCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardEdge),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                card.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 14,
                  height: 1.6,
                  color: kInk,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  CupertinoIcons.line_horizontal_3,
                  size: 18,
                  color: Color(0x803A2A18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
