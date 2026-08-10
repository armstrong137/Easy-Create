import assert from 'node:assert/strict';
import test from 'node:test';

import { TreeGrowthSystem } from '../src/TreeGrowthSystem.js';

function makeHarness() {
  const root = { scale: { x: 1, y: 1, z: 1 } };
  const channel = {
    morphTargetDictionary: {
      age_00: 0,
      age_25: 1,
      age_48: 2,
      age_72: 3,
      age_100: 4,
    },
    morphTargetInfluences: [0, 0, 0, 0, 0],
  };
  return {
    root,
    channel,
    growth: new TreeGrowthSystem({ root, morphChannels: [channel] }),
  };
}

test('树龄连续趋近目标且不会整体缩放根节点', async () => {
  const { growth, root } = makeHarness();
  const completed = growth.setAge(0.7, { animate: true, durationMs: 900 });
  let previous = growth.getState().age;

  for (let index = 0; index < 60; index += 1) {
    growth.update(1 / 60);
    const current = growth.getState().age;
    assert.ok(current >= previous);
    previous = current;
  }

  await completed;
  assert.ok(growth.getState().age >= 0.699);
  assert.deepEqual([root.scale.x, root.scale.y, root.scale.z], [1, 1, 1]);
  assert.equal(growth.getState().phase, 'idle');
});

test('任意树龄只混合相邻两档形态且权重和为一', async () => {
  const { growth, channel } = makeHarness();
  await growth.setAge(0.6, { animate: false });

  const active = channel.morphTargetInfluences.filter((weight) => weight > 0);
  assert.equal(active.length, 2);
  assert.ok(Math.abs(active.reduce((sum, weight) => sum + weight, 0) - 1) < 1e-8);
  assert.deepEqual(channel.morphTargetInfluences.slice(0, 2), [0, 0]);
});

test('树龄输入会限制在零到一之间', async () => {
  const { growth } = makeHarness();
  await growth.setAge(2, { animate: false });
  assert.equal(growth.getState().age, 1);
  await growth.setAge(-1, { animate: false });
  assert.equal(growth.getState().age, 0);
});
