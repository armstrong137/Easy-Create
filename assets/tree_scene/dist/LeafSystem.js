import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

import { heightRatioForAge, radialRatioForAge } from './GrowthProfile.js';

function leafClusterGeometry(prototypeUv) {
  let bounds = null;
  if (prototypeUv) {
    bounds = { minU: Infinity, minV: Infinity, maxU: -Infinity, maxV: -Infinity };
    for (let index = 0; index < prototypeUv.count; index += 1) {
      bounds.minU = Math.min(bounds.minU, prototypeUv.getX(index));
      bounds.minV = Math.min(bounds.minV, prototypeUv.getY(index));
      bounds.maxU = Math.max(bounds.maxU, prototypeUv.getX(index));
      bounds.maxV = Math.max(bounds.maxV, prototypeUv.getY(index));
    }
  }
  const makeLeaf = (width, height, x, y, rotation) => {
    const geometry = new THREE.PlaneGeometry(width, height);
    if (bounds) {
      const runtimeUv = geometry.getAttribute('uv');
      for (let index = 0; index < runtimeUv.count; index += 1) {
        runtimeUv.setXY(
          index,
          THREE.MathUtils.lerp(bounds.minU, bounds.maxU, runtimeUv.getX(index)),
          THREE.MathUtils.lerp(bounds.minV, bounds.maxV, runtimeUv.getY(index)),
        );
      }
      runtimeUv.needsUpdate = true;
    }
    geometry.rotateZ(rotation);
    geometry.translate(x, y, 0);
    return geometry;
  };
  const leaves = [
    makeLeaf(0.034, 0.084, 0, 0.028, 0),
    makeLeaf(0.031, 0.074, -0.025, 0.010, 0.52),
    makeLeaf(0.031, 0.074, 0.025, 0.010, -0.52),
    makeLeaf(0.028, 0.066, -0.040, -0.020, 0.78),
    makeLeaf(0.028, 0.066, 0.040, -0.020, -0.78),
  ];
  const geometry = mergeGeometries(leaves, false);
  for (const leaf of leaves) leaf.dispose();
  geometry.computeBoundingBox();
  const center = geometry.boundingBox.getCenter(new THREE.Vector3());
  geometry.translate(-center.x, -center.y, -center.z);
  return geometry;
}

export class LeafSystem {
  constructor({ root, capacity = 2048, materials = null, prototype = null }) {
    this.root = root;
    this.capacity = capacity;
    this.limit = capacity;
    this.treeAge = 0;
    this.crownGuide = null;
    this.branches = [];
    let prototypeMesh = prototype?.isMesh ? prototype : null;
    prototype?.traverse?.((object) => {
      if (!prototypeMesh && object.isMesh) prototypeMesh = object;
    });
    const prototypeUv = prototypeMesh?.geometry?.getAttribute('uv');
    this.geometry = leafClusterGeometry(prototypeUv);
    const prototypeMaterials = prototypeMesh
      ? (Array.isArray(prototypeMesh.material)
        ? prototypeMesh.material
        : [prototypeMesh.material])
      : null;
    const materialSources = prototypeMaterials ?? materials;
    const leafMaterials = materialSources
      ? materialSources.map((source) => {
        const material = source.clone();
        if (source.map) {
          material.map = source.map.clone();
          material.map.needsUpdate = true;
        }
        return material;
      })
      : [
        new THREE.MeshStandardMaterial({
          color: 0x294a18,
          roughness: 0.78,
          side: THREE.DoubleSide,
        }),
        new THREE.MeshStandardMaterial({
          color: 0x52742a,
          roughness: 0.72,
          side: THREE.DoubleSide,
        }),
      ];
    if (leafMaterials.length === 1) leafMaterials.push(leafMaterials[0].clone());
    this.meshes = leafMaterials.slice(0, 2).map((material, index) => {
      const mesh = new THREE.InstancedMesh(this.geometry, material, capacity);
      mesh.name = `RuntimeLeaves${index}`;
      mesh.count = 0;
      mesh.frustumCulled = false;
      root.add(mesh);
      return mesh;
    });
  }

  sync(branches) {
    this.branches = branches;
    this.rebuild();
  }

  setCrownGuide(guide) {
    let geometryOwner = guide.geometry?.getAttribute?.('position') ? guide : null;
    if (!geometryOwner) {
      guide.traverse?.((object) => {
        if (!geometryOwner && object.geometry?.getAttribute?.('position')) {
          geometryOwner = object;
        }
      });
    }
    if (!geometryOwner) {
      throw new Error('CrownGuide must contain a geometry mesh');
    }
    geometryOwner.userData.anchor_count =
      guide.userData?.anchor_count ?? geometryOwner.userData?.anchor_count;
    this.crownGuide = geometryOwner;
    guide.visible = false;
    this.rebuild();
  }

