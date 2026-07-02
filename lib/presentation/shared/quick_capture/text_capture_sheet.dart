import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';

/// 弹出文字速记输入层：输入灵感 → 存入全局灵感池（魔毯）
Future<void> showTextCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // 跟随键盘上移
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
    // 底部内边距跟随键盘高度，保证输入框不被遮挡
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('灵感输入框'),
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: '记下这一刻的灵感…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('灵感保存按钮'),
            onPressed: _save,
            child: const Text('存入灵感魔毯'),
          ),
        ],
      ),
    );
  }
}
