import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from 'playwright';

const output = resolve(process.argv[3] ?? 'build/qa/organic-tree-runtime', new Date().toISOString().replaceAll(':', '-'));
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true, args: ['--use-angle=swiftshader'],
});
const context = await browser.newContext({ viewport: { width: 430, height: 932 },
  recordVideo: { dir: resolve(output, 'video'), size: { width: 430, height: 932 } } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
try {
  await page.goto(process.argv[2] ?? 'http://127.0.0.1:8789/');
  await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
  await page.getByRole('button', { name: '成熟', exact: true }).waitFor();
  await page.locator('#app_boot_cover').waitFor({ state: 'detached' });
  await page.waitForTimeout(1800);
  await page.screenshot({ path: resolve(output, 'young-430.png') });
  await page.evaluate(() => {
    const intervals = [];
    const end = performance.now() + 2600;
    let previous;
    function sample(now) {
      if (previous !== undefined) intervals.push(now - previous);
      previous = now;
      if (now < end) requestAnimationFrame(sample);
      else {
        intervals.sort((a, b) => a - b);
        window.__organicTiming = { frames: intervals.length,
          p95Ms: intervals[Math.floor(intervals.length * .95)], worstMs: intervals.at(-1) };
      }
    }
    requestAnimationFrame(sample);
  });
  await page.getByRole('button', { name: '成熟', exact: true }).click();
  await page.waitForTimeout(400);
  await page.screenshot({ path: resolve(output, 'growing-430.png') });
  await page.waitForTimeout(1400);
  await page.screenshot({ path: resolve(output, 'mature-430.png') });
  for (const name of ['左枝牌', '右枝牌']) {
    const hit = await page.getByRole('button', { name, exact: true }).boundingBox();
    const style = await page.addStyleTag({ content: 'flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }' });
    await page.mouse.click(hit.x + hit.width / 2, hit.y + hit.height / 2);
    await style.evaluate(element => element.remove());
    await page.getByText(`命中：${name}`, { exact: true }).waitFor();
  }
  await page.waitForFunction(() => window.__organicTiming);
  const timing = await page.evaluate(() => window.__organicTiming);
  assert.ok(!(await readFile(resolve(output, 'young-430.png'))).equals(await readFile(resolve(output, 'mature-430.png'))));
  await page.getByRole('button', { name: '近景', exact: true }).click();
  await page.waitForTimeout(700);
  await page.screenshot({ path: resolve(output, 'close-430.png') });
  await page.getByRole('button', { name: '全景', exact: true }).click();
  await page.setViewportSize({ width: 910, height: 800 });
  await page.waitForTimeout(700);
  await page.screenshot({ path: resolve(output, 'mature-910.png') });
  assert.deepEqual(errors, []);
  await writeFile(resolve(output, 'result.json'), JSON.stringify({ output, errors, timing,
    scope: '独立运行时入口，仅验证真实材质与连续树龄，不代表正式大纲页验收或视觉通过。' }, null, 2));
  console.log(JSON.stringify({ output, errors }));
} finally {
  await context.close();
  await browser.close();
}
