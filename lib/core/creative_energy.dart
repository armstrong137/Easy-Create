/// 创作能量映射：把"当前小说的灵感数 + 章节数"换算成
/// 星空亮度与星球转速（设计定稿：零内容最暗/静止，越多越亮/越快，封顶保底）
///
/// 曲线选型（假设，阶段七调优终审）：指数饱和 1 - e^(-n/τ)，
/// 前几条灵感增益明显（正反馈强），越往后越平缓，天然封顶。
library;

import 'dart:math' as math;

/// 星空亮度下限（零内容时的最暗值，仍保留可见星光）
const double kStarBrightnessMin = 0.25;

/// 星空亮度上限（设计要求"不能太亮"）
const double kStarBrightnessMax = 0.85;

/// 亮度饱和常数：约 20 条创作量到达上限的 63%
const double _brightnessTau = 20;

/// 星球转速上限（圈/秒）：约 8 秒一圈，肉眼可见但不晕
const double kPlanetSpinMax = 0.12;

/// 有内容时的转速起点（圈/秒）：一有创作即开始缓转
const double kPlanetSpinBase = 0.02;

/// 转速饱和常数：约 30 条创作量到达上限的 63%
const double _spinTau = 30;

/// 创作量 [count]（灵感数+章节数）→ 星空亮度 [kStarBrightnessMin, kStarBrightnessMax]
double starBrightness(int count) {
  if (count <= 0) return kStarBrightnessMin;
  final t = 1 - math.exp(-count / _brightnessTau);
  return kStarBrightnessMin + (kStarBrightnessMax - kStarBrightnessMin) * t;
}

/// 创作量 [count] → 星球转速（圈/秒）；零内容严格静止
double planetSpin(int count) {
  if (count <= 0) return 0;
  final t = 1 - math.exp(-count / _spinTau);
  return kPlanetSpinBase + (kPlanetSpinMax - kPlanetSpinBase) * t;
}
