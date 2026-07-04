import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好键：语音按钮是否在左下（默认 true = 左语音右文字）
const _kVoiceOnLeftKey = 'voice_button_on_left';

/// SharedPreferences 实例，main() 预载后 override 注入
/// （测试中用 SharedPreferences.setMockInitialValues 后照常注入）
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main() 中必须 override 注入'),
);

/// 双速记按钮位置偏好：true = 语音在左（默认），false = 语音在右
///
/// 互换方式（假设，待终审）：长按任一速记按钮即左右互换，照顾左右利手
class VoiceOnLeftNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kVoiceOnLeftKey) ?? true;

  /// 互换左右并持久化
  Future<void> swap() async {
    state = !state;
    await ref.read(sharedPreferencesProvider).setBool(_kVoiceOnLeftKey, state);
  }
}

final voiceOnLeftProvider = NotifierProvider<VoiceOnLeftNotifier, bool>(
  VoiceOnLeftNotifier.new,
);
