/// 卷轴灵感魔毯的视觉外壳（P4 方案二「卷轴灵感」，2026-07-15 定稿）。
///
/// 设计目标不是"魔毯上放灵感卡片"，而是"魔毯展开后变成一张可书写、可滚动的
/// 魔法长卷"：灵感文字写入羊皮纸本体，与魔毯一体化，**禁止独立白色卡片**。
/// 素材自参考图 `picture/方案2_卷轴灵感/` 裁切（照片级素材直用）：
/// 滚轴/羊皮纸/织纹边框/底部卷边见 `assets/textures/scroll_carpet/`。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 墨色（与魔毯羊皮纸匹配）
const kScrollInk = Color(0xFF3A2A18);

/// 鎏金（标题/分隔纹/进度线）
const kScrollGold = Color(0xFFE8C87A);

/// 素材原始宽高比（裁切像素尺寸），布局按面板宽度等比缩放
const kScrollRollerAspect = 150.0 / 755.0;
const kScrollCurlAspect = 250.0 / 810.0;

/// 左右织纹边框显示宽度
const kScrollBorderWidth = 22.0;

/// 顶部滚轴 + 织入的标题（`灵感魔毯 · N`）。
/// 标题金字直接排在滚轴织物上，不再是悬浮 pill。
class ScrollRollerHeader extends StatelessWidget {
  const ScrollRollerHeader({
    super.key,
    required this.count,
    required this.glow,
    required this.onClose,
  });

  /// 灵感条数（织入标题）
  final int count;

  /// 高级效果：金字带微光
  final bool glow;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/textures/scroll_carpet/scroll_roller.png',
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        ),
        Center(
          child: Text(
            '灵感魔毯 · $count',
            key: const Key('卷轴织物标题'),
            style: TextStyle(
              fontFamily: 'LXGWWenKai',
              color: kScrollGold,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              shadows: [
                const Shadow(
                  color: Color(0xE61A0F08),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
                if (glow) const Shadow(color: Color(0x80E8C87A), blurRadius: 9),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            key: const Key('魔毯收起按钮'),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            icon: const Icon(
              Icons.close_rounded,
              color: kScrollGold,
              size: 20,
              shadows: [
                Shadow(
                  color: Color(0xE61A0F08),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

/// 羊皮纸书写区外壳：羊皮纸底 + 左右织纹边框 + 内容 + 可选墨迹进度线。
class ScrollParchmentBody extends StatelessWidget {
  const ScrollParchmentBody({
    super.key,
    required this.child,
    this.progress,
    this.glow = false,
  });

  final Widget child;

  /// 滚动进度 0~1（null = 无溢出，不显示进度线）
  final double? progress;

  /// 高级效果：进度金点带辉光
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 羊皮纸底（含星图水印，空状态直接透出）
        Image.asset(
          'assets/textures/scroll_carpet/scroll_parchment.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
        // 左右织纹边框（纵向拉伸；波斯织纹容拉伸不露馅）
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kScrollBorderWidth,
          child: Image.asset(
            'assets/textures/scroll_carpet/scroll_border_left.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: kScrollBorderWidth,
          child: Image.asset(
            'assets/textures/scroll_carpet/scroll_border_right.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
        // 纸面上下沿的柔和阴影：长卷"卷入滚轴"的暗示
        const Positioned(
          left: kScrollBorderWidth,
          right: kScrollBorderWidth,
          top: 0,
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59321F0E), Color(0x00321F0E)],
              ),
            ),
          ),
        ),
        const Positioned(
          left: kScrollBorderWidth,
          right: kScrollBorderWidth,
          bottom: 0,
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x59321F0E), Color(0x00321F0E)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          left: kScrollBorderWidth + 8,
          right: kScrollBorderWidth + 8,
          child: child,
        ),
        if (progress != null)
          Positioned(
            right: kScrollBorderWidth + 2,
            top: 12,
            bottom: 12,
            width: 10,
            child: CustomPaint(
              key: const Key('卷轴进度线'),
              painter: InkProgressPainter(t: progress!, glow: glow),
            ),
          ),
      ],
    );
  }
}

/// 底部卷边（长卷下端卷起的织物 + 鎏金饰件）
class ScrollBottomCurl extends StatelessWidget {
  const ScrollBottomCurl({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/textures/scroll_carpet/scroll_bottom_curl.png',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// 金色分隔纹：细金线 + 中央菱形星饰（灵感条目之间）
class GoldDivider extends StatelessWidget {
  const GoldDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 10,
      width: double.infinity,
      child: CustomPaint(painter: _GoldDividerPainter()),
    );
  }
}

class _GoldDividerPainter extends CustomPainter {
  const _GoldDividerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final cx = size.width / 2;
    // 两端渐隐的金线（深金描边 + 亮金主线，羊皮纸上要压得住底纹）
    final rect = Rect.fromLTWH(0, cy - 1, size.width, 2);
    final under = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x00795A22), Color(0xB3795A22), Color(0x00795A22)],
      ).createShader(rect);
    canvas.drawLine(
      Offset(size.width * 0.06, cy + 0.6),
      Offset(size.width * 0.94, cy + 0.6),
      under,
    );
    final line = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x00E8C87A), Color(0xFFE8C87A), Color(0x00E8C87A)],
      ).createShader(rect);
    canvas.drawLine(
      Offset(size.width * 0.06, cy),
      Offset(size.width * 0.94, cy),
      line,
    );
    // 中央菱形星饰（深金衬底 + 亮金本体）
    void diamond(double r, Paint p) {
      final path = Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r, cy)
        ..close();
      canvas.drawPath(path, p);
    }

    diamond(4.6, Paint()..color = const Color(0xCC795A22));
    diamond(3.4, Paint()..color = const Color(0xFFE8C87A));
    // 菱形两侧的小点
    final dot = Paint()..color = const Color(0xE6C9A050);
    canvas.drawCircle(Offset(cx - 12, cy), 1.5, dot);
    canvas.drawCircle(Offset(cx + 12, cy), 1.5, dot);
  }

  @override
  bool shouldRepaint(_GoldDividerPainter oldDelegate) => false;
}

