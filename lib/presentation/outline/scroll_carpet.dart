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

/// 卷轴部件宽高比：顶部/底部都用绘制式 3D 部件，比例可控，避免参考图裁片
/// 自带星空背景与多余纸面造成“显示不全、像截图硬裁”的问题。
const kScrollRollerAspect = 0.16;
const kScrollCurlAspect = 0.18;

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
        const CustomPaint(painter: ScrollRollerPainter()),
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

/// 绘制式顶部滚轴：用圆柱渐变、金属端头、织纹线条和投影建立 3D 感。
/// 不再使用带星空背景的截图素材。
class ScrollRollerPainter extends CustomPainter {
  const ScrollRollerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final y = h * 0.18;
    final bodyH = h * 0.58;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, y, size.width * 0.84, bodyH),
      Radius.circular(bodyH / 2),
    );
    _drawShadow(canvas, size, y + bodyH);
    _drawFabricCylinder(canvas, body);
    _drawGoldEnds(canvas, size, y, bodyH);
    _drawFabricOrnaments(canvas, body.outerRect);
  }

  void _drawShadow(Canvas canvas, Size size, double y) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, y + size.height * 0.18),
        width: size.width * 0.76,
        height: size.height * 0.25,
      ),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  void _drawFabricCylinder(Canvas canvas, RRect body) {
    final rect = body.outerRect;
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF5B2417),
            Color(0xFF1C2442),
            Color(0xFF8A3B1D),
            Color(0xFF261322),
          ],
          stops: const [0, 0.28, 0.62, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xCCE4BE75),
    );
    canvas.drawLine(
      Offset(rect.left + 18, rect.top + rect.height * 0.33),
      Offset(rect.right - 18, rect.top + rect.height * 0.33),
      Paint()
        ..color = const Color(0x66F0D591)
        ..strokeWidth = 1,
    );
  }

  void _drawGoldEnds(Canvas canvas, Size size, double y, double bodyH) {
    final cy = y + bodyH / 2;
    for (final side in [-1, 1]) {
      final x = side < 0 ? size.width * 0.08 : size.width * 0.92;
      final cap = Rect.fromCenter(
        center: Offset(x, cy),
        width: bodyH * 0.92,
        height: bodyH * 1.05,
      );
      canvas.drawOval(
        cap,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF5D3510), Color(0xFFFFD98B), Color(0xFF7A4717)],
          ).createShader(cap),
      );
      canvas.drawCircle(
        Offset(x + side * bodyH * 0.44, cy),
        bodyH * 0.16,
        Paint()..color = const Color(0xFFF3CD80),
      );
      canvas.drawLine(
        Offset(x - side * bodyH * 0.16, y + bodyH * 0.18),
        Offset(x - side * bodyH * 0.16, y + bodyH * 0.82),
        Paint()
          ..color = const Color(0x99623312)
          ..strokeWidth = 2,
      );
    }
  }

  void _drawFabricOrnaments(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0x55E8C87A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var x = rect.left + 34; x < rect.right - 34; x += 34) {
      final cy = rect.center.dy;
      final path = Path()
        ..moveTo(x - 8, cy)
        ..quadraticBezierTo(x, cy - 7, x + 8, cy)
        ..quadraticBezierTo(x, cy + 7, x - 8, cy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(ScrollRollerPainter oldDelegate) => false;
}

/// 羊皮纸书写区外壳：织纹边框在下层，**不规则纸边**的羊皮纸覆于其上
/// （纸缘波浪处透出边框织物，建立"纸嵌在毯里"的空间关系），
/// 纸面为 CustomPainter 手绘（清晰纸纹/暗角/星图水印，杜绝整张模糊截图），
/// 上沿卷入阴影暗示纸从滚轴后方铺出。
class ScrollParchmentBody extends StatelessWidget {
  const ScrollParchmentBody({
    super.key,
    required this.child,
    this.progress,
    this.progressOpacity = 1,
    this.glow = false,
  });

  final Widget child;

  /// 滚动进度 0~1（null = 无溢出，不显示进度线）
  final double? progress;

  /// 进度线透明度（展开分镜里进度线**最后**淡入，收起时最先退场）
  final double progressOpacity;

  /// 高级效果：进度金点带辉光
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 织纹边框（下层，内缘已做 alpha 过渡）
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kScrollBorderWidth + 12,
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
          width: kScrollBorderWidth + 12,
          child: Image.asset(
            'assets/textures/scroll_carpet/scroll_border_right.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
        // 羊皮纸：不规则纸边裁切，微微压住边框内缘
        Positioned.fill(
          left: kScrollBorderWidth - 4,
          right: kScrollBorderWidth - 4,
          child: CustomPaint(painter: const PaperShadowPainter()),
        ),
        Positioned.fill(
          left: kScrollBorderWidth - 4,
          right: kScrollBorderWidth - 4,
          child: ClipPath(
            clipper: const PaperEdgeClipper(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    painter: const ParchmentPainter(),
                  ),
                ),
                // 顶部卷入阴影：内容上滑时像被卷进滚轴（P4-R4 遮罩）
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x80321F0E), Color(0x00321F0E)],
                      ),
                    ),
                  ),
                ),
                // 底部卷边阴影：下一条从卷边下方露出的暗示
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x66321F0E), Color(0x00321F0E)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(left: 12, right: 12, child: child),
              ],
            ),
          ),
        ),
        if (progress != null)
          Positioned(
            right: kScrollBorderWidth + 2,
            top: 14,
            bottom: 14,
            width: 10,
            child: Opacity(
              opacity: progressOpacity.clamp(0.0, 1.0),
              child: CustomPaint(
                key: const Key('卷轴进度线'),
                painter: InkProgressPainter(t: progress!, glow: glow),
              ),
            ),
          ),
      ],
    );
  }
}

