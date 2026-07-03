import 'package:flutter/material.dart';

/// 灵感卡片：纯白卡 + 四周 3D 纯黑细框（定稿）
///
/// 3D 效果：黑细描边 + 右下偏移的纯黑实体投影，像一张略微
/// 悬浮于纸面的卡片；大小随文字长短自适应，超长省略。
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
        constraints: const BoxConstraints(minWidth: 160, minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.4),
          boxShadow: const [
            // 右下纯黑实体投影 → 3D 细框立体感
            BoxShadow(color: Colors.black, offset: Offset(3, 3)),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          content,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 15,
            height: 1.6,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
