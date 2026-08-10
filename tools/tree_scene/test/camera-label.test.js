import assert from 'node:assert/strict';
import test from 'node:test';

import * as THREE from 'three';

import { CameraSystem } from '../src/CameraSystem.js';
import { InteractionSystem } from '../src/InteractionSystem.js';
import { computeLabelLayout, fitFontSize } from '../src/LabelSystem.js';

const snapshot = {
  treeAge: 1,
  activeChapterId: 4,
  activeSectionId: 42,
  chapters: [1, 2, 3, 4].map((id) => ({
    id,
    title: `第${id}章`,
    sections: [1, 2, 3, 4, 5, 6].map((section) => ({
      id: id * 10 + section,
      title: `第${section}节`,
    })),
  })),
};

test('标签布局左侧最多两章且小节只属于当前章右侧', () => {
  const layout = computeLabelLayout(snapshot);
  assert.equal(layout.chapters.length, 2);
  assert.ok(layout.chapters.every((item) => item.side === 'left'));
  assert.ok(layout.sections.every((item) => item.side === 'right'));
  assert.ok(layout.sections.every((item) => item.chapterId === 4));
});

test('冷进入默认聚焦最新章节且移动相机不改变树矩阵', async () => {
  const camera = new THREE.PerspectiveCamera();
  const treeRoot = new THREE.Group();
  treeRoot.updateMatrixWorld(true);
  const before = treeRoot.matrixWorld.clone();
  const anchors = new Map();
  for (const id of [1, 2, 3, 4]) {
    const anchor = new THREE.Object3D();
    anchor.position.set(-2, 6 - id, 0);
    anchors.set(id, anchor);
  }
  const branchSystem = { getAnchor: (_, id) => anchors.get(id) ?? null };
  const timeline = { tween: async ({ onUpdate }) => onUpdate(1) };
  const navigation = new CameraSystem({ camera, treeRoot, branchSystem, timeline });

  await navigation.focusDefault(snapshot, { animate: false });
  assert.equal(navigation.getState().chapterId, 4);
  await navigation.focusChapter(1, { animate: true });
  assert.equal(navigation.getState().chapterId, 1);
  assert.deepEqual(treeRoot.matrixWorld.elements, before.elements);
});

test('左右手势所有权在开始时锁定且跨中线不切换', () => {
  const interaction = new InteractionSystem({ camera: new THREE.PerspectiveCamera() });
  assert.equal(interaction.beginGesture(-0.2, 0), 'chapter');
  assert.equal(interaction.updateGesture(0.8, 0), 'chapter');
  interaction.endGesture();
  assert.equal(interaction.beginGesture(0.1, 0), 'section');
});

test('长标题字体会收缩但保持可读下限', () => {
  assert.equal(fitFontSize('第一章', 180, 42), 42);
  const long = fitFontSize('这是一个非常非常长的章节标题', 180, 42);
  assert.ok(long < 42);
  assert.ok(long >= 18);
});