/// 排序把手：织入卷轴的"金线书签结"——两粒金珠夹一段织线（R3 定稿：
/// 不再用三横线系统图标，操作暗示融进材质，不当视觉主角）。
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
    // 织线
    canvas.drawLine(
      Offset(cx, 5),
      Offset(cx, size.height - 5),
      Paint()
        ..color = const Color(0x59795A22)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    // 上下金珠
    final bead = Paint()..color = const Color(0xB3C9A050);
    canvas.drawCircle(Offset(cx, 5), 2.0, bead);
    canvas.drawCircle(Offset(cx, size.height - 5), 2.0, bead);
    // 中央织线结（小菱形）
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

/// 纸面投影：在裁切羊皮纸背后先画柔和暗影，让纸面真正浮在织物边框上。
class PaperShadowPainter extends CustomPainter {
  const PaperShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = const PaperEdgeClipper().getClip(size);
    canvas.save();
    canvas.translate(0, 5);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x73000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PaperShadowPainter oldDelegate) => false;
}

/// 不规则纸边：左右缘轻微波浪（真实羊皮纸不会是刀切矩形），
/// 上下缘平直（分别藏在滚轴与底部卷边后面）。
class PaperEdgeClipper extends CustomClipper<Path> {
  const PaperEdgeClipper();

  @override
  Path getClip(Size size) {
    const amp = 3.2; // 波浪振幅
    const waves = 5; // 每侧波浪数
    final path = Path()..moveTo(amp, 0);
    path.lineTo(size.width - amp, 0);
    // 右缘：向下波浪
    final segR = size.height / waves;
    for (var i = 0; i < waves; i++) {
      final bump = i.isEven ? amp : -amp;
      path.quadraticBezierTo(
        size.width - amp + bump,
        segR * (i + 0.5),
        size.width - amp,
        segR * (i + 1),
      );
    }
    path.lineTo(amp, size.height);
    // 左缘：向上波浪（相位错开，别和右缘对称得像模具）
    final segL = size.height / waves;
    for (var i = waves - 1; i >= 0; i--) {
      final bump = i.isOdd ? amp : -amp;
      path.quadraticBezierTo(amp + bump, segL * (i + 0.5), amp, segL * i);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(PaperEdgeClipper oldClipper) => false;
}

/// 手绘羊皮纸：底色渐变 + 斑驳陈化 + 四边暗角 + 星图水印。
/// 任意尺寸下都清晰（整张截图放大会糊，这是 P4-R2 判定的完成度硬伤）。
class ParchmentPainter extends CustomPainter {
  const ParchmentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 底色：微暖的纵向渐变
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE7D5B0), Color(0xFFDDC79C), Color(0xFFD0B98A)],
        ).createShader(rect),
    );
    // 斑驳陈化：固定种子的柔和色斑（深沉/偏亮两组）
    final rng = math.Random(7);
    for (var i = 0; i < 130; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 6 + rng.nextDouble() * 26;
      final dark = rng.nextBool();
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = dark ? const Color(0x0D6B4E24) : const Color(0x0DF5EACB)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    _drawEdgeShade(canvas, size);
    _drawStarChart(canvas, size);
  }

  void _drawEdgeShade(Canvas canvas, Size size) {
    final top = Rect.fromLTWH(0, 0, size.width, 28);
    final bottom = Rect.fromLTWH(0, size.height - 28, size.width, 28);
    final left = Rect.fromLTWH(0, 0, 28, size.height);
    final right = Rect.fromLTWH(size.width - 28, 0, 28, size.height);
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x2B503514), Color(0x00503514)],
        ).createShader(top),
    );
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x2B503514), Color(0x00503514)],
        ).createShader(bottom),
    );
    canvas.drawRect(
      left,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x24503514), Color(0x00503514)],
        ).createShader(left),
    );
    canvas.drawRect(
      right,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0x24503514), Color(0x00503514)],
        ).createShader(right),
    );
  }

  /// 星图水印：弯月 + 四芒星 + 虚线连线（淡金，融入纸面）
  void _drawStarChart(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0x30A98B4F);
    // 弯月（左上）
    final moonC = Offset(size.width * 0.18, size.height * 0.14);
    final moon = Path()
      ..addOval(Rect.fromCircle(center: moonC, radius: 11))
      ..addOval(Rect.fromCircle(center: moonC.translate(4.5, -2), radius: 9.5));
    moon.fillType = PathFillType.evenOdd;
    canvas.drawPath(moon, ink);
    // 星座节点（归一化坐标，参考 04 的松散星图）
    const pts = [
      Offset(0.32, 0.30),
      Offset(0.52, 0.20),
      Offset(0.68, 0.38),
      Offset(0.46, 0.52),
      Offset(0.24, 0.62),
      Offset(0.62, 0.70),
      Offset(0.80, 0.58),
      Offset(0.82, 0.16),
    ];
    for (var i = 0; i < pts.length; i++) {
      final p = Offset(pts[i].dx * size.width, pts[i].dy * size.height);
      _fourPointStar(canvas, p, i.isEven ? 7.0 : 4.6, ink);
      if (i > 0) {
        final prev = Offset(
          pts[i - 1].dx * size.width,
          pts[i - 1].dy * size.height,
        );
        _dashedLine(canvas, prev, p, ink);
      }
    }
  }

  void _fourPointStar(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, stroke);
      d = end + gap;
    }
  }

  @override
  bool shouldRepaint(ParchmentPainter oldDelegate) => false;
}

