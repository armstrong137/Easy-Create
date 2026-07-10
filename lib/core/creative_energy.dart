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

/// 待机微转（圈/秒）：零创作也缓缓转动（约 2 分钟一圈）
/// —— 2026-07-03 用户反馈"星球不转像坏了"，静止改为待机微转
const double kPlanetSpinIdle = 0.008;

/// 转速饱和常数：约 30 条创作量到达上限的 63%
const double _spinTau = 30;

/// 创作量 [count]（灵感数+章节数）→ 星空亮度 [kStarBrightnessMin, kStarBrightnessMax]
double starBrightness(int count) {
  if (count <= 0) return kStarBrightnessMin;
  final t = 1 - math.exp(-count / _brightnessTau);
  return kStarBrightnessMin + (kStarBrightnessMax - kStarBrightnessMin) * t;
}

/// 创作量 [count] → 星球转速（圈/秒）；零内容待机微转，越创作越快
double planetSpin(int count) {
  if (count <= 0) return kPlanetSpinIdle;
  final t = 1 - math.exp(-count / _spinTau);
  return kPlanetSpinBase + (kPlanetSpinMax - kPlanetSpinBase) * t;
}

/// 宇宙演化速度下限（空宇宙：冷寂缓慢）
const double kNebulaEvolveMin = 0.6;

/// 宇宙演化速度上限（创作旺盛：宇宙演变"快进"，但不喧闹）
const double kNebulaEvolveMax = 2.4;

/// 演化饱和常数：约 60 条全局创作量到达上限的 63%
const double _evolveTau = 60;

/// 全局创作量 [count]（**所有星球**的章数+节数+灵感总数）→ 星云演化速度倍率
///
/// 用户定稿（2026-07-10）：宇宙背景的演变快慢与全库创作量正相关——
/// 写得越多，宇宙演化越"快进"。
double nebulaEvolveSpeed(int count) {
  if (count <= 0) return kNebulaEvolveMin;
  final t = 1 - math.exp(-count / _evolveTau);
  return kNebulaEvolveMin + (kNebulaEvolveMax - kNebulaEvolveMin) * t;
}
