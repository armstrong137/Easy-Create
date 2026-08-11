import assert from 'node:assert/strict';
import test from 'node:test';

import { playTreeMutation } from '../src/MutationPlayer.js';

function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

test('新增章节先出现主树成长再让章节枝与其并行生长', async () => {
  const order = [];
  const age = deferred();
  const branch = deferred();
  const treeScene = {
    setAge(_value, options) {
      order.push(options.animate ? '主树开始' : '主树落定');
      return options.animate ? age.promise : Promise.resolve();
    },
    async waitForGrowthLead(progress) {
      assert.equal(progress, 0.08);
      order.push('主树可见');
    },
    growChapter() {
      order.push('章节枝开始');
      return branch.promise;
    },
    async sync() {
      order.push('快照同步');
    },
  };

  const playing = playTreeMutation({
    treeScene,
    emit: () => {},
    payload: {
      mutation: {
        type: 'addChapter',
        nodeId: 2,
        structuralAgeChanged: true,
      },
      snapshot: {
        treeAge: 0.4,
        chapters: [{ id: 2, title: '第一章', sections: [] }],
      },
    },
  });

  await Promise.resolve();
  await Promise.resolve();
  assert.deepEqual(order.slice(0, 3), ['主树开始', '主树可见', '章节枝开始']);

  branch.resolve();
  await Promise.resolve();
  assert.equal(order.includes('主树落定'), false);

  age.resolve();
  await playing;
  assert.deepEqual(order.slice(-2), ['主树落定', '快照同步']);
});

test('成熟树新增小节不等待不存在的主树成长', async () => {
  const order = [];
  const treeScene = {
    async setAge(_value, options) {
      order.push(options.animate ? '主树开始' : '主树落定');
    },
    async waitForGrowthLead() {
      order.push('不应等待');
    },
    async growSection() {
      order.push('小节枝开始');
    },
    async sync() {},
  };

  await playTreeMutation({
    treeScene,
    emit: () => {},
    payload: {
      mutation: {
        type: 'addSection',
        nodeId: 20,
        parentId: 2,
        structuralAgeChanged: false,
      },
      snapshot: {
        treeAge: 1,
        chapters: [{ id: 2, sections: [{ id: 20, title: '第一节' }] }],
      },
    },
  });

  assert.equal(order.includes('不应等待'), false);
  assert.equal(order.includes('小节枝开始'), true);
});
