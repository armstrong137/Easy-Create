import 'dart:async';

import 'package:flutter/material.dart';

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
  });

  final String title;
  final IllustratedBranchSide side;
  final bool selected;
  final bool animateIn;

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
        return ClipRect(
          clipper: _BranchGrowthClipper(progress: progress, side: widget.side),
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
                Positioned(
                  left: widget.side == IllustratedBranchSide.left
                      ? constraints.maxWidth * 0.12
                      : null,
                  right: widget.side == IllustratedBranchSide.right
                      ? constraints.maxWidth * 0.12
                      : null,
                  top: constraints.maxHeight * 0.23,
                  width: constraints.maxWidth * 0.21,
                  height: constraints.maxHeight * 0.45,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('选中枝牌光晕'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFE9BC54),
                          width: 1.6,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x8CF2B632),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: widget.side == IllustratedBranchSide.left
                    ? constraints.maxWidth * 0.12
                    : null,
                right: widget.side == IllustratedBranchSide.right
                    ? constraints.maxWidth * 0.12
                    : null,
                top: constraints.maxHeight * 0.23,
                width: constraints.maxWidth * 0.21,
                height: constraints.maxHeight * 0.45,
                child: FittedBox(
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
          ),
        );
      },
    ),
  );
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
