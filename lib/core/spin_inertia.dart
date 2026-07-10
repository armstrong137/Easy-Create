import 'dart:math' as math;

/// 拖动转星球的惯性模型（纯逻辑，与 Widget 无关，便于单测）
///
/// 手感设计：
/// - 拖动中直接跟手，同时估计角速度（指数平滑，抹掉单帧抖动）
/// - 松手后按指数摩擦衰减滑行，低于阈值即停
/// - 俯仰角钳制在极点之内；一旦顶到边界，该方向速度清零（不再"顶着墙滑"）
class SpinInertia {
  SpinInertia({
    this.maxPitch = math.pi / 2 * 0.92,
    this.friction = 2.6,
    this.stopSpeed = 0.02,
  });

  /// 俯仰上限（弧度）：别转到极点翻面
  final double maxPitch;

  /// 指数摩擦系数：越大停得越快（2.6 ≈ 滑行 1.5 秒）
  final double friction;

  /// 停止阈值（弧度/秒）：低于它就归零，避免永远抖动
  final double stopSpeed;

  double yaw = 0;
  double pitch = 0;

  double _vYaw = 0;
  double _vPitch = 0;

  /// 是否还在惯性滑行
  bool get gliding => _vYaw != 0 || _vPitch != 0;

  /// 拖动中：直接应用转角，并估计角速度（[dt] 秒）
  void dragBy(double dYaw, double dPitch, double dt) {
    yaw += dYaw;
    _setPitch(pitch + dPitch);
    if (dt <= 0 || dt > 0.1) return; // 异常时间间隔不参与测速
    // 指数平滑：新样本占 6 成，既跟手又不被单帧尖峰带偏
    _vYaw = _vYaw * 0.4 + (dYaw / dt) * 0.6;
    _vPitch = _vPitch * 0.4 + (dPitch / dt) * 0.6;
  }

  /// 手指按下：立刻停住滑行（抓住转动中的星球）
  void grab() {
    _vYaw = 0;
    _vPitch = 0;
  }

  /// 松手：慢到一定程度就不滑了
  void release() {
    if (_vYaw.abs() < stopSpeed) _vYaw = 0;
    if (_vPitch.abs() < stopSpeed) _vPitch = 0;
  }

  /// 推进惯性一帧（[dt] 秒），返回是否仍在滑行
  bool tick(double dt) {
    if (!gliding) return false;
    yaw += _vYaw * dt;
    _setPitch(pitch + _vPitch * dt);
    // 指数衰减：与帧率无关，掉帧时也不会突然滑更远
    final decay = math.exp(-friction * dt);
    _vYaw *= decay;
    _vPitch *= decay;
    release();
    return gliding;
  }

  void _setPitch(double next) {
    final clamped = next.clamp(-maxPitch, maxPitch);
    // 顶到极点：该方向速度清零，不再顶着边界空转
    if (clamped != next) _vPitch = 0;
    pitch = clamped;
  }
}
