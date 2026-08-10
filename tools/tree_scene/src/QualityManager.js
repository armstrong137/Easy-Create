export class QualityManager {
  constructor({ devicePixelRatio = 1, hardwareConcurrency = 4 } = {}) {
    this.devicePixelRatio = devicePixelRatio;
    this.hardwareConcurrency = hardwareConcurrency;
  }

  initialProfile() {
    if (this.hardwareConcurrency <= 4) {
      return { name: 'low', pixelRatio: 1, shadows: false, antialias: false };
    }
    if (this.hardwareConcurrency <= 8) {
      return {
        name: 'medium',
        pixelRatio: Math.min(this.devicePixelRatio, 1.5),
        shadows: true,
        antialias: true,
      };
    }
    return {
      name: 'high',
      pixelRatio: Math.min(this.devicePixelRatio, 2),
      shadows: true,
      antialias: true,
    };
  }
}
