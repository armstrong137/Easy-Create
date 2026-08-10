import * as THREE from 'three';

export const PICK_LAYER = 7;

export class InteractionSystem {
  constructor({ camera, pickRoots = [] }) {
    this.camera = camera;
    this.pickRoots = pickRoots;
    this.raycaster = new THREE.Raycaster();
    this.raycaster.layers.set(PICK_LAYER);
    this.owner = null;
  }

  setPickRoots(pickRoots) {
    this.pickRoots = pickRoots;
  }

  beginGesture(ndcX) {
    this.owner = ndcX < 0 ? 'chapter' : 'section';
    return this.owner;
  }

  updateGesture() {
    return this.owner;
  }

  endGesture() {
    this.owner = null;
  }

  hitTest(ndcX, ndcY) {
    this.raycaster.setFromCamera({ x: ndcX, y: ndcY }, this.camera);
    const hits = this.raycaster.intersectObjects(this.pickRoots, true);
    for (const hit of hits) {
      let object = hit.object;
      while (object) {
        if (object.userData?.kind && object.userData?.id !== undefined) {
          return { kind: object.userData.kind, id: object.userData.id };
        }
        object = object.parent;
      }
    }
    return null;
  }
}
