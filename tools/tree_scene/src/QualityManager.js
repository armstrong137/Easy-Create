export class QualityManager {
  constructor({ devicePixelRatio = 1, hardwareConcurrency = 4 } = {}) {
    this.devicePixelRatio = devicePixelRatio;
    this.hardwareConcurrency = hardwareConcurrency;
    this.baseProfile = this.initialProfile();
    this.currentProfile = this.baseProfile;
    this.interactionStartedAt = null;
  }

  initialProfile() {
    if (this.hardwareConcurrency <= 4) {
      return profile('low', 1, 1000, 40, false, false, 70000, 35);
    }
    if (this.hardwareConcurrency <= 8) {
      return profile(
        'medium',
        Math.min(this.devicePixelRatio, 1.5),
        2200,
        64,
        true,
        true,
        140000,
        55,
      );
    }
    return profile(
      'high',
      Math.min(this.devicePixelRatio, 2),
      4000,
      96,
      true,
      true,
      250000,
      80,
    );
  }

  select(name) {
    const profiles = {
      high: profile('high', Math.min(this.devicePixelRatio, 2), 4000, 96, true, true, 250000, 80),
      medium: profile('medium', Math.min(this.devicePixelRatio, 1.5), 2200, 64, true, true, 140000, 55),
      low: profile('low', 1, 1000, 40, false, false, 70000, 35),
      static: profile('static', 1, 0, 0, false, false, 0, 0),
    };
    this.baseProfile = profiles[name] ?? this.baseProfile;
    this.currentProfile = this.baseProfile;
    return this.currentProfile;
  }

  beginInteraction(now = 0) {
    this.interactionStartedAt = now;
    this.currentProfile = {
      ...this.baseProfile,
      name: 'interactive',
      pixelRatio: Math.min(1, this.baseProfile.pixelRatio),
      shadows: false,
    };
    return this.currentProfile;
  }

  settleInteraction(elapsedMs) {
    if (this.currentProfile.name !== 'interactive' || elapsedMs < 500) {
      return this.currentProfile;
    }
    this.interactionStartedAt = null;
    this.currentProfile = this.baseProfile;
    return this.currentProfile;
  }
}

function profile(name, pixelRatio, leafInstances, textureBudgetMiB, shadows, antialias, triangles, drawCalls) {
  return {
    name,
    pixelRatio,
    leafInstances,
    textureBudgetMiB,
    shadows,
    antialias,
    triangles,
    drawCalls,
    particles: name === 'high',
  };
}

export class ProjectionReporter {
  constructor() {
    this.signature = null;
  }

  shouldEmit(labels) {
    const signature = JSON.stringify(labels);
    if (signature === this.signature) return false;
    this.signature = signature;
    return true;
  }

  reset() {
    this.signature = null;
  }
}
