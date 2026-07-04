/// 灵感魔毯尺寸常量（claude.md 约定放 core；配色已随照片素材版魔毯退役）
library;

/// 缩球直径（照片版卷球，需要在右上角有明确存在感）
const double kCarpetBallSize = 92;

/// 展开面板最小/最大高度（定稿：高度随灵感数伸缩，有上下限）
const double kCarpetMinHeight = 180;
const double kCarpetMaxHeight = 420;

/// 每条灵感贡献的高度（约一行条目）
const double kCarpetItemHeight = 54;

/// 展开面板高度 = f(灵感数)，封顶保底
double carpetHeight(int count) => (kCarpetMinHeight + count * kCarpetItemHeight)
    .clamp(kCarpetMinHeight, kCarpetMaxHeight);
