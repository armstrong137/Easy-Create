const AGE_STOPS = Object.freeze([
  ['age_00', 0.08],
  ['age_25', 0.25],
  ['age_48', 0.48],
  ['age_72', 0.72],
  ['age_100', 1],
]);

function clampAge(age) {
  return Math.min(1, Math.max(0, Number.isFinite(age) ? age : 0));
}

function smoothStep(value) {
  return value * value * (3 - 2 * value);
}

export class TreeGrowthSystem {
  constructor({ root, morphChannels = [], mixer = null }) {
    this.root = root;
    this.morphChannels = morphChannels;
    this.mixer = mixer;
    this.age = 0.08;
    this.targetAge = this.age;
    this.phase = 'idle';
    this.elapsed = 0;
    this.duration = 0;
    this.progress = 1;
    this.progressWaiters = [];
    this.startAge = this.age;
    this.pending = null;
    this.applyAge(this.age);
  }

  setAge(age, { animate = true, durationMs = 900 } = {}) {
    const target = clampAge(age);
    this.finishPending();
    this.targetAge = target;

    if (!animate || durationMs <= 0 || Math.abs(target - this.age) < 1e-6) {
      this.age = target;
      this.phase = 'idle';
      this.progress = 1;
      this.applyAge(target);
      this.finishProgressWaiters(true);
      return Promise.resolve();
    }

    this.startAge = this.age;
    this.elapsed = 0;
    this.duration = durationMs / 1000;
    this.progress = 0;
    this.phase = target > this.age ? 'growing' : 'shrinking';
    return new Promise((resolve) => {
      this.pending = resolve;
    });
  }

  update(dt) {
    const delta = Math.max(0, Number.isFinite(dt) ? dt : 0);
    this.mixer?.update(delta);
    if (this.phase === 'idle') return;

    this.elapsed += delta;
    const progress = Math.min(1, this.elapsed / this.duration);
    this.progress = progress;
    this.finishProgressWaiters();
    const eased = smoothStep(progress);
    this.age = this.startAge + (this.targetAge - this.startAge) * eased;
    this.applyAge(this.age);
    if (progress >= 1) {
      this.age = this.targetAge;
      this.phase = 'idle';
      this.applyAge(this.age);
      this.finishPending();
    }
  }

  getState() {
    return {
      age: this.age,
      targetAge: this.targetAge,
      phase: this.phase,
      progress: this.progress,
    };
  }

  waitForProgress(minimum = 0.08) {
    const threshold = Math.min(1, Math.max(0, minimum));
    if (this.phase === 'idle' || this.progress >= threshold) {
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      this.progressWaiters.push({ threshold, resolve });
    });
  }

  applyAge(age) {
    const weights = this.weightsForAge(clampAge(age));
    for (const channel of this.morphChannels) {
      const dictionary = channel.morphTargetDictionary ?? {};
      const influences = channel.morphTargetInfluences ?? [];
      for (const [name] of AGE_STOPS) {
        const index = dictionary[name];
        if (index !== undefined) influences[index] = weights.get(name) ?? 0;
      }
    }
  }

  weightsForAge(age) {
    if (age <= AGE_STOPS[0][1]) return new Map([[AGE_STOPS[0][0], 1]]);
    const last = AGE_STOPS.at(-1);
    if (age >= last[1]) return new Map([[last[0], 1]]);

    for (let index = 0; index < AGE_STOPS.length - 1; index += 1) {
      const [lowerName, lowerAge] = AGE_STOPS[index];
      const [upperName, upperAge] = AGE_STOPS[index + 1];
      if (age <= upperAge) {
        const mix = (age - lowerAge) / (upperAge - lowerAge);
        return new Map([
          [lowerName, 1 - mix],
          [upperName, mix],
        ]);
      }
    }
    return new Map([[last[0], 1]]);
  }

  finishPending() {
    const resolve = this.pending;
    this.pending = null;
    resolve?.();
    this.finishProgressWaiters(true);
  }

  finishProgressWaiters(force = false) {
    const remaining = [];
    for (const waiter of this.progressWaiters) {
      if (force || this.progress >= waiter.threshold) waiter.resolve();
      else remaining.push(waiter);
    }
    this.progressWaiters = remaining;
  }
}