/// 右侧墨迹进度线：淡金竖线 + 随滚动移动的金点；滚到底金点微亮
class InkProgressPainter extends CustomPainter {
  const InkProgressPainter({required this.t, required this.glow});

  /// 滚动进度 0~1
  final double t;

  /// 高级效果开（金点辉光）
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..strokeWidth = 1.4
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33C9A050), Color(0x88C9A050), Color(0x33C9A050)],
      ).createShader(Rect.fromLTWH(x - 1, 0, 2, size.height));
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    final clamped = t.clamp(0.0, 1.0);
    final y = clamped * size.height;
    // 滚到底部：金点微微发亮作反馈
    final atEnd = clamped >= 0.99;
    if (glow) {
      canvas.drawCircle(
        Offset(x, y),
        atEnd ? 8 : 6,
        Paint()
          ..color = atEnd ? const Color(0x66E8C87A) : const Color(0x40E8C87A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawCircle(
      Offset(x, y),
      atEnd ? 3.6 : 3,
      Paint()..color = atEnd ? const Color(0xFFF2DC9E) : kScrollGold,
    );
  }

  @override
  bool shouldRepaint(InkProgressPainter old) =>
      old.t != t || old.glow != glow;
}

/// 墨迹条目在展开时间线上的淡入进度（写入感的近似：按序淡入）。
/// [unroll] 为主时间线 0~1；第 [index] 条从 0.58 起按序错峰。
double inkFadeT(double unroll, int index) {
  final start = math.min(0.58 + index * 0.05, 0.9);
  return ((unroll - start) / (1 - start)).clamp(0.0, 1.0);
}
