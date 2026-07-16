/// 卷轴灵感魔毯的视觉外壳（P4 方案二「卷轴灵感」，2026-07-16 整体化返工）。
///
/// 设计红线（用户目标图）：魔毯展开后是**一整条**魔法卷轴——两端鎏金轴头、
/// 侧穗流苏、底部流苏边、中央宝石、四周波斯织纹框，整体悬浮在真实星空里，
/// 纸面只是中间一块可书写、可滚动的窗口。灵感墨迹写进羊皮纸本体，禁止白卡片。
///
/// 实现：把参考图 04 的整条卷轴抠成"透明中空相框" `scroll_full.png`
/// （外部星空/金纹抠透明、地球排除、纸面窗口挖空羽化），照片级素材整体直用。
/// 相框覆于最上层，挖空处透出下层的真羊皮纸 + 活文字；标题牌活绘覆盖基线字。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 墨色（与羊皮纸匹配）
const kScrollInk = Color(0xFF3A2A18);

/// 鎏金（标题/分隔纹/进度线）
const kScrollGold = Color(0xFFE8C87A);

/// 相框素材宽高比（裁切像素 900×1070）——布局按此定尺寸，纸面窗口/标题牌
/// 都以本比例内的**归一化坐标**定位，随相框等比缩放。
const kScrollFrameAspect = 900.0 / 1070.0;

/// 纸面窗口在相框内的归一化矩形（scroll_full.png 挖空区，见 build_frame 脚本）
const kScrollHoleLeft = 0.2111;
const kScrollHoleTop = 0.1729;
const kScrollHoleRight = 0.7889;
const kScrollHoleBottom = 0.7710;

/// 标题牌（基线"灵感魔毯·N"所在织物牌）归一化矩形，活标题覆盖其上
const kScrollTitleLeft = 0.30;
const kScrollTitleTop = 0.060;
const kScrollTitleRight = 0.70;
const kScrollTitleBottom = 0.152;

/// 整条卷轴相框（照片级素材，透明中空）。[child] 渲染进纸面窗口，
/// [title]/[onClose] 绘制活标题牌与收起按钮，[progressLine] 叠右侧进度线。
class ScrollFrame extends StatelessWidget {
  const ScrollFrame({
    super.key,
    required this.count,
    required this.glow,
    required this.onClose,
    required this.child,
    this.progress,
    this.progressOpacity = 1,
    this.titleOpacity = 1,
  });

  /// 灵感条数（织入活标题牌）
  final int count;

  /// 高级效果：标题/进度金点带微光
  final bool glow;

  final VoidCallback onClose;

  /// 纸面窗口内容（羊皮纸 + 墨迹，随相框挖空处显示）
  final Widget child;

  /// 滚动进度 0~1（null = 无溢出不显示进度线）
  final double? progress;

  /// 进度线透明度（展开分镜里最后淡入）
  final double progressOpacity;

  /// 标题牌透明度（展开分镜里随滚轴现身淡入）
  final double titleOpacity;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kScrollFrameAspect,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          Rect frac(double l, double t, double r, double b) =>
              Rect.fromLTRB(l * w, t * h, r * w, b * h);
          final hole = frac(
            kScrollHoleLeft,
            kScrollHoleTop,
            kScrollHoleRight,
            kScrollHoleBottom,
          );
          final title = frac(
            kScrollTitleLeft,
            kScrollTitleTop,
            kScrollTitleRight,
            kScrollTitleBottom,
          );
          return Stack(
            children: [
              // ① 纸面窗口：真羊皮纸底 + 墨迹内容（在相框挖空处透出）。
              //    放最底层，手势直达（相框在其上但 IgnorePointer 放行）。
              Positioned.fromRect(
                rect: hole,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _ParchmentFill(),
                      child,
                      // 顶/底卷入阴影：内容滑动时像被卷进滚轴
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 18,
                        child: _EdgeShade(top: true),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 16,
                        child: _EdgeShade(top: false),
                      ),
                    ],
                  ),
                ),
              ),
              // ② 相框（最上层视觉，放行手势给下层纸面）
              const Positioned.fill(
                child: IgnorePointer(
                  child: Image(
                    image: AssetImage(
                      'assets/textures/scroll_carpet/scroll_full.png',
                    ),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              // ③ 右侧墨迹进度线（叠在纸面窗口右缘内）
              if (progress != null)
                Positioned(
                  left: hole.right - 14,
                  top: hole.top + 10,
                  height: hole.height - 20,
                  width: 10,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: progressOpacity.clamp(0.0, 1.0),
                      child: CustomPaint(
                        key: const Key('卷轴进度线'),
                        painter: InkProgressPainter(t: progress!, glow: glow),
                      ),
                    ),
                  ),
                ),
              // ④ 活标题牌：覆盖基线"灵感魔毯·N"，随条数实时更新
              Positioned.fromRect(
                rect: title,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: titleOpacity.clamp(0.0, 1.0),
                    child: _TitleCartouche(count: count, glow: glow),
                  ),
                ),
              ),
              // ⑤ 收起按钮（右上轴头附近，可点）
              Positioned(
                right: w * 0.045,
                top: h * 0.055,
                child: _CloseButton(onClose: onClose),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 活标题牌：深蓝织物牌底 + 细金框 + 鎏金"灵感魔毯 · N"
class _TitleCartouche extends StatelessWidget {
  const _TitleCartouche({required this.count, required this.glow});

  final int count;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 与基线牌同色系深蓝，完全盖住基线字
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2144), Color(0xFF12162E)],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFB8933F), width: 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '灵感魔毯 · $count',
            style: TextStyle(
              fontFamily: 'LXGWWenKai',
              color: kScrollGold,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              shadows: [
                const Shadow(color: Color(0xE60A0906), blurRadius: 2),
                if (glow) const Shadow(color: Color(0x80E8C87A), blurRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('魔毯收起按钮'),
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(
          Icons.close_rounded,
          color: kScrollGold,
          size: 20,
          shadows: [Shadow(color: Color(0xE60A0906), blurRadius: 3)],
        ),
      ),
    );
  }
}

