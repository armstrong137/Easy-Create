import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

import { chromium } from 'playwright';
import { PNG } from 'pngjs';

const url = process.argv[2] ?? 'http://127.0.0.1:4175/tree_scene/index.html';
const outputDir = resolve(import.meta.dirname, '..', '..', '..', 'build', 'magic_tree', 'browser');
await mkdir(outputDir, { recursive: true });

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
page.on('requestfailed', (request) => {
  errors.push(`request: ${request.url()} ${request.failure()?.errorText ?? ''}`);
});

await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(2500);
const state = await page.evaluate(() => ({
  ready: Boolean(window.EasyCreateTreeScene),
  canvasWidth: document.querySelector('canvas')?.width ?? 0,
  canvasHeight: document.querySelector('canvas')?.height ?? 0,
}));
const ages = [0.08, 0.25, 0.48, 0.72, 1];
const coverage = [];
for (const [index, age] of ages.entries()) {
  await page.evaluate(
    async ({ age, sequence }) => {
      await window.EasyCreateTreeScene.receive({
        protocolVersion: 1,
        sceneSessionId: 'browser-check',
        sequence,
        type: 'tree.setAge',
        payload: { age, animate: false },
      });
    },
    { age, sequence: index },
  );
  await page.waitForTimeout(120);
  const screenshot = await page.screenshot({
    path: resolve(outputDir, `age_${String(Math.round(age * 100)).padStart(3, '0')}.png`),
  });
  const png = PNG.sync.read(screenshot);
  let nonBackground = 0;
  for (let offset = 0; offset < png.data.length; offset += 4) {
    const difference =
      Math.abs(png.data[offset] - 253) +
      Math.abs(png.data[offset + 1] - 246) +
      Math.abs(png.data[offset + 2] - 236);
    if (difference > 36) nonBackground += 1;
  }
  coverage.push(nonBackground / (png.width * png.height));
}
await page.evaluate(async () => {
  await window.EasyCreateTreeScene.receive({
    protocolVersion: 1,
    sceneSessionId: 'browser-check',
    sequence: 20,
    type: 'tree.sync',
    payload: {
      treeAge: 1,
      chapters: Array.from({ length: 10 }, (_, chapterIndex) => ({
        id: 100 + chapterIndex,
        title: `第${chapterIndex + 1}章`,
        sections: Array.from({ length: 3 }, (_, sectionIndex) => ({
          id: 10000 + chapterIndex * 100 + sectionIndex,
          title: `第${sectionIndex + 1}节`,
        })),
      })),
    },
  });
});
await page.waitForTimeout(120);
await page.screenshot({ path: resolve(outputDir, 'branches.png') });
await browser.close();

console.log(JSON.stringify({ state, coverage, errors }, null, 2));
const coverageValid = coverage.every((ratio) => ratio >= 0.08 && ratio <= 0.78);
if (!state.ready || errors.length > 0 || !coverageValid) process.exitCode = 1;
