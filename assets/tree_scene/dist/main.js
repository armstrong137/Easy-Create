import { MagicTreeScene } from './MagicTreeScene.js';
import { playTreeMutation } from './MutationPlayer.js';
import { ProjectionReporter, summarizeFrameTimes } from './QualityManager.js';
import {
  createStartupErrorPayload,
  detectWebGL2Availability,
} from './StartupDiagnostics.js';
import { decodeCommand, encodeEvent } from './protocol.js';

const canvas = document.querySelector('#tree-scene');
const parameters = new URLSearchParams(window.location.search);
const bridgeToken = parameters.get('token') ?? '';
const modelUrl = parameters.get('model') ?? '../3d/magic_tree/magic_tree.glb';
const webgl2Available = detectWebGL2Availability();
let treeScene = null;
let bootReady = false;
let startupStage = 'iframeLoading';
let sessionId = parameters.get('session') ?? 'bootstrap';
let outgoingSequence = 0;

function emit(type, payload = null) {
  const event = encodeEvent({
    sceneSessionId: sessionId,
    sequence: outgoingSequence++,
    type,
    payload,
  });
  window.parent?.postMessage(JSON.stringify({
    source: 'easy-create-tree-scene',
    token: bridgeToken,
    event,
  }), '*');
  window.TreeSceneBridge?.postMessage(JSON.stringify(event));
}

function emitStartup(stage, payload = {}) {
  startupStage = stage;
  emit('scene.startup', { stage, ...payload });
}

emitStartup('iframeLoading');

function normalizeSnapshot(snapshot = {}) {
  return {
    ...snapshot,
    treeAge: snapshot.structuralAge ?? snapshot.treeAge ?? 0,
    activeChapterId: snapshot.focusedChapterId ?? snapshot.activeChapterId ?? null,
  };
}

async function playMutation(payload = {}) {
  await playTreeMutation({
    treeScene,
    emit,
    payload: {
      ...payload,
      snapshot: normalizeSnapshot(payload.snapshot),
    },
  });
}

async function receive(raw) {
  const command = decodeCommand(raw);
  sessionId = command.sceneSessionId;
  if (command.type === 'scene.init') {
    if (bootReady) {
      emit('scene.ready', {
        renderer: 'WebGLRenderer',
        quality: treeScene.quality.name,
      });
    } else {
      emit('scene.startup', { stage: startupStage });
    }
    return;
  }
  if (!treeScene) {
    emit('scene.error', createStartupErrorPayload({
      stage: startupStage,
      error: new Error('Magic tree renderer is unavailable'),
      webgl2Available,
      userAgent: navigator.userAgent,
      modelUrl,
    }));
    return;
  }
  if (command.type === 'scene.ping') {
    emit('scene.pong');
  } else if (command.type === 'tree.setAge') {
    await treeScene.setAge(command.payload?.age, {
      animate: command.payload?.animate !== false,
      durationMs: command.payload?.durationMs ?? 900,
    });
    emit('tree.ageSettled', treeScene.growth?.getState());
  } else if (command.type === 'tree.sync' || command.type === 'tree.syncSnapshot') {
    const snapshot = normalizeSnapshot(command.payload);
    await treeScene.setAge(snapshot.treeAge, { animate: false });
    await treeScene.sync(snapshot);
    emit('tree.synced');
  } else if (command.type === 'tree.playMutation') {
    treeScene.beginInteraction();
    await playMutation(command.payload);
  } else if (command.type === 'tree.focusChapter') {
    await treeScene.focusChapter(command.payload?.id, {
      animate: command.payload?.animate !== false,
    });
    emit('tree.chapterFocused', { id: command.payload?.id });
  } else if (command.type === 'tree.focusSection') {
    await treeScene.focusSection(command.payload?.chapterId, command.payload?.id, {
      animate: command.payload?.animate !== false,
    });
    emit('tree.sectionFocused', {
      chapterId: command.payload?.chapterId,
      id: command.payload?.id,
    });
  } else if (command.type === 'scene.pan') {
    treeScene.pan(command.payload?.delta ?? 0);
    emit('scene.panned');
  } else if (command.type === 'scene.hitTest') {
    emit('scene.hitResult', treeScene.hitTest(command.payload?.x, command.payload?.y));
  } else if (command.type === 'tree.setDragPoint') {
    emit('tree.hit', treeScene.hitTest(command.payload?.x, command.payload?.y));
  } else if (command.type === 'tree.endDrag') {
    emit('tree.hit', null);
  } else if (command.type === 'scene.pause') {
    stopLoop();
    emit('scene.paused');
  } else if (command.type === 'scene.resume') {
    startLoop();
    emit('scene.resumed');
  } else if (command.type === 'tree.setQuality') {
    const quality = treeScene.setQuality(command.payload?.quality);
    emit('scene.qualityChanged', quality);
  } else if (command.type === 'scene.disposeAssets') {
    paused = true;
    treeScene.dispose();
    emit('scene.disposed');
  } else if (command.type === 'tree.growChapter') {
    await treeScene.growChapter(command.payload);
    emit('tree.chapterGrown', { id: command.payload?.id });
  } else if (command.type === 'tree.growSection') {
    await treeScene.growSection(command.payload);
    emit('tree.sectionGrown', { id: command.payload?.id });
  }
}