/// 纸面窗口的羊皮纸底：真素材平铺（与相框保留的纸缘同源，无缝）+ 极淡星图水印
class _ParchmentFill extends StatelessWidget {
  const _ParchmentFill();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Image(
          image: AssetImage('assets/textures/scroll_carpet/scroll_parchment.png'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
        CustomPaint(
          isComplex: true,
          willChange: false,
          painter: const _StarChartPainter(),
        ),
      ],
    );
  }
}

/// 上下卷入阴影
class _EdgeShade extends StatelessWidget {
  const _EdgeShade({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [Color(0x66321F0E), Color(0x00321F0E)],
        ),
      ),
    );
  }
}

/// 极淡星图水印（弯月/四芒星/虚线连线），融进纸面
class _StarChartPainter extends CustomPainter {
  const _StarChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0x24A98B4F);
    final moonC = Offset(size.width * 0.2, size.height * 0.16);
    final moon = Path()
      ..addOval(Rect.fromCircle(center: moonC, radius: 9))
      ..addOval(Rect.fromCircle(center: moonC.translate(4, -2), radius: 8));
    moon.fillType = PathFillType.evenOdd;
    canvas.drawPath(moon, ink);
    const pts = [
      Offset(0.34, 0.28),
      Offset(0.55, 0.2),
      Offset(0.7, 0.36),
      Offset(0.48, 0.5),
      Offset(0.26, 0.6),
      Offset(0.64, 0.66),
      Offset(0.8, 0.82),
    ];
    for (var i = 0; i < pts.length; i++) {
      final p = Offset(pts[i].dx * size.width, pts[i].dy * size.height);
      _star(canvas, p, i.isEven ? 6.0 : 4.0, ink);
      if (i > 0) {
        final prev = Offset(
          pts[i - 1].dx * size.width,
          pts[i - 1].dy * size.height,
        );
        _dashed(canvas, prev, p, ink);
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, stroke);
      d = end + gap;
    }
  }

  @override
  bool shouldRepaint(_StarChartPainter oldDelegate) => false;
}

/// 排序把手：金线书签结（融入卷轴材质，不用系统图标）
class InkHandle extends StatelessWidget {
  const InkHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 32,
      child: CustomPaint(painter: _InkHandlePainter()),
    );
  }
}

class _InkHandlePainter extends CustomPainter {
  const _InkHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    canvas.drawLine(
      Offset(cx, 5),
      Offset(cx, size.height - 5),
      Paint()
        ..color = const Color(0x59795A22)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    final bead = Paint()..color = const Color(0xB3C9A050);
    canvas.drawCircle(Offset(cx, 5), 2, bead);
    canvas.drawCircle(Offset(cx, size.height - 5), 2, bead);
    final knot = Path()
      ..moveTo(cx, size.height / 2 - 2.4)
      ..lineTo(cx + 2.4, size.height / 2)
      ..lineTo(cx, size.height / 2 + 2.4)
      ..lineTo(cx - 2.4, size.height / 2)
      ..close();
    canvas.drawPath(knot, Paint()..color = const Color(0x8CA9812F));
  }

  @override
  bool shouldRepaint(_InkHandlePainter oldDelegate) => false;
}

/// 金色分隔纹：轻装饰单金线 + 中央小菱饰（灵感条目之间，不像表格线）
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
    final rect = Rect.fromLTWH(0, cy - 1, size.width, 2);
    final line = Paint()
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x00C9A050), Color(0x8CC9A050), Color(0x00C9A050)],
      ).createShader(rect);
    canvas.drawLine(
      Offset(size.width * 0.16, cy),
      Offset(size.width * 0.84, cy),
      line,
    );
    void diamond(double r, Paint p) {
      final path = Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r, cy)
        ..close();
      canvas.drawPath(path, p);
    }

    diamond(3.6, Paint()..color = const Color(0x73795A22));
    diamond(2.6, Paint()..color = const Color(0xCCE0BE72));
  }

  @override
  bool shouldRepaint(_GoldDividerPainter oldDelegate) => false;
}

/// 右侧墨迹进度线：淡金竖线 + 随滚动移动的金点；滚到底金点微亮
class InkProgressPainter extends CustomPainter {
  const InkProgressPainter({required this.t, required this.glow});

  final double t;
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
  bool shouldRepaint(InkProgressPainter old) => old.t != t || old.glow != glow;
}

/// 墨迹条目在展开时间线上的淡入进度（写入感：按序错峰淡入）。
double inkFadeT(double unroll, int index) {
  final start = math.min(0.58 + index * 0.05, 0.9);
  return ((unroll - start) / (1 - start)).clamp(0.0, 1.0);
}
