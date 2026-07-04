import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../outline/magic_carpet.dart' show magicCarpetKey;
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
        // 右侧留白避让右上角全局魔毯球（92 球宽 + 12 边距），标题不钻到球下
        const SizedBox(width: 104),
      ],
    ),
  );

  /// 把一条魔毯灵感挂进本节：排在卡堆最前（成为当前展示卡），并收起魔毯
  Future<void> _acceptFromCarpet(Inspiration inspiration) async {
    await ref
        .read(inspirationRepositoryProvider)
        .assignToSection(inspiration.id, widget.sectionId);
    magicCarpetKey.currentState?.collapse();
  }

  @override
  Widget build(BuildContext context) {
    // 整个小节页 = 一个落点：从右上角魔毯拖一条灵感下来松手 → 挂进本节
    // （用户定稿：图1 灵感拖不进具体小节。原先落点只在大纲树上。）
    return Scaffold(
      backgroundColor: kSectionParchment,
      body: DragTarget<Inspiration>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _acceptFromCarpet(d.data),
        builder: (context, candidates, _) => Stack(
          children: [
            _body(context),
            // 拖拽悬停时：金色提示层，明示"松手放入本节"
            if (candidates.isNotEmpty)
              const Positioned.fill(child: _DropHint()),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      children: [
        SafeArea(bottom: false, child: _header(context)),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final cards =
                  ref.watch(sectionCardsProvider(widget.sectionId)).value ??
                  const [];
              if (cards.isEmpty) return const _EmptyDeck();

                // 主区只显示卡包第一张（当前展示卡）；其余卡藏在卡片包里，
                // 不在主区露卡边（用户定稿：主区只要一个框）
                final current = cards.first;
                return Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 120),
                        child: InspirationCard(
                          key: Key('主区卡_${current.id}'),
                          content: current.content,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CardEditorPage(inspiration: current),
                            ),
                          ),
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
      );
  }
}

/// 拖拽悬停提示层：金色虚框 + 中央胶囊提示"松手放入本节"
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x1FC9A050),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xCCC9A050), width: 2),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: kCardCream,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFC9A050)),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 14),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.tray_arrow_down, size: 20, color: kInk),
                SizedBox(width: 8),
                Text(
                  '松手，放入本节',
                  style: TextStyle(
                    fontFamily: 'LXGWWenKai',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
