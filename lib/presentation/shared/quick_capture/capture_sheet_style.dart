/// 速记弹层统一 iOS 羊皮纸质感（文字/语音两弹层共用）
///
/// 阶段七·3：替换裸 Material 弹层——羊皮纸暖底 + 顶部圆角 + iOS 抓手 +
/// 楷体墨色文字 + 金色描边，与大纲/小节页一致（UI 红线：禁裸 Material 组件）。
library;

import 'package:flutter/material.dart';

/// 羊皮纸暖底
const captureParchment = Color(0xFFFDF6EC);

/// 输入框米白填充
const captureCream = Color(0xFFFFFDF5);

/// 墨色正文
const captureInk = Color(0xFF3A2A18);

/// 金色描边/点缀
const captureGold = Color(0xFFC9A050);

/// 速记弹层遮罩：只轻微压暗背景，避免输入时星球被压成黑色。
const kCaptureSheetBarrierColor = Color(0x2E000000);

/// 弹层楷体文字样式
TextStyle captureText({
  double size = 16,
  FontWeight weight = FontWeight.w500,
  Color color = captureInk,
}) => TextStyle(
  fontFamily: 'LXGWWenKai',
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// 羊皮纸底 + 顶部圆角 + iOS 抓手的弹层外壳（跟随键盘上移）
class CaptureSheetShell extends StatelessWidget {
  const CaptureSheetShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: captureParchment,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // iOS 抓手
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x333A2A18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// 主行动墨色胶囊按钮（存入灵感卷轴）
class CapturePillButton extends StatelessWidget {
  const CapturePillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;

  /// 禁用态（如语音未识别到内容）：降透明度、不响应
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: captureInk,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E3A2A18),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: captureText(
              size: 16,
              weight: FontWeight.w600,
              color: const Color(0xFFF7ECD9),
            ),
          ),
        ),
      ),
    );
  }
}
