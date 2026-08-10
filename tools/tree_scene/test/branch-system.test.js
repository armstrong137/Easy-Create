import assert from 'node:assert/strict';
import test from 'node:test';

import * as THREE from 'three';

import {
  BranchSystem,
  buildBranchLayout,
  visibleBranchIds,
} from '../src/BranchSystem.js';
import { LeafSystem } from '../src/LeafSystem.js';

function snapshot(chapterCount, sectionsPerChapter = 0) {
  return {
    treeAge: Math.min(1, 0.08 + chapterCount / 24),
    chapters: Array.from({ length: chapterCount }, (_, chapterIndex) => ({
      id: 100 + chapterIndex,
      title: `第${chapterIndex + 1}章`,
      sections: Array.from({ length: sectionsPerChapter }, (_, sectionIndex) => ({
        id: 10000 + chapterIndex * 100 + sectionIndex,
        title: `第${sectionIndex + 1}节`,
      })),
    })),
  };
}

function markers() {
  return Array.from({ length: 16 }, (_, index) => {
    const marker = new THREE.Object3D();
    marker.position.set(0, 0.8 + index * 0.42, 0);
    marker.updateMatrixWorld();
    return marker;
  });
}

test('新增章节不改变已有章节枝的种子与挂点', () => {
  const before = buildBranchLayout(snapshot(2));
  const after = buildBranchLayout(snapshot(3));
  for (const id of [100, 101]) {
    assert.equal(after.chapters.get(id).seed, before.chapters.get(id).seed);
    assert.equal(after.chapters.get(id).anchorKey, before.chapters.get(id).anchorKey);
    assert.deepEqual(after.chapters.get(id).controlSignature, before.chapters.get(id).controlSignature);
  }
});

test('新增小节不改变主树树龄或已有小节挂点', () => {
  const beforeSnapshot = snapshot(3, 2);
  const afterSnapshot = snapshot(3, 3);
  const before = buildBranchLayout(beforeSnapshot);
  const after = buildBranchLayout(afterSnapshot);

  assert.equal(after.treeAge, before.treeAge);
  for (const id of [10000, 10001]) {
    assert.equal(after.sections.get(id).anchorKey, before.sections.get(id).anchorKey);
    assert.deepEqual(after.sections.get(id).controlSignature, before.sections.get(id).controlSignature);
  }
});

test('40章每章12节保持批处理预算', () => {
  const root = new THREE.Group();
  const leafSystem = new LeafSystem({ root, capacity: 5000 });
  const branches = new BranchSystem({ root, markers: markers(), leafSystem });
  branches.sync(snapshot(40, 12));
  const metrics = branches.getMetrics();

  assert.ok(metrics.drawCalls <= 3, `drawCalls=${metrics.drawCalls}`);
  assert.ok(metrics.triangles <= 50000, `triangles=${metrics.triangles}`);
  assert.equal(branches.getAnchor('chapter', 100) instanceof THREE.Object3D, true);
  assert.equal(branches.getAnchor('section', 10000) instanceof THREE.Object3D, true);
});

test('新增章节枝沿单一时间轴从芽点连续长出', async () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const samples = [];
  const timeline = {
    async tween({ onUpdate }) {
      for (const value of [0, 0.2, 0.5, 0.8, 1]) {
        onUpdate(value);
        samples.push(branches.activeGrowthProgress());
      }
    },
  };

  await branches.growChapter(snapshot(1).chapters[0], timeline);
  assert.deepEqual(samples, [0, 0.2, 0.5, 0.8, 1]);
  assert.equal(branches.activeGrowthProgress(), null);
});

test('删除小节枝沿单一时间轴反向收拢并移除节点', async () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(2, 3);
  state.activeChapterId = 101;
  state.activeSectionId = 10102;
  branches.sync(state);
  const samples = [];
  const timeline = {
    async tween({ onUpdate }) {
      for (const value of [0, 0.2, 0.5, 0.8, 1]) {
        onUpdate(value);
        samples.push(branches.activeGrowthProgress());
      }
    },
  };

  await branches.removeSection(10102, timeline);

  assert.deepEqual(samples, [0, 0.2, 0.5, 0.8, 1]);
  assert.equal(branches.getAnchor('section', 10102), null);
  assert.equal(branches.activeGrowthProgress(), null);
});

test('删除章节枝会连同其小节一起反向收拢', async () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(3, 2);
  branches.sync(state);
  const timeline = {
    async tween({ onUpdate }) {
      for (const value of [0, 0.4, 0.7, 1]) onUpdate(value);
    },
  };

  await branches.removeChapter(101, timeline);

  assert.equal(branches.getAnchor('chapter', 101), null);
  assert.equal(branches.getAnchor('section', 10100), null);
  assert.equal(branches.getAnchor('section', 10101), null);
});

test('多章节只渲染当前窗口内的两章和五节枝', () => {
  const state = snapshot(40, 12);
  state.activeChapterId = state.chapters[20].id;
  state.activeSectionId = state.chapters[20].sections[7].id;
  const visible = visibleBranchIds(state);

  assert.deepEqual([...visible.chapterIds], [119, 120]);
  assert.equal(visible.sectionIds.size, 5);
  assert.equal(visible.sectionIds.has(state.chapters[20].sections[7].id), true);
});
