import 'package:flutter/material.dart';

import 'illustrated_tree_growth.dart';

/// 重画同源主干的前景轮廓，让枝基位于树皮后；不新增位图或羽化接缝。
class IllustratedTreeTrunk extends StatelessWidget {
  const IllustratedTreeTrunk({
    super.key,
    required this.stage,
    this.completeCrown = false,
  });

  final int stage;
  final bool completeCrown;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: ClipPath(
        clipper: IllustratedTreeTrunkClipper(
          stage: stage,
          completeCrown: completeCrown,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Image.asset(
            completeCrown && stage == 5
                ? 'assets/tree_scene/illustrated/mature_complete.png'
                : illustratedTreeAssetForStage(stage),
            key: ValueKey((stage, completeCrown)),
            width: double.infinity,
            height: double.infinity,
            fit: constraints.maxWidth / constraints.maxHeight > 0.85
                ? BoxFit.contain
                : BoxFit.cover,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
      ),
    ),
  );
}

class IllustratedTreeTrunkClipper extends CustomClipper<Path> {
  const IllustratedTreeTrunkClipper({
    required this.stage,
    this.completeCrown = false,
  });

  final int stage;
  final bool completeCrown;

  @override
  Path getClip(Size size) {
    // 按 941×1672 母版主干内侧描边；不把叶丛或米白背景包含进遮挡区。
    final points = switch (stage) {
      1 => <Offset>[
        Offset(477, 1040),
        Offset(469, 1100),
        Offset(451, 1170),
        Offset(446, 1250),
        Offset(432, 1330),
        Offset(420, 1390),
        Offset(399, 1440),
        Offset(550, 1440),
        Offset(524, 1380),
        Offset(515, 1300),
        Offset(501, 1230),
        Offset(505, 1150),
        Offset(498, 1100),
        Offset(492, 1040),
      ],
      2 => <Offset>[
        Offset(481, 730),
        Offset(467, 850),
        Offset(450, 930),
        Offset(437, 1010),
        Offset(420, 1090),
        Offset(419, 1170),
        Offset(390, 1280),
        Offset(350, 1330),
        Offset(573, 1330),
        Offset(536, 1250),
        Offset(513, 1170),
        Offset(512, 1090),
        Offset(512, 1000),
        Offset(508, 910),
        Offset(501, 820),
        Offset(496, 730),
      ],
      3 => <Offset>[
        Offset(448, 580),
        Offset(399, 710),
        Offset(402, 790),
        Offset(386, 850),
        Offset(389, 940),
        Offset(365, 1040),
        Offset(340, 1150),
        Offset(310, 1270),
        Offset(270, 1400),
        Offset(669, 1400),
        Offset(603, 1260),
        Offset(568, 1140),
        Offset(550, 1050),
        Offset(553, 970),
        Offset(551, 870),
        Offset(537, 780),
        Offset(515, 700),
        Offset(483, 580),
      ],
      4 => <Offset>[
        Offset(402, 0),
        Offset(435, 130),
        Offset(448, 240),
        Offset(414, 350),
        Offset(385, 480),
        Offset(397, 600),
        Offset(390, 740),
        Offset(366, 870),
        Offset(358, 1030),
        Offset(328, 1160),
        Offset(300, 1320),
        Offset(678, 1320),
        Offset(607, 1160),
        Offset(576, 1040),
        Offset(590, 900),
        Offset(590, 760),
        Offset(595, 630),
        Offset(568, 470),
        Offset(592, 310),
        Offset(607, 140),
        Offset(630, 0),
      ],
      5 when completeCrown => <Offset>[
        Offset(450, 360),
        Offset(433, 540),
        Offset(421, 710),
        Offset(416, 920),
        Offset(397, 1110),
        Offset(380, 1290),
        Offset(325, 1410),
        Offset(656, 1410),
        Offset(565, 1290),
        Offset(550, 1090),
        Offset(535, 910),
        Offset(522, 720),
        Offset(510, 530),
        Offset(477, 360),
      ],
      5 => <Offset>[
        Offset(360, 0),
        Offset(374, 120),
        Offset(372, 250),
        Offset(391, 390),
        Offset(397, 510),
        Offset(376, 630),
        Offset(386, 780),
        Offset(384, 910),
        Offset(359, 1050),
        Offset(357, 1170),
        Offset(327, 1320),
        Offset(655, 1320),
        Offset(607, 1170),
        Offset(616, 1030),
        Offset(642, 880),
        Offset(647, 730),
        Offset(637, 590),
        Offset(642, 460),
        Offset(626, 320),
        Offset(611, 170),
        Offset(611, 0),
      ],
      _ => <Offset>[],
    };
    if (points.isEmpty) return Path();
    const sourceSize = Size(941, 1672);
    final fit = size.aspectRatio > 0.85 ? BoxFit.contain : BoxFit.cover;
    final fitted = applyBoxFit(fit, sourceSize, size);
    final source = Alignment.bottomCenter.inscribe(
      fitted.source,
      Offset.zero & sourceSize,
    );
    final target = Alignment.bottomCenter.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    Offset map(Offset p) => Offset(
      target.left + (p.dx - source.left) * target.width / source.width,
      target.top + (p.dy - source.top) * target.height / source.height,
    );
    return Path()..addPolygon(points.map(map).toList(), true);
  }

  @override
  bool shouldReclip(IllustratedTreeTrunkClipper oldClipper) =>
      oldClipper.stage != stage || oldClipper.completeCrown != completeCrown;
}
