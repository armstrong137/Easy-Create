import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import 'capture_sheet_style.dart';

/// 弹出文字速记输入层：输入灵感 → 存入全局灵感池（魔毯）
Future<void> showTextCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // 跟随键盘上移
    barrierColor: kCaptureSheetBarrierColor,
    backgroundColor: Colors.transparent, // 透出羊皮纸圆角外壳
    builder: (_) => const _TextCaptureSheet(),
  );
}

class _TextCaptureSheet extends ConsumerStatefulWidget {
  const _TextCaptureSheet();

  @override
  ConsumerState<_TextCaptureSheet> createState() => _TextCaptureSheetState();
}

class _TextCaptureSheetState extends ConsumerState<_TextCaptureSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 保存灵感入池并关闭弹层；空内容不保存
  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    await ref.read(inspirationRepositoryProvider).addInspiration(content);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CaptureSheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('记下这一刻', style: captureText(size: 17, weight: FontWeight.w700)),
          const SizedBox(height: 14),
          // 羊皮纸暖底输入框（楷体墨字、金色描边、聚焦加深）
          TextField(
            key: const Key('灵感输入框'),
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 1,
            cursorColor: captureGold,
            style: captureText(size: 16),
            decoration: InputDecoration(
              hintText: '记下这一刻的灵感…',
              hintStyle: captureText(size: 16, color: const Color(0x663A2A18)),
              filled: true,
              fillColor: captureCream,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x33C9A050)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x33C9A050)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: captureGold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          CapturePillButton(
            key: const Key('灵感保存按钮'),
            label: '存入灵感卷轴',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
