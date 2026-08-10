import { MagicTreeScene } from './MagicTreeScene.js';
import { decodeCommand, encodeEvent } from './protocol.js';

const canvas = document.querySelector('#tree-scene');
const treeScene = new MagicTreeScene({ canvas });

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

async function receive(raw) {
  const command = decodeCommand(raw);
  sessionId = command.sceneSessionId;
  if (command.type === 'scene.ping') {
    emit('scene.pong');
  } else if (command.type === 'tree.setAge') {
    await treeScene.setAge(command.payload?.age, {
      animate: command.payload?.animate !== false,
      durationMs: command.payload?.durationMs ?? 900,
    });
    emit('tree.ageSettled', treeScene.growth?.getState());
  } else if (command.type === 'tree.sync') {
    await treeScene.sync(command.payload);
    emit('tree.synced');
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
  receive(event.data.command);
});

function render() {
  treeScene.render();
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
