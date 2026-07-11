import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inspiration_font.dart';
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

class _CardDeckSheet extends ConsumerStatefulWidget {
  const _CardDeckSheet({required this.sectionId});

  final int sectionId;

  @override
  ConsumerState<_CardDeckSheet> createState() => _CardDeckSheetState();
}

class _CardDeckSheetState extends ConsumerState<_CardDeckSheet> {
  /// 重排后的乐观顺序：数据库流回填前先按用户拖完的样子显示，
  /// 避免松手瞬间闪回旧序再跳新序（用户反馈"不连贯"）
  List<Inspiration>? _optimistic;

  @override
  Widget build(BuildContext context) {
    // 数据库流一有新值（重排落库后的回填）就丢掉乐观顺序
    ref.listen(sectionCardsProvider(widget.sectionId), (_, _) {
      if (_optimistic != null) setState(() => _optimistic = null);
    });
    final cards =
        _optimistic ??
        ref.watch(sectionCardsProvider(widget.sectionId)).value ??
        const [];

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
              // onReorderItem：新回调已自动修正 newIndex（不含自身占位）。
              // 先乐观更新本地顺序（拖完什么样就是什么样），再落库
              onReorderItem: (oldIndex, newIndex) {
                final list = [...cards];
                list.insert(newIndex, list.removeAt(oldIndex));
                setState(() => _optimistic = list);
                ref
                    .read(inspirationRepositoryProvider)
                    .reorderCards(list.map((c) => c.id).toList());
              },
              itemBuilder: (context, i) => _DeckTile(
                key: ValueKey(cards[i].id),
                card: cards[i],
                index: i,
                onReturnToCarpet: () async {
                  HapticFeedback.mediumImpact();
                  await ref
                      .read(inspirationRepositoryProvider)
                      .removeFromSection(cards[i].id);
                },
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
  const _DeckTile({
    super.key,
    required this.card,
    required this.index,
    required this.onReturnToCarpet,
  });

  final Inspiration card;
  final int index;
  final VoidCallback onReturnToCarpet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('包内卡_${card.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: LongPressDraggable<Inspiration>(
        data: card,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onReturnToCarpet,
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
                style: TextStyle(
                  fontFamily:
                      inspirationFontFamily(card.content) ?? 'LXGWWenKai',
                  fontStyle: inspirationIsBrand(card.content)
                      ? FontStyle.italic
                      : FontStyle.normal,
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
