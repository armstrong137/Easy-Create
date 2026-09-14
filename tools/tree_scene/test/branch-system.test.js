import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import * as THREE from 'three';

import {
  BranchSystem,
  branchRadiusForKind,
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
    marker.position.set(0, 0.55 + index * (4.15 / 15), 0);
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

test('sapling chapter anchor follows the young crown and stays in portrait view', () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(1);
  state.treeAge = 0.08;
  branches.sync(state);

  const entry = branches.entries.find((item) => item.kind === 'chapter');
  const start = entry.curve.getPointAt(0);
  const end = entry.curve.getPointAt(1);
  assert.ok(start.y < 2, `sapling branch starts too high: ${start.y}`);
  assert.ok(end.x < -0.55 && end.x > -1.2, `chapter endpoint is outside portrait view: ${end.x}`);
});

test('section branches grow from the trunk to the right without crossing the tree', () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(2, 3);
  state.activeChapterId = state.chapters[1].id;
  branches.sync(state);

  const entry = branches.entries.find(
    (item) => item.kind === 'section' && item.chapterId === state.activeChapterId,
  );
  const start = entry.curve.getPointAt(0);
  const end = entry.curve.getPointAt(1);
  assert.ok(Math.abs(start.x) < 0.2, `section branch does not start on trunk: ${start.x}`);
  assert.ok(end.x > 0.55 && end.x < 1.25, `section endpoint is outside portrait view: ${end.x}`);
});

test('chapter and section branches stay subordinate to the main trunk', () => {
  assert.ok(branchRadiusForKind('chapter') <= 0.06);
  assert.ok(branchRadiusForKind('section') <= 0.035);
  assert.ok(branchRadiusForKind('chapter') > branchRadiusForKind('section'));
});

test('mature chapter focus uses a close trunk composition', () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(10, 2);
  state.treeAge = 1;
  state.activeChapterId = state.chapters.at(-1).id;
  branches.sync(state);

  const anchor = branches.getAnchor('chapter', state.activeChapterId);
  assert.ok(anchor.userData.frameDistance <= 9, anchor.userData);
  const visibleEndpoints = branches.entries
    .filter((entry) => entry.visible)
    .map((entry) => entry.curve.getPointAt(1).x);
  assert.ok(visibleEndpoints.every((x) => Math.abs(x) <= 0.9), visibleEndpoints);
});

test('two section twigs leave enough vertical room for readable plaques', () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(2, 2);
  state.activeChapterId = state.chapters[1].id;
  branches.sync(state);
  const endpoints = branches.entries
    .filter((entry) => entry.kind === 'section' && entry.chapterId === state.activeChapterId)
    .map((entry) => entry.curve.getPointAt(1).y)
    .sort((left, right) => left - right);

  assert.ok(endpoints[1] - endpoints[0] >= 0.58, endpoints);
});

test('two visible chapter branches leave enough vertical room for plaques', () => {
  const root = new THREE.Group();
  const branches = new BranchSystem({ root, markers: markers() });
  const state = snapshot(10, 0);
  state.activeChapterId = state.chapters.at(-1).id;
  branches.sync(state);
  const endpoints = branches.entries
    .filter((entry) => entry.kind === 'chapter' && entry.visible)
    .map((entry) => entry.curve.getPointAt(1).y)
    .sort((left, right) => left - right);

  assert.ok(endpoints[1] - endpoints[0] >= 0.70, endpoints);
});

test('settled label branches grow forked wooden supports around the plaque', async () => {
  const source = await readFile(new URL('../src/BranchSystem.js', import.meta.url), 'utf8');
  assert.match(source, /supportCurves\(entry\)/);
  assert.match(source, /supportRadius/);
  assert.match(source, /mergeGeometries\(parts, false\)/);
});
