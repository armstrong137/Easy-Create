import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { KTX2Loader } from 'three/addons/loaders/KTX2Loader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';

import { BranchSystem } from './BranchSystem.js';
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
    this.quality = new QualityManager({
      devicePixelRatio: window.devicePixelRatio || 1,
      hardwareConcurrency: navigator.hardwareConcurrency || 4,
    }).initialProfile();
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
    this.root = null;
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
    let barkMaterial = null;
    const leafMaterials = [];
    this.root.traverse((object) => {
      if (object.name.startsWith('TrunkMarker_')) markers.push(object);
      if (object.userData?.ec_role === 'magic_emissive') object.visible = false;
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
          material.emissive?.set(0x17230d);
          material.emissiveIntensity = 0.22;
          material.needsUpdate = true;
          if (leafMaterials.length < 2 && !leafMaterials.includes(material)) {
            leafMaterials.push(material.clone());
          }
        }
        if (object.userData?.ec_role === 'main_tree') barkMaterial = materials[0];
        object.castShadow = this.quality.shadows && !isLeaf;
        object.receiveShadow = this.quality.shadows;
      }
      if (object.morphTargetDictionary && object.morphTargetInfluences) {
        channels.push(object);
      }
    });

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
    });
    this.branchSystem = new BranchSystem({
      root: this.root,
      markers,
      barkMaterial,
      leafSystem,
    });
    await this.growth.setAge(0.08, { animate: false });
    return this;
  }

  setAge(age, options) {
    if (!this.growth) return Promise.resolve();
    return this.growth.setAge(age, options);
  }

  sync(snapshot) {
    this.branchSystem?.sync(snapshot);
  }

  growChapter(chapter) {
    return this.branchSystem?.growChapter(chapter, this.timeline) ?? Promise.resolve();
  }

  growSection(section) {
    return this.branchSystem?.growSection(section, this.timeline) ?? Promise.resolve();
  }

  update() {
    const dt = Math.min(this.clock.getDelta(), 1 / 20);
    this.timeline.update(dt);
    this.growth?.update(dt);
    const age = this.growth?.getState().age ?? 0.08;
    const focusHeight = 0.65 + 4.1 * age;
    this.camera.position.y = focusHeight;
    this.camera.position.z = 16 + 19 * age;
    this.camera.lookAt(0, focusHeight, 0);
  }

  render() {
    this.update();
    this.renderer.render(this.scene, this.camera);
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
