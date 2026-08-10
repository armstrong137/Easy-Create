import assert from 'node:assert/strict';
import test from 'node:test';

import { ProjectionReporter, QualityManager } from '../src/QualityManager.js';

test('质量档位包含明确的渲染预算', () => {
  const high = new QualityManager({
    devicePixelRatio: 3,
    hardwareConcurrency: 12,
  }).initialProfile();
  const medium = new QualityManager({
    devicePixelRatio: 3,
    hardwareConcurrency: 8,
  }).initialProfile();
  const low = new QualityManager({
    devicePixelRatio: 3,
    hardwareConcurrency: 4,
  }).initialProfile();

  assert.deepEqual(
    [high.name, high.pixelRatio, high.leafInstances, high.textureBudgetMiB],
    ['high', 2, 4000, 96],
  );
  assert.deepEqual(
    [medium.name, medium.pixelRatio, medium.leafInstances, medium.textureBudgetMiB],
    ['medium', 1.5, 2200, 64],
  );
  assert.deepEqual(
    [low.name, low.pixelRatio, low.leafInstances, low.textureBudgetMiB],
    ['low', 1, 1000, 40],
  );
});

test('交互档关闭阴影并在静止500ms后恢复基础档', () => {
  const manager = new QualityManager({
    devicePixelRatio: 2,
    hardwareConcurrency: 12,
  });
  assert.equal(manager.beginInteraction().shadows, false);
  assert.equal(manager.currentProfile.name, 'interactive');
  assert.equal(manager.settleInteraction(499).name, 'interactive');
  assert.equal(manager.settleInteraction(500).name, 'high');
});

test('标签投影只有发生变化时才上报', () => {
  const reporter = new ProjectionReporter();
  const labels = [{ kind: 'chapter', id: 1, x: 0.1, y: 0.2 }];
  assert.equal(reporter.shouldEmit(labels), true);
  assert.equal(reporter.shouldEmit(structuredClone(labels)), false);
  assert.equal(
    reporter.shouldEmit([{ kind: 'chapter', id: 1, x: 0.11, y: 0.2 }]),
    true,
  );
});
