import * as THREE from 'three';

export function treeFrameForAge(age) {
  const normalizedAge = Math.min(1, Math.max(0, Number(age) || 0));
  const target = new THREE.Vector3(0, 0.72 + normalizedAge * 1.85, 0);
  const position = new THREE.Vector3(0, target.y + 0.05, 4.3 + normalizedAge * 5.8);
  return { position, target };
}

export class CameraSystem {
  constructor({ camera, treeRoot, branchSystem, timeline }) {
    this.camera = camera;
    this.treeRoot = treeRoot;
    this.branchSystem = branchSystem;
    this.timeline = timeline;
    this.target = new THREE.Vector3(0, 3.5, 0);
    this.chapterId = null;
    this.sectionId = null;
  }

  focusDefault(snapshot, options = {}) {
    const chapter = snapshot.chapters?.find(
      (item) => item.id === snapshot.activeChapterId,
    ) ?? snapshot.chapters?.at(-1);
    if (!chapter) return this.frameTreeAge(snapshot.treeAge ?? 0, options);
    return this.focusChapter(chapter.id, options);
  }

  frameTreeAge(age, { animate = true } = {}) {
    this.chapterId = null;
    this.sectionId = null;
    const { position, target } = treeFrameForAge(age);
    return this.moveCamera(position, target, { animate, durationMs: 520 });
  }

  focusChapter(id, { animate = true } = {}) {
    const anchor = this.branchSystem.getAnchor('chapter', id);
    if (!anchor) return Promise.resolve();
    this.chapterId = id;
    this.sectionId = null;
    return this.moveToAnchor(anchor, {
      animate,
      distance: anchor.userData.frameDistance ?? 9.5,
    });
  }

  focusSection(chapterId, sectionId, { animate = true } = {}) {
    const anchor = this.branchSystem.getAnchor('section', sectionId);
    if (!anchor) return Promise.resolve();
    this.chapterId = chapterId;
    this.sectionId = sectionId;
    return this.moveToAnchor(anchor, {
      animate,
      distance: anchor.userData.frameDistance ?? 9.5,
    });
  }

  panBy(delta) {
    const movement = Number.isFinite(delta) ? delta : 0;
    this.camera.position.y += movement;
    this.target.y += movement;
    this.camera.lookAt(this.target);
  }

  getState() {
    return {
      chapterId: this.chapterId,
      sectionId: this.sectionId,
      target: this.target.toArray(),
    };
  }

  async moveToAnchor(anchor, { animate, distance }) {
    const world = anchor.getWorldPosition(new THREE.Vector3());
    const destinationTarget = new THREE.Vector3(0, world.y, world.z * 0.18);
    const destinationPosition = new THREE.Vector3(0, world.y + 0.08, distance);
    return this.moveCamera(destinationPosition, destinationTarget, {
      animate,
      durationMs: 620,
    });
  }

  async moveCamera(destinationPosition, destinationTarget, { animate, durationMs }) {
    if (!animate || !this.timeline?.tween) {
      this.camera.position.copy(destinationPosition);
      this.target.copy(destinationTarget);
      this.camera.lookAt(this.target);
      return;
    }

    const startPosition = this.camera.position.clone();
    const startTarget = this.target.clone();
    await this.timeline.tween({
      durationMs,
      onUpdate: (progress) => {
        this.camera.position.lerpVectors(startPosition, destinationPosition, progress);
        this.target.lerpVectors(startTarget, destinationTarget, progress);
        this.camera.lookAt(this.target);
      },
    });
  }
}
