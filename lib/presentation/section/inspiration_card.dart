import 'package:flutter/material.dart';

import '../../core/inspiration_font.dart';

/// 小节页配色（羊皮纸暖调，跟随全局魔树/魔毯基调）
const kSectionParchment = Color(0xFFFDF6EC); // 页面底
const kCardCream = Color(0xFFFFFDF5); // 卡面（略亮于页面）
const kCardEdge = Color(0x33B58A3C); // 金色发丝边
const kInk = Color(0xFF3A2A18); // 墨色正文

/// 灵感卡片：羊皮纸暖调卡 + 金色发丝边 + iOS 柔和投影（2026-07-04 钱包版）
///
/// 用户定稿：苹果钱包叠层卡堆 + 羊皮纸米白暖调。去掉旧的黑硬描边，
/// 改柔和多层投影与圆角，贴近 iOS 卡片质感；大小随文字自适应，超长省略。
class InspirationCard extends StatelessWidget {
  const InspirationCard({
    super.key,
    required this.content,
    this.maxLines = 12,
    this.onTap,
  });

  final String content;

  /// 超长省略的行数上限（主区卡片限行，全文编辑器不限）
  final int maxLines;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, minHeight: 96),
        decoration: BoxDecoration(
          color: kCardCream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kCardEdge),
          boxShadow: const [
            // iOS 柔和多层投影：近处轻、远处淡，卡片微微浮起
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Text(
          content,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          // 英文灵感用品牌斜体，中文用楷体
          style: TextStyle(
            fontFamily: inspirationFontFamily(content) ?? 'LXGWWenKai',
            fontStyle: inspirationIsBrand(content)
                ? FontStyle.italic
                : FontStyle.normal,
            fontSize: 16,
            height: 1.7,
            color: kInk,
          ),
        ),
      ),
    );
  }
}

/// 灵感卡拖拽浮影：主区卡、卡片包拖回魔毯时共用。
class InspirationDragFeedback extends StatelessWidget {
  const InspirationDragFeedback({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 210,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kCardCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC9A050), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Color(0x59C9A050), blurRadius: 14),
          ],
        ),
        child: Text(
          content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: inspirationFontFamily(content) ?? 'LXGWWenKai',
            fontStyle: inspirationIsBrand(content)
                ? FontStyle.italic
                : FontStyle.normal,
            fontSize: 13,
            height: 1.45,
            color: kInk,
          ),
        ),
      ),
    );
  }
}
