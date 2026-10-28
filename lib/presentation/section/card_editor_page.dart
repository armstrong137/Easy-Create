import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'inspiration_card.dart' show kSectionParchment, kInk;

/// 全文编辑器：点开单卡查看/编辑全文，无字数上限（可写完整小说）
///
/// 长文本策略：单 TextField maxLines:null + expands 即可支撑数万字
/// （Flutter 文本编辑惰性绘制，仅渲染可视行）。
/// 保存：返回/失焦时自动保存（写作类 App 惯例，不设显式保存按钮）。
/// 视觉（2026-07-04）：羊皮纸暖调 + iOS 极简头部（替代 Material AppBar）。
class CardEditorPage extends ConsumerStatefulWidget {
  const CardEditorPage({super.key, required this.inspiration});

  final Inspiration inspiration;

  @override
  ConsumerState<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends ConsumerState<CardEditorPage> {
  final _editorFocus = FocusNode();
  late String _savedContent = widget.inspiration.content;
  late final TextEditingController _controller = TextEditingController(
    text: widget.inspiration.content,
  );

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(_saveOnFocusLoss);
  }

  void _saveOnFocusLoss() {
    if (!_editorFocus.hasFocus) _save();
  }

  @override
  void dispose() {
    _editorFocus.removeListener(_saveOnFocusLoss);
    _editorFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 内容有变更才写库（保留 created_at 与魔毯排序不受影响）
  Future<void> _save() async {
    final text = _controller.text;
    if (text == _savedContent || text.trim().isEmpty) return;
    await ref
        .read(inspirationRepositoryProvider)
        .updateContent(widget.inspiration.id, text);
    _savedContent = text;
  }

  /// 从小节删卡：灵感放回魔毯（生命周期规则三，非真删）
  Future<void> _removeFromSection() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('把这张卡放回灵感卷轴？', style: _s(weight: FontWeight.w600)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('卡片会从这一节消失，灵感本身回到灵感卷轴（按创建时间归位），不会丢失。', style: _s(size: 13)),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: _s()),
          ),
          CupertinoDialogAction(
            key: const Key('放回魔毯确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '放回卷轴',
              style: _s(color: CupertinoColors.destructiveRed),
            ),
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

  TextStyle _s({double size = 17, FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: 'LXGWWenKai',
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    // 返回时自动保存
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: kSectionParchment,
        body: Column(
          children: [
            // iOS 极简头部：返回 + 标题 + 放回魔毯
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    GestureDetector(
                      key: const Key('编辑器返回'),
                      behavior: HitTestBehavior.translucent,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Icon(CupertinoIcons.back, color: kInk, size: 26),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '灵感全文',
                        textAlign: TextAlign.center,
                        style: _s(
                          size: 17,
                          weight: FontWeight.w600,
                          color: kInk,
                        ),
                      ),
                    ),
                    GestureDetector(
                      key: const Key('放回魔毯按钮'),
                      behavior: HitTestBehavior.translucent,
                      onTap: _removeFromSection,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Icon(
                          CupertinoIcons.tray_arrow_up,
                          color: kInk,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: const Key('全文编辑框'),
                controller: _controller,
                focusNode: _editorFocus,
                maxLines: null, // 无上限
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: kInk,
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  fontSize: 16,
                  height: 1.9,
                  color: kInk,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(22, 8, 22, 22),
                  hintText: '在这里尽情写，没有字数上限…',
                  hintStyle: TextStyle(
                    fontFamily: 'LXGWWenKai',
                    color: Color(0x663A2A18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
