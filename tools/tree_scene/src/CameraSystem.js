import * as THREE from 'three';

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
    if (!chapter) return Promise.resolve();
    return this.focusChapter(chapter.id, options);
  }

  focusChapter(id, { animate = true } = {}) {
    const anchor = this.branchSystem.getAnchor('chapter', id);
    if (!anchor) return Promise.resolve();
    this.chapterId = id;
    this.sectionId = null;
    return this.moveToAnchor(anchor, { animate, distance: 29 });
  }

  focusSection(chapterId, sectionId, { animate = true } = {}) {
    const anchor = this.branchSystem.getAnchor('section', sectionId);
    if (!anchor) return Promise.resolve();
    this.chapterId = chapterId;
    this.sectionId = sectionId;
    return this.moveToAnchor(anchor, { animate, distance: 26.5 });
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
    if (!animate || !this.timeline?.tween) {
      this.camera.position.copy(destinationPosition);
      this.target.copy(destinationTarget);
      this.camera.lookAt(this.target);
      return;
    }

    const startPosition = this.camera.position.clone();
    const startTarget = this.target.clone();
    await this.timeline.tween({
      durationMs: 620,
      onUpdate: (progress) => {
        this.camera.position.lerpVectors(startPosition, destinationPosition, progress);
        this.target.lerpVectors(startTarget, destinationTarget, progress);
        this.camera.lookAt(this.target);
      },
    });
  }
}
