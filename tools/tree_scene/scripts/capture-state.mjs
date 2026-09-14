import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://127.0.0.1:8790/assets/tree_scene/index.html';
const age = Number(process.argv[3] ?? 1);
const output = resolve(process.argv[4] ?? `../../../build/magic_tree/browser/state_${age}.png`);
const mode = process.argv[5] ?? '';
const bare = mode === '--bare';
const dense = mode === '--dense';
await mkdir(resolve(output, '..'), { recursive: true });

const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--enable-webgl', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 430, height: 932 } });
const errors = [];
page.on('console', (message) => {
  if (message.type() === 'error') errors.push(`console: ${message.text()}`);
});
page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
await page.addInitScript(() => {
  window.__captureEvents = [];
  window.addEventListener('message', (event) => {
    if (typeof event.data !== 'string') return;
    try {
      const envelope = JSON.parse(event.data);
      if (envelope.source === 'easy-create-tree-scene') {
        window.__captureEvents.push(envelope.event);
      }
    } catch (_) {}
  });
});
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForFunction(() => Boolean(window.EasyCreateTreeScene));
await page.waitForFunction(() => window.__captureEvents.some((event) => event.type === 'scene.ready'));
await page.evaluate(async ({ treeAge, bareScene, denseScene }) => {
  const chapters = denseScene
    ? Array.from({ length: 10 }, (_, index) => ({
      id: index + 1,
      title: index === 0 ? '引子' : `第${index}章`,
      sections: index === 9
        ? [{ id: 101, title: '第一节' }, { id: 102, title: '第二节' }]
        : [],
    }))
    : [{ id: 1, title: '引子', sections: [{ id: 11, title: '第一节' }] }];
  const activeChapterId = denseScene ? 10 : 1;
  const command = bareScene ? {
    protocolVersion: 1,
    sceneSessionId: 'capture-state',
    sequence: 1,
    type: 'tree.setAge',
    payload: { age: treeAge, animate: false },
  } : {
    protocolVersion: 1,
    sceneSessionId: 'capture-state',
    sequence: 1,
    type: 'tree.sync',
    payload: {
      treeAge,
      activeChapterId,
      activeSectionId: denseScene ? 102 : 11,
      chapters,
    },
  };
  await window.EasyCreateTreeScene.receive(command);
}, { treeAge: age, bareScene: bare, denseScene: dense });
await page.waitForTimeout(500);
await page.screenshot({ path: output });
const events = await page.evaluate(() => window.__captureEvents);
await browser.close();
console.log(JSON.stringify({ output, errors, events: events.slice(-8) }, null, 2));
