import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'card_editor_page.dart';
import 'section_page.dart' show sectionCardsProvider;

/// 弹出卡片包：全部卡片展开浏览（Dock 式滑出），长按拖动重排序
Future<void> showCardDeckSheet(BuildContext context, int sectionId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                const Icon(Icons.style_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  '卡片包 · ${cards.length} 张',
                  style: const TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                const Text(
                  '长按拖动可重排',
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            // ReorderableListView：长按拖动重排（移动端默认长按触发）
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: cards.length,
              // onReorderItem：新回调已自动修正 newIndex（不含自身占位）
              onReorderItem: (oldIndex, newIndex) async {
                final ids = cards.map((c) => c.id).toList();
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                await ref.read(inspirationRepositoryProvider).reorderCards(ids);
              },
              itemBuilder: (context, i) =>
                  _DeckTile(key: ValueKey(cards[i].id), card: cards[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片包中的缩略卡（白卡黑细框风格的紧凑版）
class _DeckTile extends StatelessWidget {
  const _DeckTile({super.key, required this.card});

  final Inspiration card;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('包内卡_${card.id}'),
      // 点缩略卡 → 全文编辑器
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CardEditorPage(inspiration: card)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.black, width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(2, 2)),
          ],
        ),
        child: Text(
          card.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 13,
            height: 1.5,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
