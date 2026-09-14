import assert from 'node:assert/strict';
import test from 'node:test';

import * as THREE from 'three';

import { CameraSystem, treeFrameForAge } from '../src/CameraSystem.js';
import { InteractionSystem } from '../src/InteractionSystem.js';
import {
  computeLabelLayout,
  fitFontSize,
  labelDimensions,
  LabelSystem,
  preferredLabelFont,
} from '../src/LabelSystem.js';

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

test('空书按幼苗树龄取景而不是沿用成熟树远景', async () => {
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 80);
  const treeRoot = new THREE.Group();
  const navigation = new CameraSystem({
    camera,
    treeRoot,
    branchSystem: { getAnchor: () => null },
    timeline: null,
  });

  await navigation.focusDefault({ treeAge: 0, chapters: [] }, { animate: false });

  assert.ok(camera.position.z <= 5.2, `幼苗镜头过远：${camera.position.z}`);
  assert.ok(navigation.getState().target[1] <= 1.1);
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

test('chapter branch tip projects inside the left side of a portrait viewport', () => {
  const camera = new THREE.PerspectiveCamera(30, 430 / 760, 0.1, 80);
  camera.position.set(0, 1.5, 8.5);
  camera.lookAt(0, 1.5, 0);
  camera.updateMatrixWorld(true);
  const anchor = new THREE.Object3D();
  anchor.position.set(-0.82, 1.5, 0);
  anchor.updateMatrixWorld(true);
  const harness = {
    labels: [{
      userData: { kind: 'chapter', id: 1 },
      getWorldPosition: (target) => anchor.getWorldPosition(target),
    }],
    camera,
  };

  const projections = LabelSystem.prototype.projections.call(harness);
  assert.ok(projections[0].x >= 0 && projections[0].x <= 0.35, projections[0]);
});

test('sapling and mature tree share the same stable portrait framing profile', () => {
  const sapling = treeFrameForAge(0.08);
  const mature = treeFrameForAge(1);

  assert.ok(sapling.position.z <= 4.9, sapling.position);
  assert.ok(mature.position.z <= 10.8, mature.position);
  assert.ok(mature.target.y > sapling.target.y);
});

test('chapter and section plaques fit their supporting twigs', () => {
  const chapter = labelDimensions('chapter');
  const section = labelDimensions('section');

  assert.ok(chapter.width <= 0.4 && chapter.height <= 0.7, chapter);
  assert.ok(section.width <= 0.4 && section.height >= 0.5, section);
});

test('plaque surfaces stay readable above foliage while their wood frame casts shadows', () => {
  const root = new THREE.Group();
  const anchor = new THREE.Object3D();
  root.add(anchor);
  const labels = new LabelSystem({
    root,
    branchSystem: { getAnchor: () => anchor },
    camera: new THREE.PerspectiveCamera(),
  });
  labels.makeTextTexture = () => new THREE.Texture();
  labels.sync({
    activeChapterId: 1,
    chapters: [{ id: 1, title: '引子', sections: [] }],
  });
  const plaqueMaterials = [];
  const plaqueMeshes = [];
  labels.labels[0].traverse((object) => {
    if (object.isMesh) {
      plaqueMaterials.push(object.material);
      plaqueMeshes.push(object);
    }
  });

  assert.ok(plaqueMaterials.every((material) => material.depthTest === false));
  assert.ok(plaqueMeshes.some((mesh) => mesh.castShadow));
  const panel = labels.labels[0].children.find((object) => object.name === 'PlaqueTextPanel');
  assert.ok(panel, 'missing plaque text panel');
  assert.equal(panel.geometry.type, 'ShapeGeometry');
  const uv = panel.geometry.getAttribute('uv');
  let minUv = Infinity;
  let maxUv = -Infinity;
  for (let index = 0; index < uv.count; index += 1) {
    minUv = Math.min(minUv, uv.getX(index), uv.getY(index));
    maxUv = Math.max(maxUv, uv.getX(index), uv.getY(index));
  }
  assert.ok(minUv >= -1e-6 && maxUv <= 1 + 1e-6, { minUv, maxUv });
  labels.clear();
});

test('plaque text remains legible at phone rendering size', () => {
  assert.ok(preferredLabelFont('chapter') >= 100);
  assert.ok(preferredLabelFont('section') >= 110);
});

test('plaque frames inherit the same textured bark as their supporting branch', () => {
  const root = new THREE.Group();
  const anchor = new THREE.Object3D();
  root.add(anchor);
  const barkMap = new THREE.Texture();
  const barkMaterial = new THREE.MeshStandardMaterial({ map: barkMap });
  const labels = new LabelSystem({
    root,
    branchSystem: { getAnchor: () => anchor },
    camera: new THREE.PerspectiveCamera(),
    barkMaterial,
  });

  assert.equal(labels.wood.map, barkMap);
  assert.equal(labels.activeWood.map, barkMap);
  labels.clear();
});

test('plaque perimeter is wrapped by organic bark rails and root forks', () => {
  const root = new THREE.Group();
  const anchor = new THREE.Object3D();
  root.add(anchor);
  const labels = new LabelSystem({
    root,
    branchSystem: { getAnchor: () => anchor },
    camera: new THREE.PerspectiveCamera(),
  });
  labels.makeTextTexture = () => new THREE.Texture();
  labels.sync({
    activeChapterId: 1,
    chapters: [{ id: 1, title: '引子', sections: [] }],
  });

  const rails = labels.labels[0].children.filter((child) => child.name === 'PlaqueBarkRail');
  assert.equal(rails.length, 6);
  assert.ok(rails.every((rail) => rail.geometry.type === 'TubeGeometry'));
  labels.clear();
});
