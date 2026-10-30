import 'dart:async';

import 'package:flutter/material.dart';
import 'organic_branch.dart';

export 'illustrated_tree_growth.dart';

enum IllustratedBranchSide { left, right }

const illustratedBranchAsset =
    'assets/tree_scene/illustrated/chapter_branch.png';

class IllustratedBranchPlaque extends StatefulWidget {
  const IllustratedBranchPlaque({
    super.key,
    required this.title,
    required this.side,
    required this.selected,
    required this.animateIn,
    this.organicGrowth = false,
    this.maxSupportRadius,
  });

  final String title;
  final IllustratedBranchSide side;
  final bool selected;
  final bool animateIn;
  final bool organicGrowth;
  final double? maxSupportRadius;

  @override
  State<IllustratedBranchPlaque> createState() =>
      _IllustratedBranchPlaqueState();
}

class _IllustratedBranchPlaqueState extends State<IllustratedBranchPlaque>
    with SingleTickerProviderStateMixin {
  late final AnimationController _growth;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _growth = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
      value: widget.animateIn ? 0 : 1,
    );
    if (widget.animateIn) _startGrowth();
  }

  @override
  void didUpdateWidget(IllustratedBranchPlaque oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateIn && !oldWidget.animateIn) {
      _growth.value = 0;
      _startGrowth();
    }
  }

  void _startGrowth() {
    _delay?.cancel();
    _delay = Timer(const Duration(milliseconds: 240), () {
      if (mounted) _growth.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _growth.dispose();
    super.dispose();
  }

  String get _verticalTitle =>
      widget.title.runes.map(String.fromCharCode).take(6).join('\n');

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _growth,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(_growth.value);
        final frameProgress = ((progress - .72) / .28).clamp(0.0, 1.0);
        return Stack(fit: StackFit.expand, children: [
          if (widget.organicGrowth)
            OrganicBranch(progress: progress, right: widget.side == IllustratedBranchSide.right, maxRootRadius: widget.maxSupportRadius),
          ClipRect(
          clipper: widget.organicGrowth
              ? _PlaqueFrameClipper(widget.side)
              : _BranchGrowthClipper(progress: progress, side: widget.side),
          child: Opacity(opacity: widget.organicGrowth ? frameProgress : 1,
            child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.flip(
                  flipX: widget.side == IllustratedBranchSide.right,
                  child: Image.asset(
                    illustratedBranchAsset,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              if (widget.selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.flip(
                      flipX: widget.side == IllustratedBranchSide.right,
                      child: const CustomPaint(
                        key: Key('选中枝牌光晕'),
                        painter: _PlaqueRimPainter(),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: widget.side == IllustratedBranchSide.left
                    ? constraints.maxWidth * 246 / 1536
                    : null,
                right: widget.side == IllustratedBranchSide.right
                    ? constraints.maxWidth * 246 / 1536
                    : null,
                top: constraints.maxHeight * 268 / 1024,
                width: constraints.maxWidth * 148 / 1536,
                height: constraints.maxHeight * 400 / 1024,
                child: FittedBox(
                  key: const Key('枝牌文字区'),
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _verticalTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'LXGWWenKai',
                      fontSize: widget.side == IllustratedBranchSide.left
                          ? 28
                          : 24,
                      height: 1.02,
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: const Color(0xFF2D2013),
                      shadows: const [
                        Shadow(
                          color: Color(0x66F9E4B8),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )),
        )]);
      },
    ),
  );
}

class _PlaqueFrameClipper extends CustomClipper<Rect> {
  const _PlaqueFrameClipper(this.side);
  final IllustratedBranchSide side;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    side == IllustratedBranchSide.left ? 0 : size.width * .64,
    0, size.width * .36, size.height,
  );

  @override
  bool shouldReclip(_PlaqueFrameClipper oldClipper) => oldClipper.side != side;
}

class _PlaqueRimPainter extends CustomPainter {
  const _PlaqueRimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 沿原图 1536×1024 的弧肩金边描亮，不在木牌上叠加矩形控件。
    final rim = Path()
      ..moveTo(320, 241)
      ..lineTo(269, 251)
      ..cubicTo(263, 272, 246, 288, 220, 294)
      ..lineTo(220, 637)
      ..cubicTo(244, 645, 260, 660, 269, 680)
      ..lineTo(320, 691)
      ..lineTo(377, 680)
      ..cubicTo(381, 661, 394, 647, 420, 641)
      ..lineTo(420, 295)
      ..cubicTo(399, 288, 382, 271, 376, 252)
      ..close();
    canvas.save();
    canvas.scale(size.width / 1536, size.height / 1024);
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = const Color(0xA8EAB94B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFF8D887),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlaqueRimPainter oldDelegate) => false;
}

class _BranchGrowthClipper extends CustomClipper<Rect> {
  const _BranchGrowthClipper({required this.progress, required this.side});

  final double progress;
  final IllustratedBranchSide side;

  @override
  Rect getClip(Size size) => side == IllustratedBranchSide.left
      ? Rect.fromLTRB(size.width * (1 - progress), 0, size.width, size.height)
      : Rect.fromLTRB(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_BranchGrowthClipper oldClipper) =>
      progress != oldClipper.progress || side != oldClipper.side;
}
