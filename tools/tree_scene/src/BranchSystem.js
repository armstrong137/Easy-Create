import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

import { heightRatioForAge, radialRatioForAge } from './GrowthProfile.js';

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

export function branchRadiusForKind(kind) {
  return kind === 'chapter' ? 0.058 : 0.032;
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
        chapterAnchorIndex: anchorIndex,
        anchorKey: `chapter:${chapter.id}:${sectionSeed % 11}`,
        controlSignature: signature(sectionSeed, 4),
      });
    }
  }
  return { treeAge: snapshot.treeAge ?? 0.08, chapters, sections };
}

export function visibleBranchIds(snapshot) {
  const chapters = snapshot.chapters ?? [];
  if (chapters.length === 0) {
    return { chapterIds: new Set(), sectionIds: new Set() };
  }
  const matchedChapter = chapters.findIndex(
    (chapter) => chapter.id === snapshot.activeChapterId,
  );
  const activeIndex = matchedChapter >= 0 ? matchedChapter : chapters.length - 1;
  const chapterIndices = activeIndex > 0
    ? [activeIndex - 1, activeIndex]
    : [0, 1].filter((index) => index < chapters.length);
  const chapterIds = new Set(chapterIndices.map((index) => chapters[index].id));

  const sections = chapters[activeIndex].sections ?? [];
  const matchedSection = sections.findIndex(
    (section) => section.id === snapshot.activeSectionId,
  );
  const activeSection = matchedSection >= 0 ? matchedSection : Math.max(0, sections.length - 1);
  const start = Math.max(0, Math.min(activeSection - 2, sections.length - 5));
  const sectionIds = new Set(sections.slice(start, start + 5).map((section) => section.id));
  return { chapterIds, sectionIds };
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
    const visible = visibleBranchIds(snapshot);
    const visibleChapterOrder = [...visible.chapterIds];

    for (const descriptor of layout.chapters.values()) {
      const resolved = {
        ...descriptor,
        displayRank: visibleChapterOrder.indexOf(descriptor.id),
      };
      const curve = this.chapterCurve(resolved);
      chapterCurves.set(descriptor.id, curve);
      entries.push({
        ...resolved,
        curve,
        visible: visible.chapterIds.has(descriptor.id),
      });
    }
    for (const descriptor of layout.sections.values()) {
      const parent = chapterCurves.get(descriptor.chapterId);
      if (!parent) continue;
      entries.push({
        ...descriptor,
        curve: this.sectionCurve(descriptor),
        visible: visible.sectionIds.has(descriptor.id),
      });
    }

    this.entries = entries;
    this.rebuildBatch();
    this.rebuildAnchors();
    this.leafSystem?.sync(entries.filter((entry) => entry.visible));
  }

  async growChapter(chapter, timeline) {
    const nextSnapshot = structuredClone(this.snapshot);
    nextSnapshot.chapters ??= [];
    if (!nextSnapshot.chapters.some((item) => item.id === chapter.id)) {
      nextSnapshot.chapters.push({ ...chapter, sections: chapter.sections ?? [] });
    }
    const descriptor = buildBranchLayout(nextSnapshot, this.markers.length).chapters.get(chapter.id);
    const visible = visibleBranchIds(nextSnapshot);
    const resolved = {
      ...descriptor,
      displayRank: [...visible.chapterIds].indexOf(chapter.id),
    };
    await this.runGrowth({ ...resolved, curve: this.chapterCurve(resolved) }, timeline);
    this.sync(nextSnapshot);
  }

  async growSection(section, timeline) {
    const nextSnapshot = structuredClone(this.snapshot);
    const chapter = nextSnapshot.chapters?.find((item) => item.id === section.chapterId);
    if (!chapter) return;
    chapter.sections ??= [];
    if (!chapter.sections.some((item) => item.id === section.id)) chapter.sections.push(section);
    const layout = buildBranchLayout(nextSnapshot, this.markers.length);
    const descriptor = layout.sections.get(section.id);
    await this.runGrowth({ ...descriptor, curve: this.sectionCurve(descriptor) }, timeline);
    this.sync(nextSnapshot);
  }

  async removeChapter(id, timeline) {
    const branch = this.entries.find((entry) => entry.kind === 'chapter' && entry.id === id);
    const nextSnapshot = structuredClone(this.snapshot);
    nextSnapshot.chapters = (nextSnapshot.chapters ?? []).filter((chapter) => chapter.id !== id);
    this.sync(nextSnapshot);
    if (branch) await this.runGrowth(branch, timeline, true);
  }

  async removeSection(id, timeline) {
    const branch = this.entries.find((entry) => entry.kind === 'section' && entry.id === id);
    const nextSnapshot = structuredClone(this.snapshot);
    for (const chapter of nextSnapshot.chapters ?? []) {
      chapter.sections = (chapter.sections ?? []).filter((section) => section.id !== id);
    }
    this.sync(nextSnapshot);
    if (branch) await this.runGrowth(branch, timeline, true);
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
    const start = this.trunkPoint(descriptor.anchorIndex);
    const [a, b, c, d] = descriptor.controlSignature;
    const age = Math.min(1, Math.max(0.08, Number(this.snapshot.treeAge) || 0.08));
    const span = 0.58 + Math.sqrt(age) * 0.24;
    const labelLane = descriptor.displayRank === 0
      ? 0.30
      : descriptor.displayRank === 1
        ? -0.30
        : 0;
    return new THREE.CatmullRomCurve3([
      start.clone().add(new THREE.Vector3(0.06, -0.02, 0)),
      start.clone().add(new THREE.Vector3(-span * 0.30, 0.07 + a * 0.08, b * 0.08)),
      start.clone().add(new THREE.Vector3(
        -span * 0.68,
        0.18 + c * 0.12 + labelLane * 0.48,
        d * 0.12,
      )),
      start.clone().add(new THREE.Vector3(
        -span,
        0.28 + b * 0.16 + labelLane,
        c * 0.16,
      )),
    ]);
  }

  sectionCurve(descriptor) {
    const [a, b, c, d] = descriptor.controlSignature;
    const count = Math.max(1, descriptor.siblingCount);
    const lane = (descriptor.ordinal - (count - 1) / 2) * 0.72;
    const markerOffset = Math.round((descriptor.ordinal - (count - 1) / 2) * 0.45);
    const start = this.trunkPoint(descriptor.chapterAnchorIndex + markerOffset);
    const age = Math.min(1, Math.max(0.08, Number(this.snapshot.treeAge) || 0.08));
    const horizontalSpan = 0.56 + Math.sqrt(age) * 0.22;
    return new THREE.CatmullRomCurve3([
      start,
      start.clone().add(new THREE.Vector3(horizontalSpan * 0.30, lane * 0.18 + 0.06 + a * 0.06, b * 0.07)),
      start.clone().add(new THREE.Vector3(horizontalSpan * 0.70, lane * 0.65 + 0.14 + c * 0.09, d * 0.10)),
      start.clone().add(new THREE.Vector3(horizontalSpan, lane + 0.22 + a * 0.12, b * 0.13)),
    ]);
  }

  trunkPoint(markerIndex) {
    const index = Math.max(0, Math.min(this.markers.length - 1, markerIndex));
    const marker = this.markers[index];
    const point = marker.getWorldPosition(new THREE.Vector3());
    this.root.worldToLocal(point);
    const heightRatio = heightRatioForAge(this.snapshot.treeAge);
    const radialRatio = radialRatioForAge(this.snapshot.treeAge);
    const ground = 0.42;
    point.set(
      point.x * radialRatio,
      ground + (point.y - ground) * heightRatio,
      point.z * radialRatio,
    );
    return point;
  }

  tubeGeometry(curve, tubularSegments, radius, radialSegments, minimumTaper = 0.14) {
    const geometry = new THREE.TubeGeometry(
      curve,
      tubularSegments,
      radius,
      radialSegments,
      false,
    );
    const positions = geometry.getAttribute('position');
    const center = new THREE.Vector3();
    const point = new THREE.Vector3();
    const ringSize = radialSegments + 1;
    for (let ring = 0; ring <= tubularSegments; ring += 1) {
      const t = ring / tubularSegments;
      curve.getPointAt(t, center);
      const taper = minimumTaper + (1 - minimumTaper) * (1 - t) ** 0.72;
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

  supportCurves(entry) {
    const end = entry.curve.getPointAt(1);
    const chapter = entry.kind === 'chapter';
    const halfWidth = (chapter ? 0.38 : 0.34) * 0.46;
    const lift = (chapter ? 0.66 : 0.56) * 0.12;
    return [-1, 1].map((direction) => new THREE.CatmullRomCurve3([
      end.clone(),
      end.clone().add(new THREE.Vector3(direction * halfWidth * 0.34, lift * 0.16, 0.015)),
      end.clone().add(new THREE.Vector3(direction * halfWidth * 0.76, lift * 0.58, 0.020)),
      end.clone().add(new THREE.Vector3(direction * halfWidth, lift, 0.018)),
    ]));
  }

  geometryFor(entry) {
    const chapter = entry.kind === 'chapter';
    const radialSegments = 6;
    const supportRadius = branchRadiusForKind(entry.kind) * 0.50;
    const parts = [
      this.tubeGeometry(
        entry.curve,
        chapter ? 14 : 5,
        branchRadiusForKind(entry.kind),
        radialSegments,
      ),
      ...this.supportCurves(entry).map((curve) => this.tubeGeometry(
        curve,
        chapter ? 7 : 5,
        supportRadius,
        radialSegments,
        0.22,
      )),
    ];
    const geometry = mergeGeometries(parts, false);
    for (const part of parts) part.dispose();
    return geometry;
  }

  rebuildBatch() {
    if (this.batch) {
      this.batch.geometry.dispose();
      this.batch.removeFromParent();
      this.batch = null;
    }
    const geometries = this.entries
      .filter((entry) => entry.visible)
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
      anchor.userData.frameDistance = 6.4 + (Number(this.snapshot.treeAge) || 0) * 2.4;
      this.anchorGroup.add(anchor);
      this.anchors.set(`${entry.kind}:${entry.id}`, anchor);
    }
  }

  async runGrowth(entry, timeline, reverse = false) {
    const geometry = this.geometryFor(entry);
    const mesh = new THREE.Mesh(geometry, this.material);
    const bud = new THREE.Mesh(
      new THREE.SphereGeometry(branchRadiusForKind(entry.kind) * 1.08, 10, 6),
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
