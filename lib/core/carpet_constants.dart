/// 灵感魔毯尺寸常量（claude.md 约定放 core；配色已随照片素材版魔毯退役）
library;

/// 缩球直径（照片版卷球，需要在右上角有明确存在感）
const double kCarpetBallSize = 92;

/// 展开面板列表区最小/最大高度（定稿：高度随灵感数伸缩，有上下限）
const double kCarpetMinHeight = 180;
const double kCarpetMaxHeight = 420;

/// 每条灵感的固定卡槽高（作 ListView itemExtent：两行预览 + 卡间距）
const double kCarpetItemHeight = 68;

/// 列表顶部内边距 / 上下内边距合计（与 ListView padding 上 2 + 下 12 一致）
const double kCarpetListTopPad = 2;
const double kCarpetListPad = 14;

/// 展开面板列表区高度 = f(灵感数, 可用空间)：只取**整数个卡槽**，
/// 灵感卡要么完整显示要么不显示，显示不下的滑动阅读（用户定稿）。
/// [maxAvail] 传屏幕剩余空间：面板绝不伸出屏幕底，否则末尾卡片被屏幕截断、
/// 滑也滑不出来。
double carpetHeight(int count, {double maxAvail = kCarpetMaxHeight}) {
  final cap = maxAvail.clamp(kCarpetMinHeight, kCarpetMaxHeight);
  final slots = ((cap - kCarpetListTopPad) / kCarpetItemHeight).floor();
  if (count <= slots) {
    // 全部装得下：含上下内边距，保底（空毯邀请文案区）
    return (count * kCarpetItemHeight + kCarpetListPad).clamp(
      kCarpetMinHeight,
      kCarpetMaxHeight,
    );
  }
  // 溢出：视口只含顶部内边距 → 静止时恰好 slots 张整卡，
  // 不会在底缘透出下一张卡的边（底部内边距滚到末尾才出现）
  return slots * kCarpetItemHeight + kCarpetListTopPad;
}