/// 底部卷边（长卷下端卷起的织物 + 鎏金饰件）
class ScrollBottomCurl extends StatelessWidget {
  const ScrollBottomCurl({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: ScrollBottomCurlPainter());
  }
}

/// 绘制式底部卷边：压低高度，只画织物卷边和中央金饰，避免底部大截图
/// 把纸面挤没。
class ScrollBottomCurlPainter extends CustomPainter {
  const ScrollBottomCurlPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final roll = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.12,
        size.width * 0.86,
        size.height * 0.58,
      ),
      Radius.circular(size.height * 0.28),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.78),
        width: size.width * 0.72,
        height: size.height * 0.26,
      ),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(
      roll,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF24345C), Color(0xFF8B321E), Color(0xFF1A1125)],
        ).createShader(roll.outerRect),
    );
    canvas.drawRRect(
      roll,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xCCE4BE75),
    );
    _drawGoldEmblem(canvas, size);
    _drawEndCaps(canvas, size, roll.outerRect);
  }

  void _drawGoldEmblem(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.42);
    final path = Path()
      ..moveTo(c.dx, c.dy - 13)
      ..lineTo(c.dx + 18, c.dy)
      ..lineTo(c.dx, c.dy + 13)
      ..lineTo(c.dx - 18, c.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFE1A0), Color(0xFF855114)],
        ).createShader(Rect.fromCircle(center: c, radius: 22)),
    );
    canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF3A8CA7));
  }

  void _drawEndCaps(Canvas canvas, Size size, Rect roll) {
    final capPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5D3510), Color(0xFFFFD98B), Color(0xFF7A4717)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    for (final x in [roll.left, roll.right]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, roll.center.dy),
          width: size.height * 0.45,
          height: size.height * 0.62,
        ),
        capPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ScrollBottomCurlPainter oldDelegate) => false;
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
    // 轻装饰金线（R3：分隔纹不能强到像表格线——短跨度、半透明）
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
    // 中央菱形星饰（缩小、半透明，只作点缀）
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
    // 菱形两侧的小点
    final dot = Paint()..color = const Color(0x99C9A050);
    canvas.drawCircle(Offset(cx - 11, cy), 1.2, dot);
    canvas.drawCircle(Offset(cx + 11, cy), 1.2, dot);
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
  bool shouldRepaint(InkProgressPainter old) => old.t != t || old.glow != glow;
}

/// 墨迹条目在展开时间线上的淡入进度（写入感的近似：按序淡入）。
/// [unroll] 为主时间线 0~1；第 [index] 条从 0.58 起按序错峰。
double inkFadeT(double unroll, int index) {
  final start = math.min(0.58 + index * 0.05, 0.9);
  return ((unroll - start) / (1 - start)).clamp(0.0, 1.0);
}
