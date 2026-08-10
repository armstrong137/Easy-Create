import * as THREE from 'three';

import { PICK_LAYER } from './InteractionSystem.js';

export function fitFontSize(text, maxWidth, preferred) {
  const units = [...String(text)].reduce(
    (sum, character) => sum + (/^[\x00-\x7F]$/.test(character) ? 0.56 : 1),
    0,
  );
  if (units * preferred <= maxWidth) return preferred;
  return Math.max(18, Math.floor(maxWidth / Math.max(1, units)));
}

export function computeLabelLayout(snapshot) {
  const chapters = snapshot.chapters ?? [];
  const activeIndex = Math.max(
    0,
    chapters.findIndex((chapter) => chapter.id === snapshot.activeChapterId),
  );
  const resolvedIndex = snapshot.activeChapterId == null ? chapters.length - 1 : activeIndex;
  const chapterIndices = [resolvedIndex];
  if (resolvedIndex > 0) chapterIndices.push(resolvedIndex - 1);
  else if (chapters.length > 1) chapterIndices.push(1);
  const visibleChapters = chapterIndices
    .filter((index) => index >= 0 && index < chapters.length)
    .map((index, displayRank) => ({
      ...chapters[index],
      side: 'left',
      displayRank,
    }));

  const activeChapter = chapters[resolvedIndex];
  const allSections = activeChapter?.sections ?? [];
  const matchedSectionIndex = allSections.findIndex(
    (section) => section.id === snapshot.activeSectionId,
  );
  const sectionIndex = snapshot.activeSectionId == null
    ? Math.max(0, allSections.length - 1)
    : Math.max(0, matchedSectionIndex);
  const start = Math.max(0, Math.min(sectionIndex - 2, allSections.length - 5));
  const sections = allSections.slice(start, start + 5).map((section) => ({
    ...section,
    chapterId: activeChapter.id,
    side: 'right',
  }));
  return { chapters: visibleChapters, sections };
}

export class LabelSystem {
  constructor({ root, branchSystem, camera }) {
    this.root = root;
    this.branchSystem = branchSystem;
    this.camera = camera;
    this.labels = [];
    this.pickRoots = [];
    this.wood = new THREE.MeshStandardMaterial({
      color: 0x4f2d18,
      roughness: 0.82,
      metalness: 0.02,
    });
    this.gold = new THREE.MeshStandardMaterial({
      color: 0xb68a3a,
      roughness: 0.48,
      metalness: 0.36,
    });
  }

  sync(snapshot) {
    this.clear();
    const layout = computeLabelLayout(snapshot);
    for (const chapter of layout.chapters) this.addLabel('chapter', chapter);
    for (const section of layout.sections) this.addLabel('section', section);
  }

  update() {
    for (const label of this.labels) label.quaternion.copy(this.camera.quaternion);
  }

  projections() {
    return this.labels.flatMap((label) => {
      const point = label.getWorldPosition(new THREE.Vector3()).project(this.camera);
      if (point.z < -1 || point.z > 1) return [];
      const chapter = label.userData.kind === 'chapter';
      return [{
        kind: label.userData.kind,
        id: label.userData.id,
        x: (point.x + 1) / 2 - (chapter ? 0.065 : 0.09),
        y: (1 - point.y) / 2 - (chapter ? 0.075 : 0.035),
        width: chapter ? 0.13 : 0.18,
        height: chapter ? 0.15 : 0.07,
      }];
    });
  }

  addLabel(kind, item) {
    const anchor = this.branchSystem.getAnchor(kind, item.id);
    if (!anchor) return;
    const chapter = kind === 'chapter';
    const width = chapter ? 0.9 : 1.45;
    const height = chapter ? 1.45 : 0.55;
    const group = new THREE.Group();
    group.name = `${kind}Label_${item.id}`;
    group.userData = { kind, id: item.id };
    const chapterY = chapter ? (item.displayRank === 0 ? -0.48 : 0.48) : 0;
    group.position.set(0, chapterY, 0);

    const frame = new THREE.Mesh(new THREE.BoxGeometry(width, height, 0.105), this.wood);
    frame.userData = group.userData;
    frame.layers.enable(PICK_LAYER);
    group.add(frame);

    const panelMaterial = new THREE.MeshStandardMaterial({
      map: this.makeTextTexture(item.title, chapter),
      roughness: 0.9,
      metalness: 0,
    });
    const panel = new THREE.Mesh(
      new THREE.PlaneGeometry(width * 0.78, height * 0.84),
      panelMaterial,
    );
    panel.position.z = 0.056;
    panel.userData = group.userData;
    panel.layers.enable(PICK_LAYER);
    group.add(panel);

    for (const y of [-height * 0.51, height * 0.51]) {
      const ornament = new THREE.Mesh(
        new THREE.OctahedronGeometry(chapter ? 0.085 : 0.055, 0),
        this.gold,
      );
      ornament.position.set(0, y, 0.02);
      ornament.userData = group.userData;
      ornament.layers.enable(PICK_LAYER);
      group.add(ornament);
    }

    anchor.add(group);
    this.labels.push(group);
    this.pickRoots.push(group);
  }

  makeTextTexture(text, vertical) {
    const canvas = document.createElement('canvas');
    canvas.width = vertical ? 384 : 768;
    canvas.height = vertical ? 640 : 256;
    const context = canvas.getContext('2d');
    context.fillStyle = '#d8c59a';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.strokeStyle = '#9e7739';
    context.lineWidth = 18;
    context.strokeRect(10, 10, canvas.width - 20, canvas.height - 20);
    context.fillStyle = '#2f2117';
    context.textAlign = 'center';
    context.textBaseline = 'middle';

    if (vertical && [...text].length <= 8) {
      const characters = [...text];
      const size = Math.min(76, Math.floor(470 / Math.max(1, characters.length)));
      context.font = `600 ${size}px serif`;
      characters.forEach((character, index) => {
        const y = canvas.height / 2 + (index - (characters.length - 1) / 2) * size * 1.12;
        context.fillText(character, canvas.width / 2, y);
      });
    } else {
      const size = fitFontSize(text, canvas.width - 80, vertical ? 58 : 74);
      context.font = `600 ${size}px serif`;
      context.fillText(text, canvas.width / 2, canvas.height / 2, canvas.width - 80);
    }
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 4;
    return texture;
  }

  clear() {
    for (const label of this.labels) {
      label.traverse((object) => {
        object.geometry?.dispose?.();
        if (object.material?.map) object.material.map.dispose();
        if (object.material !== this.wood && object.material !== this.gold) {
          object.material?.dispose?.();
        }
      });
      label.removeFromParent();
    }
    this.labels = [];
    this.pickRoots = [];
  }
}
