import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音识别薄封装：隔离 speech_to_text 插件
///
/// 只暴露弹层需要的最小接口；测试中用子类替身 override provider，
/// 免去对平台 channel 的依赖
class SpeechService {
  final SpeechToText _speech = SpeechToText();

  /// 初始化系统本地识别引擎；false = 设备不支持或权限被拒
  Future<bool> init() => _speech.initialize();

  /// 开始聆听，[onResult] 持续收到 (识别文字, 是否最终结果)
  Future<void> listen(void Function(String text, bool isFinal) onResult) {
    return _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  /// 停止聆听（保留已识别文字）
  Future<void> stop() => _speech.stop();
}

final speechServiceProvider = Provider<SpeechService>((ref) => SpeechService());
