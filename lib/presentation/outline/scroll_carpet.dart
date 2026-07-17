/// 卷轴灵感魔毯的视觉外壳（P4 方案二「卷轴灵感」，2026-07-16 整体化返工）。
///
/// 设计红线（用户目标图）：魔毯展开后是**一整条**魔法卷轴——两端鎏金轴头、
/// 侧穗流苏、底部流苏边、中央宝石、四周波斯织纹框，整体悬浮在真实星空里，
/// 纸面只是中间一块可书写、可滚动的窗口。灵感墨迹写进羊皮纸本体，禁止白卡片。
///
/// 实现：`scroll_full.png` 是完整透明背景卷轴物件（含滚轴/织物边/羊皮纸/
/// 流苏/宝石），Flutter 只把活标题和灵感墨迹叠进素材预留区域；避免把控件
/// 画成蓝色牌子或把纸面挖成硬黑洞。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 墨色（与羊皮纸匹配）
const kScrollInk = Color(0xFF3A2A18);

/// 鎏金（标题/分隔纹/进度线）
const kScrollGold = Color(0xFFE8C87A);

/// 相框素材宽高比（透明资产 1134×1285）——布局按此定尺寸，纸面窗口/标题牌
/// 都以本比例内的**归一化坐标**定位，随相框等比缩放。
const kScrollFrameAspect = 1134.0 / 1285.0;

/// 灵感墨迹可写区域在完整羊皮纸中的归一化矩形。
const kScrollHoleLeft = 0.205;
const kScrollHoleTop = 0.305;
const kScrollHoleRight = 0.795;
const kScrollHoleBottom = 0.805;

/// 标题牌归一化矩形，活标题只绘制鎏金字，底板由资产里的织物牌承担。
const kScrollTitleLeft = 0.285;
const kScrollTitleTop = 0.058;
const kScrollTitleRight = 0.715;
const kScrollTitleBottom = 0.145;

/// 整条卷轴（照片级完整素材）。[child] 渲染进羊皮纸安全区，[title]/[onClose]
/// 绘制活标题与收起按钮，[progressLine] 叠右侧进度线。
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

  /// 纸面窗口内容（墨迹/滚动/拖拽层）
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
              // ① 完整照片级卷轴物件：含羊皮纸、滚轴、织纹、流苏、宝石。
              const Positioned.fill(
                child: IgnorePointer(
                  child: Image(
                    image: AssetImage(
                      'assets/textures/scroll_carpet/scroll_full.png',
                    ),
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              // ② 纸面墨迹层：覆盖在资产羊皮纸上，不再另铺一张矩形纸。
              Positioned.fromRect(
                rect: hole,
                child: ClipRect(child: child),
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
              // ④ 活标题：只绘制鎏金字，底板来自素材里的织物牌
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
                right: w * 0.055,
                top: h * 0.060,
                child: _CloseButton(onClose: onClose),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 活标题：鎏金字直接压在资产里的织物牌上，不再画额外矩形底板。
class _TitleCartouche extends StatelessWidget {
  const _TitleCartouche({required this.count, required this.glow});

  final int count;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '灵感卷轴 · $count',
          key: const Key('卷轴织物标题'),
          style: TextStyle(
            fontFamily: 'LXGWWenKai',
            color: kScrollGold,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            shadows: [
              const Shadow(
                color: Color(0xF20A0906),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
              const Shadow(color: Color(0x99E8C87A), blurRadius: 7),
              if (glow) const Shadow(color: Color(0xAAE8C87A), blurRadius: 12),
            ],
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
          size: 18,
          shadows: [Shadow(color: Color(0xE60A0906), blurRadius: 3)],
        ),
      ),
    );
  }
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
    // 各元素只比原来亮一档（用户定稿：明显一点但不突兀）——
    // 织线 35%→50%、金珠 70%→90%、线结 55%→80%，尺寸微放大
    canvas.drawLine(
      Offset(cx, 5),
      Offset(cx, size.height - 5),
      Paint()
        ..color = const Color(0x80795A22)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    final bead = Paint()..color = const Color(0xE6C9A050);
    canvas.drawCircle(Offset(cx, 5), 2.3, bead);
    canvas.drawCircle(Offset(cx, size.height - 5), 2.3, bead);
    final knot = Path()
      ..moveTo(cx, size.height / 2 - 2.8)
      ..lineTo(cx + 2.8, size.height / 2)
      ..lineTo(cx, size.height / 2 + 2.8)
      ..lineTo(cx - 2.8, size.height / 2)
      ..close();
    canvas.drawPath(knot, Paint()..color = const Color(0xCCA9812F));
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
