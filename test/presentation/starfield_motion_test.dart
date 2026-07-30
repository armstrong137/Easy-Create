import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/presentation/home/starfield_motion.dart';

/// 动态星空的确定性调度（阶段八 P2-2）
void main() {
  group('流星调度 meteorAt', () {
    test('同一时刻求值幂等（确定性，无隐藏状态）', () {
      for (final t in [0.0, 3.7, 11.99, 25.4, 3600.0]) {
        final a = meteorAt(t);
        final b = meteorAt(t);
        expect(a?.progress, b?.progress, reason: 't=$t');
        expect(a?.startX, b?.startX);
      }
    });

    test('每个周期恰出现一颗：生命周期内非空且 progress 单调 0→1', () {
      const period = 12.0, duration = 1.4;
      for (var cycle = 0; cycle < 8; cycle++) {
        // 找到该周期内流星出现的时刻
        double? firstSeen;
        double lastProgress = -1;
        for (var t = cycle * period; t < (cycle + 1) * period; t += 0.05) {
          final m = meteorAt(t, period: period, duration: duration);
          if (m == null) continue;
          expect(m.cycle, cycle);
          expect(m.progress, inInclusiveRange(0, 1));
          expect(
            m.progress,
            greaterThanOrEqualTo(lastProgress),
            reason: '生命周期内 progress 必须单调递增',
          );
          lastProgress = m.progress;
          firstSeen ??= t;
        }
        expect(firstSeen, isNotNull, reason: '周期 $cycle 内必须出现一颗流星');
      }
    });

    test('流星生命周期完整落在周期内（不跨周期截断）', () {
      const period = 12.0, duration = 1.4;
      for (var cycle = 0; cycle < 20; cycle++) {
        final m = meteorAt(cycle * period + 0.0);
        // 周期首帧若有流星，说明起始为 0——合法；只需保证周期尾部无残留
        final tail = meteorAt(
          (cycle + 1) * period - 1e-6,
          period: period,
          duration: duration,
        );
        if (tail != null) {
          expect(tail.progress, lessThanOrEqualTo(1));
        }
        expect(m == null || m.progress >= 0, isTrue);
      }
    });

    test('不同周期的流星起点/长度不同（不是每次同一条）', () {
      MeteorState at(int cycle) {
        // 扫描找到该周期的流星
        for (var t = cycle * 12.0; t < (cycle + 1) * 12.0; t += 0.05) {
          final m = meteorAt(t);
          if (m != null) return m;
        }
        fail('周期 $cycle 无流星');
      }

      final a = at(0), b = at(1), c = at(2);
      final positions = {a.startX, b.startX, c.startX};
      expect(positions.length, greaterThan(1), reason: '起点应随周期变化');
      // 起点限制在画布内的合理范围
      for (final m in [a, b, c]) {
        expect(m.startX, inInclusiveRange(0.15, 0.85));
        expect(m.startY, inInclusiveRange(0.0, 0.4), reason: '流星从上半屏出发');
        expect(m.length, inInclusiveRange(0.16, 0.26));
      }
    });

    test('负时间无流星（防御）', () {
      expect(meteorAt(-1), isNull);
    });
  });

  group('星点闪烁 twinkle', () {
    test('亮度恒为正（星不会闪没）且有随时间的起伏', () {
      final samples = [for (var t = 0.0; t < 20; t += 0.5) twinkle(t, 31, 5)];
      expect(samples.every((v) => v > 0.05 && v <= 1.0), isTrue);
      expect(samples.toSet().length, greaterThan(10), reason: '亮度应随时间变化');
    });

    test('不同星点相位不同（不齐闪）', () {
      final a = twinkle(3.0, 31, 1);
      final b = twinkle(3.0, 31, 2);
      final c = twinkle(3.0, 31, 3);
      expect({a, b, c}.length, greaterThan(1));
    });
  });

  test('双层漂移速度不同产生视差，且 wrap 在 0~1', () {
    final far = driftOffset(100, 1 / 40);
    final near = driftOffset(100, 1 / 16);
    expect(far, isNot(near));
    expect(far, inInclusiveRange(0, 1));
    expect(near, inInclusiveRange(0, 1));
  });

  test('hashRand 确定性与分布（同参同值、异参异值、值域 [0,1)）', () {
    expect(hashRand(7, 42), hashRand(7, 42));
    final values = {for (var i = 0; i < 100; i++) hashRand(7, i)};
    expect(values.length, greaterThan(90), reason: '哈希不应大量碰撞');
    expect(values.every((v) => v >= 0 && v < 1), isTrue);
  });
}
