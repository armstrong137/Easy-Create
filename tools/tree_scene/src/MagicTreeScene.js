import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { KTX2Loader } from 'three/addons/loaders/KTX2Loader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';

import { BranchSystem } from './BranchSystem.js';
import { CameraSystem, treeFrameForAge } from './CameraSystem.js';
import { InteractionSystem } from './InteractionSystem.js';
import { LabelSystem } from './LabelSystem.js';
import { LeafSystem } from './LeafSystem.js';
import { QualityManager } from './QualityManager.js';
import { SceneTimeline } from './SceneTimeline.js';
import { TreeGrowthSystem } from './TreeGrowthSystem.js';

export class MagicTreeScene {
  constructor({ canvas, assetUrl = '../3d/magic_tree/magic_tree.glb' }) {
    this.canvas = canvas;
    this.assetUrl = assetUrl;
    this.clock = new THREE.Clock();
    this.timeline = new SceneTimeline();
    this.qualityManager = new QualityManager({
      devicePixelRatio: window.devicePixelRatio || 1,
      hardwareConcurrency: navigator.hardwareConcurrency || 4,
    });
    this.quality = this.qualityManager.currentProfile;
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: false,
      antialias: this.quality.antialias,
      powerPreference: 'high-performance',
    });
    this.renderer.setPixelRatio(this.quality.pixelRatio);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.08;
    this.renderer.shadowMap.enabled = this.quality.shadows;
    this.renderer.setClearColor(0xfdf6ec, 1);

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.1, 80);
    this.camera.position.set(0, 3.5, 13.4);
    this.camera.lookAt(0, 3.5, 0);
    this.growth = null;
    this.branchSystem = null;
    this.labelSystem = null;
    this.cameraSystem = null;
    this.interactionSystem = null;
    this.root = null;
    this.magicVeins = [];
    this.autoFrame = true;
    this.lastInteractionAt = null;
    this.addLights();
    this.resize();
  }

  async load() {
    const ktx2 = new KTX2Loader()
      .setTranscoderPath('./vendor/addons/libs/basis/')
      .detectSupport(this.renderer);
    const loader = new GLTFLoader()
      .setKTX2Loader(ktx2)
      .setMeshoptDecoder(MeshoptDecoder);
    const gltf = await loader.loadAsync(this.assetUrl);
    this.root = gltf.scene;
    this.root.name = 'MagicTreeRoot';
    this.scene.add(this.root);

    const channels = [];
    const markers = [];
    let crownGuide = null;
    let leafPrototype = null;
    let mainTreeRole = null;
    let rootRole = null;
    let barkMaterial = null;
    const leafMaterials = [];
    this.root.traverse((object) => {
      if (object.name.startsWith('TrunkMarker_')) markers.push(object);
      if (object.name === 'CrownGuide') crownGuide = object;
      if (object.userData?.ec_role === 'main_tree') mainTreeRole = object;
      if (object.userData?.ec_role === 'root_flare') rootRole = object;
      if (object.userData?.ec_role === 'magic_emissive') {
        object.visible = false;
        this.magicVeins.push(object);
      }
      if (object.userData?.ec_role === 'leaf_prototype') {
        leafPrototype = object;
        object.visible = false;
      }
      if (object.userData?.ec_role === 'soil_mound') object.visible = false;
      if (object.userData?.ec_role === 'moss_patches') object.visible = false;
      if (object.isMesh) {
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        let isLeaf = false;
        for (const material of materials) {
          if (!material?.name.startsWith('Leaf')) continue;
          isLeaf = true;
          material.alphaTest = 0.42;
          material.transparent = false;
          material.depthWrite = true;
          material.side = THREE.DoubleSide;
          material.emissive?.set(0x2c4815);
          material.emissiveIntensity = 0.38;
          material.needsUpdate = true;
          if (leafMaterials.length < 2 && !leafMaterials.includes(material)) {
            leafMaterials.push(material.clone());
          }
        }
        object.castShadow = this.quality.shadows && !isLeaf;
        object.receiveShadow = this.quality.shadows;
      }
      if (object.morphTargetDictionary && object.morphTargetInfluences) {
        channels.push(object);
      }
    });
    mainTreeRole?.traverse((object) => {
      if (barkMaterial || !object.isMesh) return;
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      barkMaterial = materials.find((material) => !material?.name.startsWith('Leaf')) ?? null;
    });
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(40, 40),
      new THREE.ShadowMaterial({ color: 0x3a2a18, opacity: 0.10 }),
    );
    ground.name = 'GroundPlane';
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = 0.0;
    ground.receiveShadow = this.quality.shadows;
    this.scene.add(ground);

    const mixer = new THREE.AnimationMixer(this.root);
    const idle = THREE.AnimationClip.findByName(gltf.animations, 'idle_breath');
    if (idle) mixer.clipAction(idle).play();
    this.growth = new TreeGrowthSystem({ root: this.root, morphChannels: channels, mixer });
    this.root.updateMatrixWorld(true);
    markers.sort((left, right) => left.name.localeCompare(right.name));
    const leafSystem = new LeafSystem({
      root: this.root,
      capacity: 5000,
      materials: leafMaterials.length === 2 ? leafMaterials : null,
      prototype: leafPrototype,
    });
    if (crownGuide) leafSystem.setCrownGuide(crownGuide);
    this.branchSystem = new BranchSystem({
      root: this.root,
      markers,
      barkMaterial,
      leafSystem,
    });
    this.labelSystem = new LabelSystem({
      root: this.root,
      branchSystem: this.branchSystem,
      camera: this.camera,
      barkMaterial,
    });
    this.cameraSystem = new CameraSystem({
      camera: this.camera,
      treeRoot: this.root,
      branchSystem: this.branchSystem,
      timeline: this.timeline,
    });
    this.interactionSystem = new InteractionSystem({ camera: this.camera });
    await this.growth.setAge(0.08, { animate: false });
    leafSystem.setTreeAge(0.08);
    return this;
  }

  setAge(age, options) {
    if (!this.growth) return Promise.resolve();
    return this.growth.setAge(age, options);
  }

  waitForGrowthLead(progress = 0.08) {
    return this.growth?.waitForProgress(progress) ?? Promise.resolve();
  }

  async sync(snapshot) {
    this.snapshot = structuredClone(snapshot);
    this.branchSystem?.sync(snapshot);
    this.branchSystem?.leafSystem?.setTreeAge(snapshot.treeAge ?? 0);
    this.labelSystem?.sync(snapshot);
    this.interactionSystem?.setPickRoots(this.labelSystem?.pickRoots ?? []);
    this.autoFrame = false;
    await this.cameraSystem?.focusDefault(snapshot, { animate: false });
  }

  focusChapter(id, options) {
    this.autoFrame = false;
    if (this.snapshot) {
      this.snapshot.activeChapterId = id;
      this.snapshot.activeSectionId = null;
      this.branchSystem?.sync(this.snapshot);
      this.labelSystem?.sync(this.snapshot);
      this.interactionSystem?.setPickRoots(this.labelSystem?.pickRoots ?? []);
    }
    return this.cameraSystem?.focusChapter(id, options) ?? Promise.resolve();
  }

  focusSection(chapterId, sectionId, options) {
    this.autoFrame = false;
    if (this.snapshot) {
      this.snapshot.activeChapterId = chapterId;
      this.snapshot.activeSectionId = sectionId;
      this.labelSystem?.sync(this.snapshot);
      this.interactionSystem?.setPickRoots(this.labelSystem?.pickRoots ?? []);
    }
    return this.cameraSystem?.focusSection(chapterId, sectionId, options) ?? Promise.resolve();
  }

  pan(delta) {
    this.beginInteraction();
    this.autoFrame = false;
    this.cameraSystem?.panBy(delta);
  }

  hitTest(ndcX, ndcY) {
    this.beginInteraction();
    return this.interactionSystem?.hitTest(ndcX, ndcY) ?? null;
  }

  visibleLabels() {
    return this.labelSystem?.projections() ?? [];
  }

  growChapter(chapter) {
    return this.branchSystem?.growChapter(chapter, this.timeline) ?? Promise.resolve();
  }

  growSection(section) {
    return this.branchSystem?.growSection(section, this.timeline) ?? Promise.resolve();
  }

  removeChapter(id) {
    return this.branchSystem?.removeChapter(id, this.timeline) ?? Promise.resolve();
  }

  removeSection(id) {
    return this.branchSystem?.removeSection(id, this.timeline) ?? Promise.resolve();
  }

  update() {
    const dt = Math.min(this.clock.getDelta(), 1 / 20);
    this.timeline.update(dt);
    this.growth?.update(dt);
    const treeAge = this.growth?.getState().age ?? 0;
    this.branchSystem?.leafSystem?.setTreeAge(treeAge);
    if (this.autoFrame) {
      const age = this.growth?.getState().age ?? 0.08;
      const frame = treeFrameForAge(age);
      this.camera.position.copy(frame.position);
      this.camera.lookAt(frame.target);
    }
    this.labelSystem?.update();
    if (this.lastInteractionAt != null) {
      const next = this.qualityManager.settleInteraction(
        performance.now() - this.lastInteractionAt,
      );
      if (next.name !== this.quality.name) this.applyQuality(next);
    }
  }

  render() {
    this.update();
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    this.labelSystem?.clear();
    this.branchSystem?.leafSystem?.dispose();
    this.renderer.dispose();
  }

  setQuality(name) {
    return this.applyQuality(this.qualityManager.select(name));
  }

  beginInteraction() {
    this.lastInteractionAt = performance.now();
    return this.applyQuality(
      this.qualityManager.beginInteraction(this.lastInteractionAt),
    );
  }

  applyQuality(profile) {
    this.quality = profile;
    this.renderer.setPixelRatio(profile.pixelRatio);
    this.renderer.shadowMap.enabled = profile.shadows;
    this.branchSystem?.leafSystem?.setLimit(profile.leafInstances);
    if (this.branchSystem?.snapshot) this.branchSystem.sync(this.branchSystem.snapshot);
    return profile;
  }

  restoreContext() {
    this.renderer.resetState();
    this.applyQuality(this.qualityManager.currentProfile);
    this.resize();
  }

  telemetry() {
    const info = this.renderer.info;
    const branch = this.branchSystem?.getMetrics() ?? {};
    return {
      quality: this.quality.name,
      pixelRatio: this.quality.pixelRatio,
      drawCalls: info.render.calls,
      triangles: info.render.triangles,
      textures: info.memory.textures,
      geometries: info.memory.geometries,
      programs: info.programs?.length ?? 0,
      branch,
      textureBudgetMiB: this.quality.textureBudgetMiB,
    };
  }

  resize(width = window.innerWidth, height = window.innerHeight) {
    const safeWidth = Math.max(1, width);
    const safeHeight = Math.max(1, height);
    this.renderer.setSize(safeWidth, safeHeight, false);
    this.camera.aspect = safeWidth / safeHeight;
    this.camera.updateProjectionMatrix();
  }

  addLights() {
    this.scene.add(new THREE.HemisphereLight(0xfff4dc, 0x24301b, 2.2));
    const key = new THREE.DirectionalLight(0xffc777, 3.4);
    key.position.set(-6, 10, 8);
    key.castShadow = this.quality.shadows;
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0xcce79a, 1.5);
    rim.position.set(6, 7, -5);
    this.scene.add(rim);
  }
}
