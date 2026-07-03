/// 灵感魔毯尺寸与配色常量（claude.md 约定放 core）
library;

import 'package:flutter/painting.dart';

/// 缩球直径
const double kCarpetBallSize = 56;

/// 展开面板最小/最大高度（定稿：高度随灵感数伸缩，有上下限）
const double kCarpetMinHeight = 140;
const double kCarpetMaxHeight = 340;

/// 每条灵感贡献的高度（约一行条目）
const double kCarpetItemHeight = 48;

/// 展开面板高度 = f(灵感数)，封顶保底
double carpetHeight(int count) =>
    (kCarpetMinHeight + count * kCarpetItemHeight)
        .clamp(kCarpetMinHeight, kCarpetMaxHeight);

/// 阿拉丁魔毯配色：深红绒面 + 金色织边 + 紫夜点缀
const kCarpetDeepRed = Color(0xFF7B1E2B);
const kCarpetDarkRed = Color(0xFF4A1018);
const kCarpetGold = Color(0xFFE9B84C);
const kCarpetPurple = Color(0xFF3D2459);
