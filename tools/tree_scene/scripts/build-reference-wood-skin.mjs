import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { PNG } from 'pngjs';

const guides = 'assets/source/magic_tree/guides';
const guide = JSON.parse(await readFile(`${guides}/reference_wood_sections.json`));
const source = `${guides}/${guide.source}`;
const bytes = await readFile(source);
const hash = data => createHash('sha256').update(data).digest('hex');
if (hash(bytes) !== guide.sha256) throw Error('木体截面与源图版本不一致');
const { width, height, data } = PNG.sync.read(bytes);
const out = 'build/qa/reference-wood-skin-proof';
await mkdir(out, { recursive: true });

// 加密采样行并读取实际覆盖范围，源图透明度保留根间空隙。
const rows = [710, ...guide.sections.map(row => row.y), height];
const ys = rows.flatMap((y, i) => i ? Array.from(
  { length: Math.ceil((y - rows[i - 1]) / 12) },
  (_, j) => Math.min(y, rows[i - 1] + (j + 1) * 12),
) : [y]);
const pixels = [];
const indices = new Map();
function vertex(x, y) {
  const key = y * (width + 1) + x;
  if (!indices.has(key)) {
    indices.set(key, pixels.length);
    pixels.push([x, y]);
  }
  return indices.get(key);
}
const corners = [];
for (let i = 1; i < ys.length; i++) {
  const top = ys[i - 1], bottom = ys[i];
  for (let x = 0; x < width; x += 12) {
    const right = Math.min(width, x + 12);
    let covered = false;
    for (let y = top; y < bottom && !covered; y++) {
      for (let u = x; u < right && !covered; u++) covered = data[(y * width + u) * 4 + 3] > 0;
    }
    if (!covered) continue;
    const a = vertex(x, top), b = vertex(x, bottom);
    const c = vertex(right, bottom), d = vertex(right, top);
    for (const index of [a, b, c, a, c, d]) {
      const [u, v] = pixels[index];
      corners.push(index, u / width, 1 - v / height);
    }
  }
}

const ages = [0, .5, 1];
const poses = ages.map(age => pixels.map(([x, y]) => {
  const z = (1400 - y) / 120;
  const life = 1 - age;
  // 保持同一UV，根幅和高度分别发育。成熟位置与源图等比例对应。
  const spread = 1 - life * (.45 + .16 * Math.exp(-Math.max(0, z)));
  return [(x - 520) / 120 * spread + life * .10 * z, 0, z * (1 - .37 * life) + life * .017 * z * z];
}));
const sections = {};
const chunks = [];
let byteLength = 0;
function section(name, values) {
  const buffer = Buffer.alloc(values.length * 4);
  values.forEach((value, i) => buffer.writeFloatLE(value, i * 4));
  sections[name] = { offset: byteLength, length: values.length };
  byteLength += buffer.length;
  chunks.push(buffer);
}
section('normals', pixels.flatMap(() => [0, -1, 0]));
section('corners', corners);
poses.forEach((pose, i) => section(`positions${i}`, pose.flat()));
const nodes = [[0, 0, 0], [0, 0, 5.75]];
const metadata = {
  format: '源图轮廓局部表皮-v1', vertexCount: pixels.length, triangleCount: corners.length / 9,
  sections, byteLength, nodes, edges: [[0, 1]],
  poseFrames: ages.map(age => ({ age, nodes, radial: [1] })),
  vertexPoseSections: ages.map((_, i) => `positions${i}`),
  samples: ages.map((age, i) => ({ age, vertices: poses[i].map((position, index) => ({ index, position })) })),
  camera: { target: [0, 0, 2.85], right: [1, 0, 0], up: [0, 0, 1], back: [0, -1, 0], scale: 9.8 },
  unlitTexture: true, groundShadow: false, nearOffset: [0, -1.8], nearSpan: [6, 3],
  scope: '木体下部源纹与空隙的局部形变验证',
};
await writeFile(`${out}/mesh.bin`, Buffer.concat(chunks));
await writeFile(`${out}/mesh.json`, JSON.stringify(metadata));
await copyFile(source, `${out}/baked-bark.png`);
await writeFile(`${out}/result.json`, JSON.stringify({
  script_sha256: hash(await readFile(new URL(import.meta.url))), source_sha256: guide.sha256,
  mesh_export: { vertices: metadata.vertexCount, triangles: metadata.triangleCount, bytes: byteLength },
}, null, 2));
console.log(metadata.vertexCount, '顶点', metadata.triangleCount, '三角形');
