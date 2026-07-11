import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import 'capture_sheet_style.dart';
import 'speech_service.dart';

/// 弹出语音速记层：系统本地引擎识别 → 用户确认 → 存入灵感池（魔毯）
Future<void> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: kCaptureSheetBarrierColor,
    backgroundColor: Colors.transparent, // 透出羊皮纸圆角外壳
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
    return CaptureSheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_available == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: CupertinoActivityIndicator(color: captureInk, radius: 14),
            )
          else if (_available == false)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                key: const Key('语音不可用提示'),
                '语音识别不可用：请检查麦克风权限，\n或该设备没有本地识别引擎',
                textAlign: TextAlign.center,
                style: captureText(size: 14, color: const Color(0xCC3A2A18)),
              ),
            )
          else ...[
            // 聆听状态：麦克风图标 + 文案（聆听中金色微光呼吸感）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _listening
                      ? CupertinoIcons.mic_fill
                      : CupertinoIcons.mic_slash,
                  size: 20,
                  color: _listening ? captureGold : const Color(0x803A2A18),
                ),
                const SizedBox(width: 8),
                Text(
                  _listening ? '聆听中…' : '识别结束',
                  style: captureText(size: 15, weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 实时识别文字（羊皮纸暖底卡）
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 88),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: captureCream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x33C9A050)),
              ),
              child: Text(
                key: const Key('语音识别文字'),
                _recognized.isEmpty ? '请开始说话…' : _recognized,
                style: captureText(
                  size: 16,
                  color: _recognized.isEmpty
                      ? const Color(0x663A2A18)
                      : captureInk,
                ),
              ),
            ),
            const SizedBox(height: 18),
            CapturePillButton(
              key: const Key('语音保存按钮'),
              label: '存入灵感魔毯',
              enabled: _recognized.trim().isNotEmpty,
              onPressed: _save,
            ),
          ],
        ],
      ),
    );
  }
}
