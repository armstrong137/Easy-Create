import * as THREE from 'three';

import { decodeCommand, encodeEvent } from './protocol.js';

const canvas = document.querySelector('#tree-scene');
const renderer = new THREE.WebGLRenderer({
  canvas,
  alpha: true,
  antialias: true,
  powerPreference: 'high-performance',
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0xfdf6ec);
const camera = new THREE.PerspectiveCamera(
  34,
  window.innerWidth / window.innerHeight,
  0.1,
  100,
);
camera.position.set(0, 1.8, 8);

const light = new THREE.HemisphereLight(0xfff4dc, 0x21301c, 2.2);
scene.add(light);

let sessionId = 'bootstrap';
let outgoingSequence = 0;

function emit(type, payload = null) {
  const event = encodeEvent({
    sceneSessionId: sessionId,
    sequence: outgoingSequence++,
    type,
    payload,
  });
  window.parent?.postMessage({ source: 'easy-create-tree-scene', event }, '*');
  window.TreeSceneBridge?.postMessage(JSON.stringify(event));
}

function receive(raw) {
  const command = decodeCommand(raw);
  sessionId = command.sceneSessionId;
  if (command.type === 'scene.ping') {
    emit('scene.pong');
  }
}

window.EasyCreateTreeScene = Object.freeze({ receive });
window.addEventListener('message', (event) => {
  if (event.data?.source !== 'easy-create-flutter') return;
  receive(event.data.command);
});

function render() {
  renderer.render(scene, camera);
  requestAnimationFrame(render);
}
render();
emit('scene.ready', { renderer: 'WebGLRenderer', threeRevision: THREE.REVISION });
