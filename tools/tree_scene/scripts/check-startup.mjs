import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

import { chromium } from 'playwright';
import { PNG } from 'pngjs';

const disableWebgl = process.argv.includes('--disable-webgl');
const url = process.argv.find((argument) => argument.startsWith('http'))
  ?? 'http://127.0.0.1:4175/tree_scene/index.html';
const outputDir = resolve(import.meta.dirname, '..', '..', '..', 'build', 'magic_tree', 'browser');
await mkdir(outputDir, { recursive: true });

const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: disableWebgl
    ? ['--disable-webgl']
    : ['--enable-webgl', '--use-angle=swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 430, height: 932 } });
const browserErrors = [];
page.on('console', (message) => {
  if (message.type() === 'error') browserErrors.push(`console: ${message.text()}`);
});
page.on('pageerror', (error) => browserErrors.push(`pageerror: ${error.message}`));
page.on('requestfailed', (request) => {
  browserErrors.push(`request: ${request.url()} ${request.failure()?.errorText ?? ''}`);
});
await page.addInitScript(() => {
  window.__treeSceneStartupEvents = [];
  window.addEventListener('message', (event) => {
    if (typeof event.data !== 'string') return;
    try {
      const envelope = JSON.parse(event.data);
      if (envelope.source === 'easy-create-tree-scene') {
        window.__treeSceneStartupEvents.push(envelope.event);
      }
    } catch (_) {}
  });
});

await page.goto(`${url}?session=startup-check`, { waitUntil: 'networkidle' });
await page.waitForFunction(() => window.__treeSceneStartupEvents.some(
  (event) => event.type === 'scene.ready' || event.type === 'scene.error',
), null, { timeout: 15000 });
const events = await page.evaluate(() => window.__treeSceneStartupEvents);
const screenshot = await page.screenshot({
  path: resolve(outputDir, disableWebgl ? 'startup-error.png' : 'startup-ready.png'),
});
const png = PNG.sync.read(screenshot);
let nonBackground = 0;
for (let offset = 0; offset < png.data.length; offset += 4) {
  const difference =
    Math.abs(png.data[offset] - 253)
    + Math.abs(png.data[offset + 1] - 246)
    + Math.abs(png.data[offset + 2] - 236);
  if (difference > 36) nonBackground += 1;
}
const coverage = nonBackground / (png.width * png.height);
await browser.close();

const stages = events
  .filter((event) => event.type === 'scene.startup')
  .map((event) => event.payload?.stage);
const ready = events.find((event) => event.type === 'scene.ready');
const error = events.find((event) => event.type === 'scene.error');
const result = { disableWebgl, stages, ready, error, coverage, browserErrors };
console.log(JSON.stringify(result, null, 2));

if (disableWebgl) {
  if (!error || error.payload?.stage !== 'webglCreating') process.exitCode = 1;
} else {
  const expected = ['iframeLoading', 'webglCreating', 'modelLoading', 'firstFrame', 'ready'];
  if (!ready || expected.some((stage, index) => stages[index] !== stage) || coverage < 0.05) {
    process.exitCode = 1;
  }
}
