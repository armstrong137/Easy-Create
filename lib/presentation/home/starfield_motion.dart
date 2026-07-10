import 'dart:math' as math;

/// 动态星空的确定性调度（纯逻辑，无 Widget 依赖，便于单测）
///
/// 所有随机都由（种子, 序号）哈希派生：同一时刻求值结果幂等，
/// 测试可复现，两台设备表现一致。

/// 确定性伪随机 [0,1)：整数哈希（xorshift 混合），与调用顺序无关
double hashRand(int seed, int index) {
  var x = seed * 0x9E3779B1 + index * 0x85EBCA6B;
  x = (x ^ (x >> 16)) * 0x45D9F3B;
  x = (x ^ (x >> 16)) * 0x45D9F3B;
  x = x ^ (x >> 16);
  return (x & 0xFFFFFF) / 0x1000000;
}

/// 一颗流星的瞬时状态
class MeteorState {
  const MeteorState({
    required this.progress,
    required this.cycle,
    required this.startX,
    required this.startY,
    required this.length,
  });

  /// 生命周期进度 0→1（划过与淡出都由它驱动）
  final double progress;

  /// 第几个调度周期（决定这颗流星的起点/长度）
  final int cycle;

  /// 起点（相对画布宽高的 0~1 比例；y 限制在上半屏，流星从高处划落）
  final double startX;
  final double startY;

  /// 划痕长度（相对画布宽的比例）
  final double length;
}

/// 流星调度：把时间轴切成 [period] 秒的周期，每周期在随机时刻出现一颗，
/// 持续 [duration] 秒。O(1) 求值，不随运行时长变慢。
MeteorState? meteorAt(
  double elapsedSeconds, {
  double period = 12,
  double duration = 1.4,
  int seed = 7,
}) {
  if (elapsedSeconds < 0) return null;
  final cycle = elapsedSeconds ~/ period;
  // 本周期内流星的起始时刻（保证完整生命周期落在周期内）
  final start = hashRand(seed, cycle) * (period - duration);
  final local = elapsedSeconds - cycle * period - start;
  if (local < 0 || local > duration) return null;
  return MeteorState(
    progress: local / duration,
    cycle: cycle,
    startX: 0.15 + hashRand(seed + 1, cycle) * 0.7,
    startY: hashRand(seed + 2, cycle) * 0.4,
    length: 0.16 + hashRand(seed + 3, cycle) * 0.10,
  );
}

/// 星点闪烁亮度 0~1：各自相位与周期的呼吸曲线（恒为正，不会闪没）
double twinkle(double elapsedSeconds, int seed, int index) {
  final phase = hashRand(seed, index) * 2 * math.pi;
  final speed = 0.5 + hashRand(seed + 1, index) * 1.1; // 0.5~1.6 rad/s
  return 0.55 + 0.45 * math.sin(elapsedSeconds * speed + phase);
}

/// 层漂移偏移（0~1 wrap）：远近两层速度不同产生视差
double driftOffset(double elapsedSeconds, double speedPerSecond) =>
    (elapsedSeconds * speedPerSecond) % 1.0;
