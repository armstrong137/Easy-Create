import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/quick_capture/capture_button_prefs.dart';

/// 羊皮纸暖底
const _parchment = Color(0xFFFDF6EC);

/// 米白卡片
const _cream = Color(0xFFFFFDF5);

/// 墨色
const _ink = Color(0xFF3A2A18);

/// 楷体样式
TextStyle _kai({
  double size = 16,
  FontWeight weight = FontWeight.w500,
  Color color = _ink,
}) => TextStyle(
  fontFamily: 'LXGWWenKai',
  fontSize: size,
  fontWeight: weight,
  color: color,
);

/// 设置页｜iOS 羊皮纸质感。当前仅"速记按钮位置"一项（用户定稿 2026-07-05）
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onLeft = ref.watch(captureOnLeftProvider);

    return Scaffold(
      backgroundColor: _parchment,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header(context)),
          const SizedBox(height: 8),
          // 速记按钮位置：右（默认）/ 左
          _SettingRow(
            title: '速记按钮位置',
            subtitle: '轻点写字，长按说话',
            trailing: CupertinoSlidingSegmentedControl<bool>(
              groupValue: onLeft,
              backgroundColor: const Color(0x14000000),
              thumbColor: _cream,
              children: {
                false: Padding(
                  key: const Key('速记靠右'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('靠右', style: _kai(size: 14)),
                ),
                true: Padding(
                  key: const Key('速记靠左'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('靠左', style: _kai(size: 14)),
                ),
              },
              onValueChanged: (v) =>
                  ref.read(captureOnLeftProvider.notifier).setOnLeft(v ?? false),
            ),
          ),
        ],
      ),
    );
  }

  /// iOS 极简头部：返回箭头 + 居中标题
  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        GestureDetector(
          key: const Key('设置返回'),
          behavior: HitTestBehavior.translucent,
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(CupertinoIcons.back, color: _ink, size: 26),
          ),
        ),
        Expanded(
          child: Text(
            '设置',
            textAlign: TextAlign.center,
            style: _kai(size: 17, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 54), // 平衡返回箭头
      ],
    ),
  );
}

/// 一行设置项：米白圆角卡，左标题+副标题、右控件
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1A3A2A18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _kai(size: 16, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: _kai(size: 12, color: const Color(0x993A2A18)),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
