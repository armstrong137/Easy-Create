import * as THREE from 'three';

export class LeafSystem {
  constructor({ root, capacity = 2048, materials = null }) {
    this.root = root;
    this.capacity = capacity;
    this.limit = capacity;
    this.geometry = new THREE.PlaneGeometry(0.18, 0.36, 1, 2);
    const leafMaterials = materials ?? [
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
    const counts = this.meshes.map(() => 0);
    const matrix = new THREE.Matrix4();
    const position = new THREE.Vector3();
    const tangent = new THREE.Vector3();
    const scale = new THREE.Vector3();
    const quaternion = new THREE.Quaternion();
    const side = new THREE.Vector3();

    for (const branch of branches) {
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
      mesh.material.dispose();
    }
    this.geometry.dispose();
  }
}
