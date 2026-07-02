import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import 'speech_service.dart';

/// 弹出语音速记层：系统本地引擎识别 → 用户确认 → 存入灵感池（魔毯）
Future<void> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _VoiceCaptureSheet(),
  );
}

class _VoiceCaptureSheet extends ConsumerStatefulWidget {
  const _VoiceCaptureSheet();

  @override
  ConsumerState<_VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends ConsumerState<_VoiceCaptureSheet> {
  /// 存字段而非 dispose 里 ref.read（Riverpod 3 禁止 dispose 中用 ref）
  late final SpeechService _speech = ref.read(speechServiceProvider);

  /// null = 初始化中；false = 不可用；true = 可用
  bool? _available;

  /// 当前已识别文字（partial 结果实时刷新）
  String _recognized = '';

  /// 是否正在聆听
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// 初始化引擎并开始聆听
  Future<void> _start() async {
    final ok = await _speech.init();
    if (!mounted) return;
    setState(() => _available = ok);
    if (!ok) return;

    setState(() => _listening = true);
    await _speech.listen((text, isFinal) {
      if (!mounted) return;
      setState(() {
        _recognized = text;
        if (isFinal) _listening = false;
      });
    });
  }

  /// 确认入池并关闭弹层；空识别结果不保存
  Future<void> _save() async {
    await _speech.stop();
    final content = _recognized.trim();
    if (content.isEmpty) return;
    await ref.read(inspirationRepositoryProvider).addInspiration(content);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // 弹层被划掉/取消时确保停止聆听
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_available == null)
            const Center(child: CircularProgressIndicator())
          else if (_available == false)
            const Text(
              key: Key('语音不可用提示'),
              '语音识别不可用：请检查麦克风权限，或该设备没有本地识别引擎',
              textAlign: TextAlign.center,
            )
          else ...[
            Row(
              children: [
                Icon(
                  _listening ? Icons.mic : Icons.mic_off,
                  color: _listening ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(_listening ? '聆听中…' : '识别结束'),
              ],
            ),
            const SizedBox(height: 12),
            // 实时识别文字
            Text(
              key: const Key('语音识别文字'),
              _recognized.isEmpty ? '请开始说话…' : _recognized,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('语音保存按钮'),
              onPressed: _save,
              child: const Text('存入灵感魔毯'),
            ),
          ],
        ],
      ),
    );
  }
}
