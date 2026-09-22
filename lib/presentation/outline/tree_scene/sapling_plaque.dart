import 'package:flutter/material.dart';

/// 一体化幼树图的牌面和点击区域，随底图使用相同取景。
Rect saplingPlaqueRect(Size size) {
  const sourceSize = Size(941, 1672);
  final fit = size.aspectRatio > .85 ? BoxFit.contain : BoxFit.cover;
  final fitted = applyBoxFit(fit, sourceSize, size);
  final source = Alignment.bottomCenter.inscribe(
    fitted.source,
    Offset.zero & sourceSize,
  );
  final target = Alignment.bottomCenter.inscribe(
    fitted.destination,
    Offset.zero & size,
  );
  final scale = target.width / source.width;
  return Rect.fromLTWH(
    target.left + (180 - source.left) * scale,
    target.top + (940 - source.top) * scale,
    112 * scale,
    165 * scale,
  );
}

/// 枝与牌已绘在底图中，只绘制可编辑标题，不再覆盖另一块枝牌贴图。
class SaplingPlaqueTitle extends StatelessWidget {
  const SaplingPlaqueTitle({
    super.key,
    required this.title,
    required this.selected,
  });
  final String title;
  final bool selected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: EdgeInsets.fromLTRB(
        constraints.maxWidth * .23,
        constraints.maxHeight * .19,
        constraints.maxWidth * .22,
        constraints.maxHeight * .16,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          title.runes.map(String.fromCharCode).take(6).join('\n'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'LXGWWenKai',
            fontSize: 26,
            height: 1.02,
            color: const Color(0xFF2D2013),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