window.EasyCreateTreeScene = Object.freeze({ receive });
window.addEventListener('message', (event) => {
  if (event.data?.source !== 'easy-create-flutter') return;
  if (bridgeToken && event.data?.token !== bridgeToken) return;
  receive(event.data.command);
});

canvas.addEventListener('webglcontextlost', (event) => {
  event.preventDefault();
  stopLoop();
  emit('scene.contextLost');
});

canvas.addEventListener('webglcontextrestored', () => {
  try {
    treeScene.restoreContext();
    projectionReporter.reset();
    startLoop();
    emit('scene.ready', {
      renderer: 'WebGLRenderer',
      quality: treeScene.quality.name,
      recovered: true,
    });
  } catch (error) {
    emit('scene.recoveryFailed', { message: String(error) });
  }
});

let paused = false;
let frameRequest = null;
let lastProjectionAt = 0;
let lastTelemetryAt = 0;
let previousFrameAt = null;
let sceneLoadMs = null;
const bootStartedAt = performance.now();
const frameTimes = [];
const projectionReporter = new ProjectionReporter();
function render() {
  if (paused) return;
  const frameStartedAt = performance.now();
  if (previousFrameAt != null) {
    frameTimes.push(frameStartedAt - previousFrameAt);
    if (frameTimes.length > 180) frameTimes.shift();
  }
  previousFrameAt = frameStartedAt;
  treeScene.render();
  const now = performance.now();
  if (now - lastProjectionAt >= 100) {
    lastProjectionAt = now;
    const labels = treeScene.visibleLabels();
    if (projectionReporter.shouldEmit(labels)) {
      emit('tree.visibleLabels', { labels });
    }
  }
  if (now - lastTelemetryAt >= 2000) {
    lastTelemetryAt = now;
    const heapBytes = performance.memory?.usedJSHeapSize;
    emit('scene.telemetry', {
      ...treeScene.telemetry(),
      frame: summarizeFrameTimes(frameTimes),
      sceneLoadMs,
      jsHeapMiB: Number.isFinite(heapBytes)
        ? Number((heapBytes / 1024 / 1024).toFixed(2))
        : null,
    });
  }
  frameRequest = requestAnimationFrame(render);
}

function startLoop() {
  if (!paused && frameRequest != null) return;
  paused = false;
  previousFrameAt = null;
  treeScene.clock.start();
  frameRequest = requestAnimationFrame(render);
}

function stopLoop() {
  paused = true;
  if (frameRequest != null) cancelAnimationFrame(frameRequest);
  frameRequest = null;
  treeScene.clock.stop();
}

window.addEventListener('resize', () => treeScene?.resize());
document.addEventListener('visibilitychange', () => {
  document.hidden ? stopLoop() : startLoop();
});

try {
  emitStartup('webglCreating');
  treeScene = new MagicTreeScene({ canvas, assetUrl: modelUrl });
  emitStartup('modelLoading');
  await treeScene.load();
  sceneLoadMs = Number((performance.now() - bootStartedAt).toFixed(1));
  treeScene.render();
  emitStartup('firstFrame');
  startLoop();
  bootReady = true;
  emitStartup('ready');
  emit('scene.ready', { renderer: 'WebGLRenderer', quality: treeScene.quality.name });
} catch (error) {
  const failedAt = startupStage;
  emitStartup('failed', { failedAt });
  emit('scene.error', createStartupErrorPayload({
    stage: failedAt,
    error,
    webgl2Available,
    userAgent: navigator.userAgent,
    modelUrl,
  }));
}
