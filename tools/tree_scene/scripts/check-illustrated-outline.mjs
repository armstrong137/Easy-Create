import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://127.0.0.1:8780/';
const runId = new Date().toISOString().replaceAll(':', '-');
const output = resolve(process.argv[3] ?? '../../build/illustrated-outline-check', runId);
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
  args: ['--use-angle=swiftshader'],
});
const page = await browser.newPage({
  viewport: { width: 430, height: 932 },
  recordVideo: process.argv.includes('--audit-overview') || process.argv.includes('--audit-growth')
    ? { dir: resolve(output, 'video'), size: { width: 430, height: 932 } }
    : undefined,
});
const errors = [];
let phase = '首页启动';
page.on('pageerror', (error) => errors.push({ phase, message: error.message }));
page.on('console', (message) => {
  if (message.type() === 'error') errors.push({ phase, message: message.text() });
});
const captures = [];
async function capture(name) {
  // 等待已有 240ms 延迟和 920ms 生长播放完毕，只记录稳定态。
  await page.waitForTimeout(1500);
  await page.screenshot({ path: resolve(output, `${name}.png`) });
  captures.push({ name, text: await page.locator('body').innerText() });
}
try {
  // 独立临时浏览器上下文，只通过正式 UI 建数据，不触碰用户的小说。
  await page.goto(url);
  await page.locator('flt-semantics-placeholder').evaluate((element) => element.click());
  await page.getByText('Create Something', { exact: true }).click({ timeout: 30000 });
  await page.locator('input').click();
  // Flutter 编辑桥接需真实键盘事件，直接改 DOM input 值不代表控制器收到输入。
  await page.locator('input').pressSequentially('Visual QA', { delay: 60 });
  await page.getByText('诞生', { exact: true }).click();
  await page.getByText('Visual QA', { exact: true }).waitFor({ timeout: 30000 });
  await page.waitForTimeout(6000);
  phase = '大纲页';
  await page.mouse.click(215, 440);
  const addChapter = page.getByRole('button', { name: '新增章节', exact: true });
  const addSection = page.getByRole('button', { name: '新增小节', exact: true });
  await addChapter.waitFor();
  await capture('00-empty-430');
  await addChapter.click();
  await page.getByRole('button', { name: '引子', exact: true }).waitFor();
  await capture('01-prologue-430');
  if (process.argv.includes('--audit-growth')) {
    await page.evaluate(() => {
      const intervals = [];
      const end = performance.now() + 2000;
      let previous;
      function sample(now) {
        if (previous !== undefined) intervals.push(now - previous);
        previous = now;
        if (now < end) requestAnimationFrame(sample);
        else {
          intervals.sort((a, b) => a - b);
          window.__treeGrowthTiming = {
            frames: intervals.length,
            p95Ms: intervals[Math.floor(intervals.length * .95)],
            worstMs: intervals.at(-1),
          };
        }
      }
      requestAnimationFrame(sample);
    });
  }
  await addChapter.click();
  await page.getByRole('button', { name: '第一章', exact: true }).waitFor();
  if (process.argv.includes('--audit-growth')) {
    for (const [name, delay] of [['growth-early', 260], ['growth-middle', 240], ['growth-settled', 700]]) {
      await page.waitForTimeout(delay);
      await page.screenshot({ path: resolve(output, `${name}.png`) });
    }
    await page.waitForFunction(() => window.__treeGrowthTiming);
    await writeFile(resolve(output, 'growth-timing.json'), JSON.stringify(await page.evaluate(() => window.__treeGrowthTiming), null, 2));
  }
  await addSection.click();
  await page.getByRole('button', { name: '第一节', exact: true }).waitFor();
  await addSection.click();
  await page.getByRole('button', { name: '第二节', exact: true }).waitFor();
  await capture('04-four-branches-430');
  const titles = ['第二章', '第三章', '第四章', '第五章', '第六章', '第七章', '第八章', '第九章'];
  for (const title of titles) {
    await addChapter.click();
    await page.getByRole('button', { name: title, exact: true }).waitFor();
    await page.waitForTimeout(1300);
  }
  await capture('12-mature-430');
  const visibleChapters = page.getByRole('button', { name: /^(引子|第[一二三四五六七八九十]+章)$/ });
  assert.equal(await visibleChapters.count(), 2, '左侧只能显示两章');
  if (process.argv.includes('--audit-overview')) {
    await page.getByRole('button', { name: '全景', exact: true }).click();
    await capture('overview-complete-430');
    assert.equal(await visibleChapters.count(), 2, '全景不改变章节窗口');
    const chapterHit = await page.getByRole('button', { name: '第九章', exact: true }).boundingBox();
    // 语义层的点击会转成辅助操作；双击需验证实际 Flutter 指针路径。
    const pointerStyle = await page.addStyleTag({ content: 'flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }' });
    await page.mouse.dblclick(chapterHit.x + chapterHit.width / 2, chapterHit.y + chapterHit.height / 2, { delay: 60 });
    await pointerStyle.evaluate(element => element.remove());
    await page.getByText('重命名这一章', { exact: true }).waitFor();
    await capture('overview-chapter-hit-430');
    await page.getByText('取消', { exact: true }).click();
    await page.getByRole('button', { name: '返回章节', exact: true }).click();
    await capture('overview-return-430');
  }
  if (process.argv.includes('--audit-history')) {
    phase = '历史章节镜头验收';
    // 取不被左右枝牌遮挡的下段树干；标签替换不能充当镜头移动的证据。
    const clip = { x: 200, y: 650, width: 30, height: 160 };
    const before = await page.screenshot({ clip });
    for (let index = 0; index < 9; index += 1) {
      await page.mouse.move(80, 590);
      await page.mouse.down();
      await page.mouse.move(80, 780, { steps: 16 });
      await page.mouse.up();
      await page.waitForTimeout(600);
    }
    await page.getByRole('button', { name: '引子', exact: true }).waitFor();
    await capture('history-prologue-430');
    const after = await page.screenshot({ clip });
    const treeRegionChanged = !before.equals(after);
    await writeFile(resolve(output, 'history-audit.json'), JSON.stringify({
      reachedPrologue: true, clip, treeRegionChanged,
      note: '区域完全相同可证伪本次镜头移动；区域不同仍需肉眼确认不是闪光或换树。',
    }, null, 2));
    assert.ok(treeRegionChanged, '滑回引子后树干区域完全未变：标签切换不等于镜头移动');
  }
  await page.setViewportSize({ width: 910, height: 800 });
  await capture('12-mature-910');
  if (process.argv.includes('--audit-overview')) {
    await page.getByRole('button', { name: '全景', exact: true }).click();
    await capture('overview-complete-910');
  }
  assert.deepEqual(errors, [], '浏览器不应发生运行错误');
  await writeFile(resolve(output, 'result.json'), JSON.stringify({
    runId, url,
    checksPassed: ['创建十章和两节', '末态语义窗口只有两章', '浏览器零错误'],
    visualAcceptance: '待人工对照参考图', captures, errors,
  }, null, 2));
  console.log(JSON.stringify({ output, captures: captures.map(({ name }) => name), errors }));
} catch (error) {
  await page.screenshot({ path: resolve(output, 'failure.png') });
  await writeFile(resolve(output, 'failure.json'), JSON.stringify({
    runId, error: String(error), text: await page.locator('body').innerText(), captures, errors,
  }, null, 2));
  throw error;
} finally {
  await browser.close();
}
