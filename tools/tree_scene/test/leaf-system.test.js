import assert from 'node:assert/strict';
import test from 'node:test';

import * as THREE from 'three';

import { LeafSystem } from '../src/LeafSystem.js';

function makeGuide() {
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute(
    'position',
    new THREE.Float32BufferAttribute([
      -0.3, 0, 1.0,
      0.2, 0, 1.2,
      -0.6, 0, 2.4,
      0.5, 0, 3.1,
      0.1, 0, 4.4,
    ], 3),
  );
  geometry.setAttribute(
    '_BIRTH',
    new THREE.Float32BufferAttribute([0, 0, 0.25, 0.55, 0.85], 1),
  );
  const guide = new THREE.Points(geometry);
  guide.name = 'CrownGuide';
  return guide;
}

test('空书幼苗已有完整嫩冠且树龄增长叶片只增不减', () => {
  const root = new THREE.Group();
  const leaves = new LeafSystem({ root, capacity: 32 });
  leaves.setCrownGuide(makeGuide());

  leaves.setTreeAge(0);
  const sapling = leaves.getMetrics().instances;
  leaves.setTreeAge(0.5);
  const young = leaves.getMetrics().instances;
  leaves.setTreeAge(1);
  const mature = leaves.getMetrics().instances;

  assert.ok(sapling >= 2, `幼苗树冠叶片不足：${sapling}`);
  assert.ok(young > sapling);
  assert.ok(mature > young);
  leaves.dispose();
});

test('sapling leaves grow on Y and contract on X/Z in three.js coordinates', () => {
  const root = new THREE.Group();
  const system = new LeafSystem({ root, capacity: 4 });
  const guideGeometry = new THREE.BufferGeometry();
  guideGeometry.setAttribute(
    'position',
    new THREE.Float32BufferAttribute([1, 4, 2], 3),
  );
  const guide = new THREE.Points(guideGeometry);
  guide.userData.anchor_count = 1;
  system.setCrownGuide(guide);
  system.setTreeAge(0.08);

  const matrix = new THREE.Matrix4();
  system.meshes[0].getMatrixAt(0, matrix);
  const position = new THREE.Vector3().setFromMatrixPosition(matrix);
  assert.ok(Math.abs(position.x - 0.06) < 0.001);
  assert.ok(Math.abs(position.y - 0.8) < 0.001);
  assert.ok(Math.abs(position.z - 0.12) < 0.001);
});

test('crown guide may be a glTF role group containing the points mesh', () => {
  const root = new THREE.Group();
  const system = new LeafSystem({ root, capacity: 8 });
  const roleGroup = new THREE.Group();
  roleGroup.userData.anchor_count = 5;
  roleGroup.add(makeGuide());

  assert.doesNotThrow(() => system.setCrownGuide(roleGroup));
  assert.ok(system.getMetrics().instances >= 2);
  system.dispose();
});

test('crown anchors include the glTF mesh node transform before age scaling', () => {
  const root = new THREE.Group();
  const system = new LeafSystem({ root, capacity: 4 });
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute(
    'position',
    new THREE.Float32BufferAttribute([100, 200, 300], 3),
  );
  const guide = new THREE.Mesh(geometry);
  guide.scale.setScalar(0.01);
  guide.position.set(-1, -2, -3);
  guide.userData.anchor_count = 1;
  root.add(guide);
  root.updateMatrixWorld(true);

  system.setCrownGuide(guide);
  system.setTreeAge(1);

  const matrix = new THREE.Matrix4();
  system.meshes[0].getMatrixAt(0, matrix);
  const position = new THREE.Vector3().setFromMatrixPosition(matrix);
  assert.ok(position.distanceTo(new THREE.Vector3(0, 0, 0)) < 0.001, position);
  system.dispose();
});

test('runtime leaves preserve the optimized glTF prototype UV contract', () => {
  const root = new THREE.Group();
  const texture = new THREE.Texture();
  texture.offset.set(0.035, 0.02);
  texture.repeat.set(3.2, 5.76);
  const source = new THREE.MeshStandardMaterial({ map: texture });
  const geometry = new THREE.PlaneGeometry(0.18, 0.36);
  const uv = geometry.getAttribute('uv');
  uv.setXY(0, 0.035, 0.62);
  uv.setXY(1, 0.235, 0.62);
  uv.setXY(2, 0.035, 0.98);
  uv.setXY(3, 0.235, 0.98);
  geometry.translate(8000, 4000, 0);
  const prototype = new THREE.Mesh(geometry, source);
  const staleTexture = new THREE.Texture();
  const staleMaterial = new THREE.MeshStandardMaterial({ map: staleTexture });
  const system = new LeafSystem({
    root,
    capacity: 4,
    materials: [staleMaterial, staleMaterial],
    prototype,
  });

  const runtimeMap = system.meshes[0].material.map;
  assert.notEqual(runtimeMap, staleTexture);
  system.geometry.computeBoundingBox();
  const center = system.geometry.boundingBox.getCenter(new THREE.Vector3());
  const size = system.geometry.boundingBox.getSize(new THREE.Vector3());
  assert.ok(center.length() < 0.001, `leaf geometry escaped its local origin: ${center.toArray()}`);
  assert.ok(size.x <= 0.15 && size.y <= 0.14, `leaf cluster is oversized: ${size.toArray()}`);
  assert.ok((system.geometry.index?.count ?? 0) / 3 >= 6, 'a crown instance must be a real leaf cluster');
  const runtimeUvs = Array.from(system.geometry.getAttribute('uv').array);
  assert.ok(Math.abs(Math.min(...runtimeUvs.filter((_, index) => index % 2 === 0)) - 0.035) < 0.001);
  assert.ok(Math.abs(Math.max(...runtimeUvs.filter((_, index) => index % 2 === 0)) - 0.235) < 0.001);
  assert.deepEqual(runtimeMap.offset.toArray(), [0.035, 0.02]);
  assert.deepEqual(runtimeMap.repeat.toArray(), [3.2, 5.76]);
  system.dispose();
});

test('optimized guides without birth metadata keep the sapling crown sparse', () => {
  const root = new THREE.Group();
  const system = new LeafSystem({ root, capacity: 256 });
  const positions = [];
  for (let index = 0; index < 200; index += 1) {
    positions.push((index % 10) * 0.05, 1 + index * 0.01, 0);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  const guide = new THREE.Points(geometry);
  guide.userData.anchor_count = 200;
  system.setCrownGuide(guide);
  system.setTreeAge(0.08);

  assert.ok(system.getMetrics().instances >= 36, system.getMetrics());
  assert.ok(system.getMetrics().instances <= 48, system.getMetrics());
  system.dispose();
});

test('mature crown forms layered foliage while preserving trunk gaps', () => {
  const root = new THREE.Group();
  const system = new LeafSystem({ root, capacity: 5000 });
  const positions = [];
  for (let index = 0; index < 2600; index += 1) {
    positions.push((index % 50) * 0.02, 1 + index * 0.001, 0);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  const guide = new THREE.Points(geometry);
  guide.userData.anchor_count = 2600;
  system.setCrownGuide(guide);
  system.setTreeAge(1);

  assert.ok(system.getMetrics().instances >= 1500, system.getMetrics());
  assert.ok(system.getMetrics().instances <= 1900, system.getMetrics());
  system.dispose();
});
