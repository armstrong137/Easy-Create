import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'card_deck_sheet.dart';
import 'card_editor_page.dart';
import 'inspiration_card.dart';

/// 某小节的卡堆流（按 card_order 升序，最后一张=最新拖入）
final sectionCardsProvider = StreamProvider.family<List<Inspiration>, int>(
  (ref, sectionId) =>
      ref.watch(inspirationRepositoryProvider).watchSectionCards(sectionId),
);

/// 小节页｜苹果钱包叠层卡堆（2026-07-04 用户定稿 iOS 照片级改版）
///
/// - 羊皮纸暖调、iOS 极简头部（返回 + 可编辑标题，替代 Material AppBar）
/// - 主区 = 钱包式卡堆：最新一张卡在最前、完整可读；其余卡只在其上方
///   露出一条卡边（不露正文），像一叠护照卡
/// - 点最新卡 → 全文编辑器；点卡堆/卡片包 → 展开全部（可重排、开任意卡）
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
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );

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

  /// iOS 极简头部：返回箭头 + 居中可编辑标题
  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(CupertinoIcons.back, color: kInk, size: 26),
          ),
        ),
        Expanded(
          child: TextField(
            key: const Key('小节标题输入框'),
            controller: _title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'LXGWWenKai',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: kInk,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
            ),
            onSubmitted: (_) => _saveTitle(),
            onTapOutside: (_) {
              _saveTitle();
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        const SizedBox(width: 54), // 平衡返回箭头
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSectionParchment,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header(context)),
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final cards =
                    ref.watch(sectionCardsProvider(widget.sectionId)).value ??
                    const [];
                if (cards.isEmpty) return const _EmptyDeck();

                final latest = cards.last; // 最新拖入 = 卡堆最前
                final behind = cards.length - 1; // 身后卡数（只露卡边）
                return Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 120),
                        child: _WalletStack(
                          behind: behind,
                          front: InspirationCard(
                            key: Key('主区卡_${latest.id}'),
                            content: latest.content,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    CardEditorPage(inspiration: latest),
                              ),
                            ),
                          ),
                          onTapBehind: () =>
                              showCardDeckSheet(context, widget.sectionId),
                        ),
                      ),
                    ),
                    // 底部：卡片包入口（展开全部 + 重排）
                    Align(
                      alignment: const Alignment(0, 0.94),
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
          ),
        ],
      ),
    );
  }
}

/// 钱包式卡堆：身后卡只露一条卡边（叠在最前卡上方），最前卡完整可读
class _WalletStack extends StatelessWidget {
  const _WalletStack({
    required this.behind,
    required this.front,
    required this.onTapBehind,
  });

  /// 身后卡数量（最多露 3 条边，多了不再叠加视觉负担）
  final int behind;
  final Widget front;
  final VoidCallback onTapBehind;

  @override
  Widget build(BuildContext context) {
    final peeks = behind.clamp(0, 3);
    const peekH = 14.0; // 每条卡边露出的高度
    const peekInset = 12.0; // 每条卡边左右内缩，形成层叠错落
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 身后卡边：越靠后越窄、越淡（点它们展开卡片包）
        for (var i = peeks; i >= 1; i--)
          GestureDetector(
            onTap: onTapBehind,
            child: Container(
              height: peekH + peekH,
              margin: EdgeInsets.symmetric(horizontal: peekInset * i),
              transform: Matrix4.translationValues(0, peekH * i, 0),
              decoration: BoxDecoration(
                color: Color.lerp(kCardCream, kSectionParchment, i / 4)!,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border.all(color: kCardEdge),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
            ),
          ),
        front,
      ],
    );
  }
}

/// 空节邀请文案（羊皮纸风）
class _EmptyDeck extends StatelessWidget {
  const _EmptyDeck();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '还没有灵感卡\n去魔毯上拖一条过来，或随手速记',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'LXGWWenKai',
            color: Color(0x803A2A18),
            fontSize: 14,
            height: 1.9,
          ),
        ),
      ),
    );
  }
}

/// 卡片包入口按钮：羊皮纸胶囊 + 叠卡图标 + 张数
class _DeckButton extends StatelessWidget {
  const _DeckButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('卡片包按钮'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: kCardCream,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kCardEdge),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.rectangle_stack, size: 18, color: kInk),
            const SizedBox(width: 8),
            Text(
              '卡片包 $count',
              style: const TextStyle(
                fontFamily: 'LXGWWenKai',
                fontSize: 14,
                color: kInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
