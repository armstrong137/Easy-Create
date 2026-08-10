function easeInOutCubic(value) {
  return value < 0.5 ? 4 * value ** 3 : 1 - (-2 * value + 2) ** 3 / 2;
}

export class SceneTimeline {
  constructor() {
    this.tweens = new Set();
  }

  tween({ durationMs, onUpdate }) {
    return new Promise((resolve) => {
      const tween = {
        duration: Math.max(1, durationMs) / 1000,
        elapsed: 0,
        onUpdate,
        resolve,
      };
      this.tweens.add(tween);
      onUpdate(0);
    });
  }

  update(dt) {
    for (const tween of [...this.tweens]) {
      tween.elapsed += Math.max(0, dt);
      const progress = Math.min(1, tween.elapsed / tween.duration);
      tween.onUpdate(easeInOutCubic(progress));
      if (progress < 1) continue;
      this.tweens.delete(tween);
      tween.resolve();
    }
  }
}
