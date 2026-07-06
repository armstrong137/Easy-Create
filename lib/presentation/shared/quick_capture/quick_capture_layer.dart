import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_keys.dart';
import 'capture_button_prefs.dart';
import 'text_capture_sheet.dart';
import 'voice_capture_sheet.dart';

/// 当前是否有弹出层（对话框/菜单/底部弹层）：有则隐藏双按钮
/// （按钮浮在 Navigator 之上，否则会遮挡弹层内容）
class CaptureSheetOpenNotifier extends Notifier<bool> {
  /// 当前打开的 PopupRoute 计数（由 [ModalAwareObserver] 维护）
  int _popupCount = 0;

  @override
  bool build() => false;

  void _onPopupPushed() {
    _popupCount++;
    state = _popupCount > 0;
  }

  void _onPopupRemoved() {
    _popupCount = (_popupCount - 1).clamp(0, 1 << 30);
    state = _popupCount > 0;
  }

  /// 包裹弹层生命周期：弹出前隐藏按钮，关闭后恢复
  /// （速记自家弹层用；其它页面的弹层由 [ModalAwareObserver] 自动感知）
  Future<void> during(Future<void> Function() showSheet) async {
    state = true;
    try {
      await showSheet();
    } finally {
      state = _popupCount > 0;
    }
  }
}

final captureSheetOpenProvider =
    NotifierProvider<CaptureSheetOpenNotifier, bool>(
      CaptureSheetOpenNotifier.new,
    );

/// 全局路由观察者：任何 PopupRoute（对话框/菜单/底部弹层）出现时
/// 通知速记按钮让位；普通翻页（PageRoute）不影响
class ModalAwareObserver extends NavigatorObserver {
  ModalAwareObserver(this._ref);

  final WidgetRef _ref;

  void _sync(Route<dynamic>? route, bool pushed) {
    if (route is PopupRoute) {
      final notifier = _ref.read(captureSheetOpenProvider.notifier);
      pushed ? notifier._onPopupPushed() : notifier._onPopupRemoved();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route, true);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route, false);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _sync(route, false);
}

/// 全局灵感速记层：单个悬浮按钮，覆盖在任何页面之上
///
/// - **轻点写字**（文字速记弹层）、**长按说话**（语音识别弹层）
/// - 默认在右下；左右侧在设置页切换（偏好持久化，照顾左右利手）
class QuickCaptureLayer extends ConsumerWidget {
  const QuickCaptureLayer({super.key, required this.child});

  /// 被覆盖的页面内容（整个 App 的 Navigator）
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onLeft = ref.watch(captureOnLeftProvider);
    final sheetOpen = ref.watch(captureSheetOpenProvider);

    // 速记层在 Navigator 之上，必须用根 Navigator 的 context 弹出输入层
    Future<void> openText() => ref
        .read(captureSheetOpenProvider.notifier)
        .during(() => showTextCaptureSheet(rootNavigatorKey.currentContext!));

    Future<void> openVoice() {
      HapticFeedback.mediumImpact(); // 长按触发说话，给触觉确认（不 await，弹层同步弹出）
      return ref
          .read(captureSheetOpenProvider.notifier)
          .during(
            () => showVoiceCaptureSheet(rootNavigatorKey.currentContext!),
          );
    }

    return Stack(
      children: [
        child,
        // 弹层打开期间隐藏按钮，避免遮挡弹层内容
        if (!sheetOpen)
          Positioned(
            left: onLeft ? 24 : null,
            right: onLeft ? null : 24,
            bottom: 24,
            child: _CaptureButton(
              key: const Key('速记按钮'),
              onTap: openText,
              onLongPress: openVoice,
            ),
          ),
      ],
    );
  }
}

/// 单个速记圆形按钮（黑白基调，契合素净风格）：轻点写字、长按说话
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    super.key,
    required this.onTap,
    required this.onLongPress,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    // 注意：不能用 Tooltip——本层位于 Navigator/Overlay 之上，Tooltip 会找不到
    // Overlay 而崩溃；改用 Semantics 提供无障碍标签
    return Semantics(
      label: '速记：轻点写字，长按说话',
      button: true,
      child: Material(
        color: Colors.black87,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: const SizedBox.square(
            dimension: 56,
            child: Icon(Icons.edit, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