  setTreeAge(age) {
    const next = Math.min(1, Math.max(0, Number(age) || 0));
    if (Math.abs(next - this.treeAge) < 0.0001) return;
    this.treeAge = next;
    this.rebuild();
  }

  rebuild() {
    const counts = this.meshes.map(() => 0);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const tangent = new THREE.Vector3();
    const scale = new THREE.Vector3();
    const quaternion = new THREE.Quaternion();
    const side = new THREE.Vector3();

    const positions = this.crownGuide?.geometry?.getAttribute('position');
    const births = this.crownGuide?.geometry?.getAttribute('_BIRTH');
    const anchorCount = Math.max(
      0,
      Number(this.crownGuide?.userData?.anchor_count) || (positions?.count ?? 0),
    );
    const guideStride = anchorCount > 0 && positions?.count === anchorCount * 3 ? 3 : 1;
    const heightRatio = heightRatioForAge(this.treeAge);
    const radialRatio = radialRatioForAge(this.treeAge);
    const leafSize = 0.78 + this.treeAge * 0.22;
    for (let anchorIndex = 0; anchorIndex < anchorCount; anchorIndex += 1) {
      const index = anchorIndex * guideStride;
      const birth = births?.getX(index)
        ?? (anchorIndex < 42 ? 0 : 0.08 + ((anchorIndex * 73) % 920) / 1000);
      if (birth > this.treeAge + 0.001) continue;
      if (anchorIndex >= 42 && (anchorIndex * 37) % 100 >= 65) continue;
      const meshIndex = anchorIndex % this.meshes.length;
      const instanceIndex = counts[meshIndex];
      if (instanceIndex >= this.limit) continue;
      position.fromBufferAttribute(positions, index);
      this.crownGuide.localToWorld(position);
      this.root.worldToLocal(position);
      position.set(
        position.x * radialRatio,
        position.y * heightRatio,
        position.z * radialRatio,
      );
      quaternion.setFromEuler(new THREE.Euler(
        ((anchorIndex * 17) % 9 - 4) * 0.11,
        ((anchorIndex * 29) % 11 - 5) * 0.16,
        ((anchorIndex * 43) % 13 - 6) * 0.20,
      ));
      scale.setScalar(leafSize);
      matrix.compose(position, quaternion, scale);
      this.meshes[meshIndex].setMatrixAt(instanceIndex, matrix);
      counts[meshIndex] += 1;
    }

    for (const branch of this.branches) {
      const leafCount = branch.kind === 'chapter' ? 8 : 3;
      for (let index = 0; index < leafCount; index += 1) {
        const meshIndex = (branch.seed + index) % this.meshes.length;
        const instanceIndex = counts[meshIndex];
        if (instanceIndex >= this.limit) continue;
        const t = 0.56 + (index / Math.max(1, leafCount - 1)) * 0.38;
        branch.curve.getPointAt(Math.min(0.96, t), position);
        branch.curve.getTangentAt(Math.min(0.96, t), tangent).normalize();
        side.set(-tangent.y, tangent.x, 0).normalize();
        position.addScaledVector(side, (index % 2 === 0 ? -1 : 1) * 0.07);
        quaternion.setFromEuler(
          new THREE.Euler(
            (((branch.seed + index) % 5) - 2) * 0.10,
            0,
            -Math.atan2(tangent.x, tangent.y),
          ),
        );
        const size = branch.kind === 'chapter' ? 1 : 0.62;
        scale.set(size, size, size);
        matrix.compose(position, quaternion, scale);
        this.meshes[meshIndex].setMatrixAt(instanceIndex, matrix);
        counts[meshIndex] += 1;
      }
    }

    for (const [index, mesh] of this.meshes.entries()) {
      mesh.count = counts[index];
      mesh.instanceMatrix.needsUpdate = true;
    }
  }

  setLimit(limit) {
    this.limit = Math.max(0, Math.min(this.capacity, limit));
    this.rebuild();
  }

  getMetrics() {
    return {
      drawCalls: this.meshes.filter((mesh) => mesh.count > 0).length,
      instances: this.meshes.reduce((sum, mesh) => sum + mesh.count, 0),
      triangles: this.meshes.reduce(
        (sum, mesh) => sum + mesh.count * (this.geometry.index?.count ?? 0) / 3,
        0,
      ),
    };
  }

  dispose() {
    for (const mesh of this.meshes) {
      mesh.removeFromParent();
      mesh.material.map?.dispose();
      mesh.material.dispose();
    }
    this.geometry.dispose();
  }
}
