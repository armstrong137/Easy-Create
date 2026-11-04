import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const source = await readFile('assets/source/magic_tree/guides/ancient_tree_form_v1.svg', 'utf8');
const output = resolve('build/qa/authored-growth');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 900 } });
  await page.setContent('<body style="margin:0">' + source + '</body>');
  await page.evaluate(() => {
    const svg = document.querySelector('svg');
    const wood = Object.fromEntries([...svg.querySelectorAll('#wood-silhouette path')].map(path => [path.id, path]));
    const front = [...svg.querySelectorAll('#front-canopy path')];
    const rear = [...svg.querySelectorAll('#rear-canopy path')];
    const plaque = svg.querySelector('#plaque');
    const ridgeGroup = svg.querySelector('#lit-ridges');
    const ridgePaths = [...ridgeGroup.querySelectorAll('path')];
    const ridges = [
      [ridgePaths[0], 'trunk'],
      ...ridgePaths[1].getAttribute('d').match(/M[^M]+/g).map((d, index) => {
        const path = ridgePaths[1].cloneNode();
        path.setAttribute('d', d);
        ridgeGroup.append(path);
        return [path, ['trunk', 'left-limb', 'right-limb', 'near-root'][index]];
      }),
    ];
    ridgePaths[1].remove();
    const shadow = svg.querySelector('ellipse');
    const smooth = value => {
      const t = Math.max(0, Math.min(1, value));
      return t * t * (3 - 2 * t);
    };
    const label = document.createElementNS(svg.namespaceURI, 'text');
    label.setAttribute('x', '24');
    label.setAttribute('y', '34');
    label.setAttribute('fill', '#4e4536');
    label.setAttribute('font-size', '18');
    svg.append(label);

    // 各部位独立发育。母体只提供接点，子部位的长宽使用自己的时序。
    const parts = [
      ['trunk', [405, 800], null, .18, .34, 0],
      ['left-limb', [387, 559], 'trunk', .17, .20, .10],
      ['right-limb', [421, 570], 'trunk', .14, .17, .18],
      ['upper-fork', [371, 444], 'trunk', .18, .25, .08],
      ['near-root', [382, 651], 'trunk', .19, .28, .18],
      ['right-root', [432, 699], 'trunk', .17, .25, .23],
      ['plaque-support', [415, 635], 'trunk', .02, .02, .35],
      [front[0], [401, 214], 'trunk', .34, .46, .00],
      [front[1], [237, 268], 'upper-fork', .23, .33, .12],
      [front[2], [392, 329], 'trunk', .22, .27, .18],
      [front[3], [166, 424], 'left-limb', .25, .38, .10],
      [front[4], [663, 378], 'right-limb', .25, .38, .22],
      [rear[0], [224, 355], 'upper-fork', .17, .26, .24],
      [rear[1], [597, 314], 'right-limb', .18, .24, .28],
      [rear[2], [515, 510], 'right-limb', .12, .20, .30],
    ];
    window.renderGrowth = (age, near = false) => {
      const transforms = new Map();
      const matrices = new Map();
      for (const [part, [x, y], parent, initialX, initialY, onset] of parts) {
        const growth = smooth((age - onset) / (1 - onset));
        const sx = initialX + (1 - initialX) * growth;
        const sy = initialY + (1 - initialY) * growth;
        const [ax, ay] = parent ? transforms.get(parent)(x, y) : [x, y];
        const tx = ax - x * sx;
        const ty = ay - y * sy;
        const matrix = `matrix(${sx} 0 0 ${sy} ${tx} ${ty})`;
        (wood[part] ?? part).setAttribute('transform', matrix);
        matrices.set(part, matrix);
        transforms.set(part, (px, py) => [px * sx + tx, py * sy + ty]);
      }
      for (const [path, part] of ridges) path.setAttribute('transform', matrices.get(part));
      shadow.setAttribute('rx', String(58 + 239 * smooth(age)));
      const [px, py] = transforms.get('plaque-support')(520, 550);
      const size = smooth((age - .43) / .52);
      plaque.setAttribute('visibility', size > 0 ? 'visible' : 'hidden');
      plaque.setAttribute('transform', `translate(${px} ${py}) scale(${size}) translate(0 -78)`);
      svg.setAttribute('viewBox', near ? '315 369 390 439' : '0 0 800 900');
      label.setAttribute('x', near ? '327' : '24');
      label.setAttribute('y', near ? '386' : '34');
      label.setAttribute('font-size', near ? '9' : '18');
      label.textContent = `树龄 ${age.toFixed(2)} · ${(age * 10).toFixed(1)} 秒`;
    };
  });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  for (const [name, age, near] of [['young', 0], ['middle', .5], ['mature', 1], ['plaque-close', 1, true]]) {
    await page.evaluate(([age, near]) => window.renderGrowth(age, near), [age, near]);
    await page.screenshot({ path: resolve(output, `${name}.png`) });
  }
  const frames = [];
  for (let frame = 0; frame <= 100; frame++) {
    await page.evaluate(age => window.renderGrowth(age), frame / 100);
    frames.push(await page.screenshot({ type: 'jpeg', quality: 88 }));
  }
  if (errors.length) throw Error(errors.join('\n'));
  const ffmpeg = resolve(process.env.LOCALAPPDATA, 'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe');
  const encode = spawnSync(ffmpeg, ['-y', '-f', 'image2pipe', '-r', '10', '-c:v', 'mjpeg', '-i', 'pipe:0',
    '-c:v', 'libvpx', '-pix_fmt', 'yuv420p', resolve(output, 'growth.webm')],
  { input: Buffer.concat(frames), encoding: 'utf8' });
  if (encode.status !== 0) throw Error(encode.error?.message ?? encode.stderr);
  await writeFile(resolve(output, 'result.json'), JSON.stringify({ frames: 101, fps: 10, errors }, null, 2));
} finally {
  await browser.close();
}
