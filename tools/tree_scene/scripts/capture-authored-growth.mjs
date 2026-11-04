import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const source = await readFile('assets/source/magic_tree/guides/ancient_tree_form_v1.svg', 'utf8');
const output = resolve('build/qa/authored-joined-growth');
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

    // 每行独立定义高度、左缘和右缘，两套源截面使用同一组索引。
    const seedling = [
      [581, 404, 406], [599, 401, 406], [620, 396, 405], [646, 393, 405],
      [670, 391, 403], [692, 393, 405], [715, 397, 409], [738, 398, 412],
      [760, 395, 415], [781, 389, 422], [797, 377, 433], [801, 381, 430],
    ];
    const mature = [
      [172, 400, 404], [234, 410, 425], [305, 376, 411], [372, 367, 411],
      [438, 371, 425], [493, 358, 418], [550, 352, 416], [607, 356, 430],
      [666, 346, 453], [719, 328, 465], [775, 237, 551], [803, 377, 425],
    ];
    const columns = 5;
    const trunkFaces = [];
    for (let row = 0; row < mature.length - 1; row++) {
      for (let col = 0; col < columns - 1; col++) {
        const i = row * columns + col;
        trunkFaces.push([i, i + 1, i + columns], [i + 1, i + columns + 1, i + columns]);
      }
    }
    const trunkRidges = ridges.filter(([, part]) => part === 'trunk')
      .map(([path]) => [path, path.getAttribute('d')]);
    const limbs = [
      { id: 'left-limb', row: 6, side: -1, tip: [166, 424], young: [23, -13], old: [184, -143] },
      { id: 'right-limb', row: 5, side: 1, tip: [663, 378], young: [18, -11], old: [243, -143] },
      { id: 'plaque-support', row: 7, side: 1, tip: [520, 550], young: [2, -1], old: [79, -87] },
    ];
    const faces = [...trunkFaces];
    let vertexCount = mature.length * columns;
    for (const limb of limbs) {
      const edge = limb.side > 0 ? columns - 1 : 0;
      let a = limb.row * columns + edge;
      let b = a + columns;
      for (let step = 0; step < 4; step++) {
        const c = vertexCount++;
        const d = vertexCount++;
        const pair = [[a, c, b], [c, d, b]];
        faces.push(...(limb.side > 0 ? pair : pair.map(face => face.reverse())));
        a = c;
        b = d;
      }
      wood[limb.id].remove();
    }
    const edgeUses = new Map();
    for (const face of faces) {
      for (let i = 0; i < 3; i++) {
        const a = face[i], b = face[(i + 1) % 3];
        const key = a < b ? `${a}:${b}` : `${b}:${a}`;
        const uses = edgeUses.get(key) ?? [];
        uses.push([a, b]);
        edgeUses.set(key, uses);
      }
    }
    const boundary = new Map();
    for (const uses of edgeUses.values()) {
      if (uses.length === 1) boundary.set(...uses[0]);
      else if (uses.length !== 2 || uses[0][0] !== uses[1][1]) throw Error('木体存在不一致的共边');
    }
    const outline = [0];
    for (let next = boundary.get(0); next !== 0; next = boundary.get(next)) {
      if (next === undefined || outline.length >= boundary.size) throw Error('木体外轮廓未闭合');
      outline.push(next);
    }
    if (outline.length !== boundary.size) throw Error('木体存在额外轮廓');
    for (const [path, part] of ridges) {
      if (limbs.some(limb => limb.id === part)) path.remove();
    }

    // 各部位独立发育。母体只提供接点，子部位的长宽使用自己的时序。
    const parts = [
      ['upper-fork', [371, 444], 'trunk', .18, .25, .08],
      ['near-root', [382, 651], 'trunk', .19, .28, .18],
      ['right-root', [432, 699], 'trunk', .17, .25, .23],
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
      const growth = smooth(age);
      const sections = mature.map((row, i) => row.map((value, j) =>
        seedling[i][j] + (value - seedling[i][j]) * growth));
      const vertices = sections.flatMap(([y, left, right]) =>
        Array.from({ length: columns }, (_, col) => [left + (right - left) * col / (columns - 1), y]));
      const limbTransforms = [];
      for (const { id, row, side, tip, young, old } of limbs) {
        const edge = side > 0 ? columns - 1 : 0;
        const [a, b] = [vertices[row * columns + edge], vertices[(row + 1) * columns + edge]];
        const [dx, dy] = old.map((value, i) => young[i] + (value - young[i]) * growth);
        for (let step = 1; step <= 4; step++) {
          const t = step / 4;
          const width = (b[1] - a[1]) * (1 - .92 * t) / 2;
          const x = side * (Math.max(side * a[0], side * b[0]) + dx * t);
          const y = (a[1] + b[1]) / 2 + dy * (.25 * t + .75 * t * t);
          vertices.push([x, y - width], [x, y + width]);
        }
        const end = vertices.at(-1).map((value, i) => (value + vertices.at(-2)[i]) / 2);
        limbTransforms.push([id, (x, y) => [end[0] + (x - tip[0]) * dx / old[0],
          end[1] + (y - tip[1]) * dy / old[1]]]);
      }
      let minimumArea = Infinity;
      for (const [i, j, k] of faces) {
        const [a, b, c] = [vertices[i], vertices[j], vertices[k]];
        minimumArea = Math.min(minimumArea, (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]));
      }
      if (!(minimumArea > 0)) throw Error('木体截面翻面');
      wood.trunk.setAttribute('d', `M${outline.map(index => vertices[index]).join('L')}Z`);
      const mapTrunk = (x, y) => {
        const last = mature.findIndex(row => row[0] >= y);
        const i = Math.min(mature.length - 2, Math.max(0, last < 0 ? mature.length - 2 : last - 1));
        const t = (y - mature[i][0]) / (mature[i + 1][0] - mature[i][0]);
        const sample = rows => rows[i].map((value, j) => value + (rows[i + 1][j] - value) * t);
        const [, left, right] = sample(mature);
        const [py, nextLeft, nextRight] = sample(sections);
        return [nextLeft + (x - left) * (nextRight - nextLeft) / (right - left), py];
      };
      const transforms = new Map([['trunk', mapTrunk], ...limbTransforms]);
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
      for (const [path, part] of ridges) {
        if (matrices.has(part)) path.setAttribute('transform', matrices.get(part));
      }
      for (const [path, d] of trunkRidges) {
        path.setAttribute('d', d.replace(/(\d+) (\d+)/g, (_, x, y) => mapTrunk(+x, +y).join(' ')));
        path.setAttribute('stroke-width', String(1 + 4 * growth));
      }
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
      return { vertices: vertices.length, triangles: faces.length, sharedLimbEdges: limbs.length, minimumArea };
    };
  });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  for (const [name, age, near] of [['young', 0], ['middle', .5], ['mature', 1], ['plaque-close', 1, true]]) {
    await page.evaluate(([age, near]) => window.renderGrowth(age, near), [age, near]);
    await page.screenshot({ path: resolve(output, `${name}.png`) });
  }
  const frames = [];
  const trunkChecks = [];
  for (let frame = 0; frame <= 100; frame++) {
    trunkChecks.push(await page.evaluate(age => window.renderGrowth(age), frame / 100));
    frames.push(await page.screenshot({ type: 'jpeg', quality: 88 }));
  }
  if (errors.length) throw Error(errors.join('\n'));
  const ffmpeg = resolve(process.env.LOCALAPPDATA, 'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe');
  const encode = spawnSync(ffmpeg, ['-y', '-f', 'image2pipe', '-r', '10', '-c:v', 'mjpeg', '-i', 'pipe:0',
    '-c:v', 'libvpx', '-pix_fmt', 'yuv420p', resolve(output, 'growth.webm')],
  { input: Buffer.concat(frames), encoding: 'utf8' });
  if (encode.status !== 0) throw Error(encode.error?.message ?? encode.stderr);
  await writeFile(resolve(output, 'result.json'), JSON.stringify({
    frames: frames.length, fps: 10, errors,
    wood: { ...trunkChecks[0], minimumArea: Math.min(...trunkChecks.map(check => check.minimumArea)) },
  }, null, 2));
} finally {
  await browser.close();
}
