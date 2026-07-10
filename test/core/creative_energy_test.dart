import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/creative_energy.dart';

/// 创作能量映射的边界与单调性（设计定稿：零内容最暗/静止，封顶保底）
void main() {
  group('星空亮度 starBrightness', () {
    test('零内容取下限（最暗但可见）', () {
      expect(starBrightness(0), kStarBrightnessMin);
      expect(starBrightness(-5), kStarBrightnessMin, reason: '负数按零处理');
    });

    test('随创作量单调递增', () {
      expect(starBrightness(1), greaterThan(starBrightness(0)));
      expect(starBrightness(10), greaterThan(starBrightness(1)));
      expect(starBrightness(50), greaterThan(starBrightness(10)));
    });

    test('封顶：极大创作量不超过上限', () {
      expect(starBrightness(100000), lessThanOrEqualTo(kStarBrightnessMax));
    });
  });

  group('星球转速 planetSpin', () {
    test('零内容待机微转（2026-07-03 变更：静止像 bug）', () {
      expect(planetSpin(0), kPlanetSpinIdle);
      expect(planetSpin(0), lessThan(kPlanetSpinBase), reason: '待机应慢于创作起步');
    });

    test('一有创作即明显加速（不低于起点转速）', () {
      expect(planetSpin(1), greaterThanOrEqualTo(kPlanetSpinBase));
    });

    test('随创作量单调递增且封顶', () {
      expect(planetSpin(10), greaterThan(planetSpin(1)));
      expect(planetSpin(100000), lessThanOrEqualTo(kPlanetSpinMax));
    });
  });

  group('宇宙演化速度 nebulaEvolveSpeed（全局创作量驱动）', () {
    test('空宇宙冷寂缓慢（下限）', () {
      expect(nebulaEvolveSpeed(0), kNebulaEvolveMin);
      expect(nebulaEvolveSpeed(-3), kNebulaEvolveMin, reason: '防御负数');
    });

    test('随全局创作量单调加快且封顶（越写宇宙演变越快进）', () {
      expect(nebulaEvolveSpeed(20), greaterThan(nebulaEvolveSpeed(1)));
      expect(nebulaEvolveSpeed(200), greaterThan(nebulaEvolveSpeed(20)));
      expect(nebulaEvolveSpeed(1000000), lessThanOrEqualTo(kNebulaEvolveMax));
    });
  });
}
