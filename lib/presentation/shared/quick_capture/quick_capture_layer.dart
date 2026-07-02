import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_keys.dart';
import 'capture_button_prefs.dart';
import 'text_capture_sheet.dart';

/// 全局灵感速记层：左下 + 右下双悬浮按钮，覆盖在任何页面之上
///
/// - 默认左 = 语音、右 = 文字；长按任一按钮左右互换（偏好持久化）
/// - 语音识别在阶段二·3 接入，当前点击语音按钮仅提示
class QuickCaptureLayer extends ConsumerWidget {
  const QuickCaptureLayer({super.key, required this.child});

  /// 被覆盖的页面内容（整个 App 的 Navigator）
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceOnLeft = ref.watch(voiceOnLeftProvider);

    // 长按互换左右位置（假设的交互方式，待终审），带触觉反馈
    Future<void> swap() async {
      await ref.read(voiceOnLeftProvider.notifier).swap();
      await HapticFeedback.mediumImpact();
    }

    final voiceButton = _CaptureButton(
      key: const Key('语音速记按钮'),
      icon: Icons.mic,
      tooltip: '语音速记',
      onTap: () {
        // TODO(阶段二·3)：接入 speech_to_text 系统本地引擎
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('语音识别即将到来（阶段二·3）')),
        );
      },
      onLongPress: swap,
    );

    final textButton = _CaptureButton(
      key: const Key('文字速记按钮'),
      icon: Icons.edit,
      tooltip: '文字速记',
      // 速记层在 Navigator 之上，必须用根 Navigator 的 context 弹出输入层
      onTap: () => showTextCaptureSheet(rootNavigatorKey.currentContext!),
      onLongPress: swap,
    );

    return Stack(
      children: [
        child,
        // 左下角
        Positioned(
          left: 24,
          bottom: 24,
          child: voiceOnLeft ? voiceButton : textButton,
        ),
        // 右下角
        Positioned(
          right: 24,
          bottom: 24,
          child: voiceOnLeft ? textButton : voiceButton,
        ),
      ],
    );
  }
}

/// 单个速记圆形按钮（黑白基调，契合铅笔树的素净风格）
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // 注意：不能用 Tooltip——本层位于 Navigator/Overlay 之上，Tooltip 会找不到
    // Overlay 而崩溃；改用 Semantics 提供无障碍标签
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        color: Colors.black87,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox.square(
            dimension: 56,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
