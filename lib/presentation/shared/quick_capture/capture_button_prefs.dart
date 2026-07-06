import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好键：速记按钮是否在左下（默认 false = 在右下）
const _kCaptureOnLeftKey = 'capture_button_on_left';

/// SharedPreferences 实例，main() 预载后 override 注入
/// （测试中用 SharedPreferences.setMockInitialValues 后照常注入）
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main() 中必须 override 注入'),
);

/// 单速记按钮位置偏好：true = 在左下，false = 在右下（默认，用户定稿 2026-07-05）
///
/// 单按钮交互：**轻点写字、长按说话**；左右侧在设置页切换（照顾左右利手）。
class CaptureOnLeftNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kCaptureOnLeftKey) ?? false;

  /// 设置按钮靠左/靠右并持久化
  Future<void> setOnLeft(bool onLeft) async {
    state = onLeft;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_kCaptureOnLeftKey, onLeft);
  }
}

final captureOnLeftProvider = NotifierProvider<CaptureOnLeftNotifier, bool>(
  CaptureOnLeftNotifier.new,
);
