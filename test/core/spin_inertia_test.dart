import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/spin_inertia.dart';

/// 拖动转星球的惯性模型
void main() {
  test('拖动直接跟手：转角即时累加', () {
    final s = SpinInertia();
    s.dragBy(0.3, 0.1, 1 / 60);
    expect(s.yaw, closeTo(0.3, 1e-9));
    expect(s.pitch, closeTo(0.1, 1e-9));
  });

  test('甩手后惯性滑行，逐渐减速直至停止', () {
    final s = SpinInertia();
    // 连续几帧快速拖动 → 建立角速度
    for (var i = 0; i < 5; i++) {
      s.dragBy(0.05, 0, 1 / 60);
    }
    s.release();
    expect(s.gliding, isTrue, reason: '甩手应进入滑行');

    final yawAtRelease = s.yaw;
    var frames = 0;
    while (s.tick(1 / 60) && frames < 600) {
      frames++;
    }

    expect(s.gliding, isFalse, reason: '最终必须停下，不能永远滑');
    expect(s.yaw, greaterThan(yawAtRelease), reason: '松手后还会继续转一段');
    expect(frames, lessThan(300), reason: '滑行时长应在数秒内（5 秒 = 300 帧）');
  });

  test('慢速松手不滑行（低于停止阈值直接停）', () {
    final s = SpinInertia();
    s.dragBy(0.0001, 0, 1 / 60);
    s.release();
    expect(s.gliding, isFalse);
  });

  test('按下即抓住滑行中的星球', () {
    final s = SpinInertia();
    for (var i = 0; i < 5; i++) {
      s.dragBy(0.05, 0, 1 / 60);
    }
    s.release();
    expect(s.gliding, isTrue);

    s.grab();
    expect(s.gliding, isFalse, reason: '手指按下应立刻停住');
  });

  test('俯仰钳制在极点内，且顶到边界后不再顶着滑', () {
    final s = SpinInertia();
    for (var i = 0; i < 20; i++) {
      s.dragBy(0, 0.5, 1 / 60); // 一路往下转
    }
    expect(s.pitch, closeTo(s.maxPitch, 1e-9));
    expect(s.pitch, lessThan(math.pi / 2), reason: '不许翻过极点');

    s.release();
    var frames = 0;
    while (s.tick(1 / 60) && frames < 600) {
      frames++;
    }
    expect(s.pitch, closeTo(s.maxPitch, 1e-9), reason: '滑行不该把俯仰推出边界');
  });

  test('衰减与帧率无关：掉帧时滑行距离基本一致', () {
    double glideDistance(double dt) {
      final s = SpinInertia();
      for (var i = 0; i < 5; i++) {
        s.dragBy(0.05, 0, 1 / 60);
      }
      s.release();
      final start = s.yaw;
      var guard = 0;
      while (s.tick(dt) && guard < 5000) {
        guard++;
      }
      return s.yaw - start;
    }

    final at60 = glideDistance(1 / 60);
    final at30 = glideDistance(1 / 30); // 掉帧到 30fps
    expect((at60 - at30).abs() / at60, lessThan(0.12), reason: '掉帧不应显著改变滑行距离');
  });
}
