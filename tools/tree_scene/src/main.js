import { MagicTreeScene } from './MagicTreeScene.js';
import { decodeCommand, encodeEvent } from './protocol.js';

const canvas = document.querySelector('#tree-scene');
const parameters = new URLSearchParams(window.location.search);
const bridgeToken = parameters.get('token') ?? '';
const treeScene = new MagicTreeScene({
  canvas,
  assetUrl: parameters.get('model') ?? '../3d/magic_tree/magic_tree.glb',
});

let sessionId = 'bootstrap';
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

function normalizeSnapshot(snapshot = {}) {
  return {
    ...snapshot,
    treeAge: snapshot.structuralAge ?? snapshot.treeAge ?? 0,
    activeChapterId: snapshot.focusedChapterId ?? snapshot.activeChapterId ?? null,
  };
}

async function playMutation(payload = {}) {
  const mutation = payload.mutation ?? {};
  const snapshot = normalizeSnapshot(payload.snapshot);
  const chapters = snapshot.chapters ?? [];
  emit('tree.mutationStarted', { type: mutation.type, id: mutation.nodeId });
  const agePromise = treeScene.setAge(snapshot.treeAge, {
    animate: mutation.structuralAgeChanged,
  });
  await new Promise((resolve) => requestAnimationFrame(resolve));
  if (mutation.type === 'addChapter') {
    const chapter = chapters.find((item) => item.id === mutation.nodeId);
    if (chapter) {
      emit('tree.branchGrowthStarted', { kind: 'chapter', id: chapter.id });
      await Promise.all([agePromise, treeScene.growChapter(chapter)]);
    }
  } else if (mutation.type === 'addSection') {
    const chapter = chapters.find((item) => item.id === mutation.parentId);
    const section = chapter?.sections?.find((item) => item.id === mutation.nodeId);
    if (section) {
      emit('tree.branchGrowthStarted', { kind: 'section', id: section.id });
      await Promise.all([
        agePromise,
        treeScene.growSection({ ...section, chapterId: chapter.id }),
      ]);
    }
  } else {
    await agePromise;
  }
  await treeScene.setAge(snapshot.treeAge, { animate: false });
  await treeScene.sync(snapshot);
  emit('tree.mutationCompleted', { type: mutation.type, id: mutation.nodeId });
}

async function receive(raw) {
  const command = decodeCommand(raw);
  sessionId = command.sceneSessionId;
  if (command.type === 'scene.init') {
    emit('scene.ready', { renderer: 'WebGLRenderer', quality: treeScene.quality.name });
  } else if (command.type === 'scene.ping') {
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
    paused = true;
    emit('scene.paused');
  } else if (command.type === 'scene.resume') {
    paused = false;
    emit('scene.resumed');
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
  paused = true;
  emit('scene.contextLost');
});

let paused = false;
let lastProjectionAt = 0;
function render() {
  if (!paused) {
    treeScene.render();
    const now = performance.now();
    if (now - lastProjectionAt >= 100) {
      lastProjectionAt = now;
      emit('tree.visibleLabels', { labels: treeScene.visibleLabels() });
    }
  }
  requestAnimationFrame(render);
}

window.addEventListener('resize', () => treeScene.resize());

try {
  await treeScene.load();
  render();
  emit('scene.ready', { renderer: 'WebGLRenderer', quality: treeScene.quality.name });
} catch (error) {
  emit('scene.error', { message: String(error) });
  throw error;
}
