import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

function stableHash(value) {
  let hash = 2166136261;
  for (const character of String(value)) {
    hash ^= character.codePointAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function signature(seed, length) {
  return Array.from({ length }, (_, index) => {
    const shifted = seed >>> ((index * 5) % 24);
    return Number((((shifted & 31) / 31) * 2 - 1).toFixed(4));
  });
}

export function buildBranchLayout(snapshot, markerCount = 16) {
  const chapters = new Map();
  const sections = new Map();
  for (const [ordinal, chapter] of (snapshot.chapters ?? []).entries()) {
    const seed = stableHash(`chapter:${chapter.id}`);
    const anchorIndex = Math.max(0, markerCount - 1 - (ordinal % markerCount));
    const descriptor = {
      kind: 'chapter',
      id: chapter.id,
      seed,
      anchorKey: `trunk:${anchorIndex}`,
      anchorIndex,
      ordinal,
      controlSignature: signature(seed, 4),
    };
    chapters.set(chapter.id, descriptor);

    const chapterSections = chapter.sections ?? [];
    for (const [sectionOrdinal, section] of chapterSections.entries()) {
      const sectionSeed = stableHash(`section:${section.id}`);
      sections.set(section.id, {
        kind: 'section',
        id: section.id,
        chapterId: chapter.id,
        seed: sectionSeed,
        ordinal: sectionOrdinal,
        siblingCount: chapterSections.length,
        anchorKey: `chapter:${chapter.id}:${sectionSeed % 11}`,
        controlSignature: signature(sectionSeed, 4),
      });
    }
  }
  return { treeAge: snapshot.treeAge ?? 0.08, chapters, sections };
}

export class BranchSystem {
  constructor({ root, markers, barkMaterial = null, leafSystem = null }) {
    this.root = root;
    this.markers = markers;
    this.leafSystem = leafSystem;
    this.material = barkMaterial?.clone?.() ?? new THREE.MeshStandardMaterial({
      color: 0x4b2d18,
      roughness: 0.88,
    });
    this.group = new THREE.Group();
    this.group.name = 'RuntimeBranches';
    root.add(this.group);
    this.anchorGroup = new THREE.Group();
    this.anchorGroup.name = 'RuntimeBranchAnchors';
    root.add(this.anchorGroup);
    this.anchors = new Map();
    this.entries = [];
    this.snapshot = { treeAge: 0.08, chapters: [] };
    this.batch = null;
    this.active = null;
  }

  sync(snapshot) {
    this.snapshot = structuredClone(snapshot);
    const layout = buildBranchLayout(snapshot, this.markers.length);
    const entries = [];
    const chapterCurves = new Map();
    const activeChapterId =
      snapshot.activeChapterId ?? snapshot.chapters?.at(-1)?.id ?? null;

    for (const descriptor of layout.chapters.values()) {
      const curve = this.chapterCurve(descriptor);
      chapterCurves.set(descriptor.id, curve);
      entries.push({ ...descriptor, curve });
    }
    for (const descriptor of layout.sections.values()) {
      const parent = chapterCurves.get(descriptor.chapterId);
      if (!parent) continue;
      entries.push({
        ...descriptor,
        curve: this.sectionCurve(descriptor, parent),
        visible: descriptor.chapterId === activeChapterId,
      });
    }

    this.entries = entries;
    this.rebuildBatch();
    this.rebuildAnchors();
    this.leafSystem?.sync(entries.filter((entry) => entry.kind === 'chapter' || entry.visible));
  }

  async growChapter(chapter, timeline) {
    const nextSnapshot = structuredClone(this.snapshot);
    nextSnapshot.chapters ??= [];
    if (!nextSnapshot.chapters.some((item) => item.id === chapter.id)) {
      nextSnapshot.chapters.push({ ...chapter, sections: chapter.sections ?? [] });
    }
    const descriptor = buildBranchLayout(nextSnapshot, this.markers.length).chapters.get(chapter.id);
    await this.runGrowth({ ...descriptor, curve: this.chapterCurve(descriptor) }, timeline);
    this.sync(nextSnapshot);
  }

  async growSection(section, timeline) {
    const nextSnapshot = structuredClone(this.snapshot);
    const chapter = nextSnapshot.chapters?.find((item) => item.id === section.chapterId);
    if (!chapter) return;
    chapter.sections ??= [];
    if (!chapter.sections.some((item) => item.id === section.id)) chapter.sections.push(section);
    const layout = buildBranchLayout(nextSnapshot, this.markers.length);
    const chapterDescriptor = layout.chapters.get(section.chapterId);
    const descriptor = layout.sections.get(section.id);
    const parent = this.chapterCurve(chapterDescriptor);
    await this.runGrowth({ ...descriptor, curve: this.sectionCurve(descriptor, parent) }, timeline);
    this.sync(nextSnapshot);
  }

  async removeChapter(id, timeline) {
    const branch = this.entries.find((entry) => entry.kind === 'chapter' && entry.id === id);
    if (branch) await this.runGrowth(branch, timeline, true);
    const nextSnapshot = structuredClone(this.snapshot);
    nextSnapshot.chapters = (nextSnapshot.chapters ?? []).filter((chapter) => chapter.id !== id);
    this.sync(nextSnapshot);
  }

  getAnchor(kind, id) {
    return this.anchors.get(`${kind}:${id}`) ?? null;
  }

  activeGrowthProgress() {
    return this.active?.progress ?? null;
  }

  getMetrics() {
    const branchTriangles = this.batch?.geometry.index?.count / 3 || 0;
    const leaves = this.leafSystem?.getMetrics() ?? { drawCalls: 0, triangles: 0 };
    return {
      drawCalls: (this.batch ? 1 : 0) + leaves.drawCalls,
      triangles: branchTriangles + leaves.triangles,
    };
  }

  chapterCurve(descriptor) {
    const marker = this.markers[descriptor.anchorIndex % this.markers.length];
    const start = marker.getWorldPosition(new THREE.Vector3());
    this.root.worldToLocal(start);
    const [a, b, c, d] = descriptor.controlSignature;
    return new THREE.CatmullRomCurve3([
      start.clone().add(new THREE.Vector3(0.06, -0.02, 0)),
      start.clone().add(new THREE.Vector3(-0.38, 0.10 + a * 0.16, b * 0.24)),
      start.clone().add(new THREE.Vector3(-1.05, 0.28 + c * 0.30, d * 0.54)),
      start.clone().add(new THREE.Vector3(-1.72 - Math.abs(a) * 0.58, 0.46 + b * 0.42, c * 0.78)),
    ]);
  }

  sectionCurve(descriptor, parentCurve) {
    const [a, b, c, d] = descriptor.controlSignature;
    const count = Math.max(1, descriptor.siblingCount);
    const t = 0.22 + (descriptor.ordinal / Math.max(1, count - 1)) * 0.58;
    const lane = (descriptor.ordinal - (count - 1) / 2) * 0.52;
    const start = parentCurve.getPointAt(Math.min(0.82, t));
    const horizontalSpan = 2.65 - start.x;
    return new THREE.CatmullRomCurve3([
      start,
      start.clone().add(new THREE.Vector3(horizontalSpan * 0.30, lane * 0.25 + 0.10 + a * 0.08, b * 0.18)),
      start.clone().add(new THREE.Vector3(horizontalSpan * 0.70, lane * 0.72 + 0.24 + c * 0.16, d * 0.26)),
      start.clone().add(new THREE.Vector3(horizontalSpan, lane + 0.38 + a * 0.20, b * 0.34)),
    ]);
  }

  geometryFor(entry) {
    const chapter = entry.kind === 'chapter';
    const tubularSegments = chapter ? 14 : 5;
    const radialSegments = chapter ? 6 : 4;
    const geometry = new THREE.TubeGeometry(
      entry.curve,
      tubularSegments,
      chapter ? 0.11 : 0.032,
      radialSegments,
      false,
    );
    const positions = geometry.getAttribute('position');
    const center = new THREE.Vector3();
    const point = new THREE.Vector3();
    const ringSize = radialSegments + 1;
    for (let ring = 0; ring <= tubularSegments; ring += 1) {
      const t = ring / tubularSegments;
      entry.curve.getPointAt(t, center);
      const taper = 0.14 + 0.86 * (1 - t) ** 0.72;
      for (let radial = 0; radial < ringSize; radial += 1) {
        const index = ring * ringSize + radial;
        point.fromBufferAttribute(positions, index);
        point.sub(center).multiplyScalar(taper).add(center);
        positions.setXYZ(index, point.x, point.y, point.z);
      }
    }
    positions.needsUpdate = true;
    geometry.computeVertexNormals();
    return geometry;
  }

  rebuildBatch() {
    if (this.batch) {
      this.batch.geometry.dispose();
      this.batch.removeFromParent();
      this.batch = null;
    }
    const geometries = this.entries
      .filter((entry) => entry.kind === 'chapter' || entry.visible)
      .map((entry) => this.geometryFor(entry));
    if (geometries.length === 0) return;
    const merged = mergeGeometries(geometries, false);
    for (const geometry of geometries) geometry.dispose();
    this.batch = new THREE.Mesh(merged, this.material);
    this.batch.name = 'SettledBranchBatch';
    this.batch.castShadow = true;
    this.group.add(this.batch);
  }

  rebuildAnchors() {
    this.anchorGroup.clear();
    this.anchors.clear();
    for (const entry of this.entries) {
      const anchor = new THREE.Object3D();
      anchor.name = `${entry.kind}Anchor_${entry.id}`;
      anchor.position.copy(entry.curve.getPointAt(1));
      this.anchorGroup.add(anchor);
      this.anchors.set(`${entry.kind}:${entry.id}`, anchor);
    }
  }

  async runGrowth(entry, timeline, reverse = false) {
    const geometry = this.geometryFor(entry);
    const mesh = new THREE.Mesh(geometry, this.material);
    const bud = new THREE.Mesh(
      new THREE.SphereGeometry(entry.kind === 'chapter' ? 0.12 : 0.055, 10, 6),
      this.material,
    );
    this.group.add(mesh, bud);
    this.active = { entry, mesh, bud, progress: reverse ? 1 : 0 };
    const indexCount = geometry.index?.count ?? 0;
    const update = (rawProgress) => {
      const progress = reverse ? 1 - rawProgress : rawProgress;
      this.active.progress = rawProgress;
      const visible = Math.floor((indexCount * progress) / 6) * 6;
      geometry.setDrawRange(0, visible);
      bud.position.copy(entry.curve.getPointAt(Math.max(0, Math.min(1, progress))));
      bud.scale.setScalar(0.45 + Math.sin(Math.PI * progress) * 0.55);
    };
    if (timeline?.tween) {
      await timeline.tween({ durationMs: entry.kind === 'chapter' ? 980 : 720, onUpdate: update });
    } else {
      update(1);
    }
    mesh.removeFromParent();
    bud.removeFromParent();
    geometry.dispose();
    bud.geometry.dispose();
    this.active = null;
  }
}
