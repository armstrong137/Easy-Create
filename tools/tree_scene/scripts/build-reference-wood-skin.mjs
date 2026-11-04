import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { PNG } from 'pngjs';

const guides = 'assets/source/magic_tree/guides';
const guide = JSON.parse(await readFile(`${guides}/reference_wood_sections.json`));
const junctions = JSON.parse(await readFile(`${guides}/reference_wood_junctions.json`));
const source = `${guides}/${guide.source}`;
const bytes = await readFile(source);
const hash = data => createHash('sha256').update(data).digest('hex');
if (hash(bytes) !== guide.sha256) throw Error('木体截面与源图版本不一致');
const { width, height, data } = PNG.sync.read(bytes);
const out = 'build/qa/reference-wood-skin-proof';
await mkdir(out, { recursive: true });

// 加密采样行并读取实际覆盖范围，源图透明度保留根间空隙。
const rows = [0, ...guide.sections.map(row => row.y), height];
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

const ages = [0, .2, .45, .7, 1];
function boundaryAt(points, y) {
  for (let i = 1; i < points.length; i++) {
    const [a, left] = points[i - 1], [b, right] = points[i];
    if (y <= b) return left + (right - left) * (y - a) / (b - a);
  }
  return points.at(-1)[1];
}
const poses = ages.map(age => pixels.map(([x, y]) => {
  const z = (1400 - y) / 120;
  const life = 1 - age;
  // 保持同一UV，根幅和高度分别发育。成熟位置与源图等比例对应。
  const spread = 1 - life * (.45 + .16 * Math.exp(-Math.max(0, z)));
  // 左右侧域各自展开。域边界与主干共用坐标，根颈保留原来的发育曲线。
  const left = boundaryAt(junctions.left, y), right = boundaryAt(junctions.right, y);
  const inner = Math.max(left, Math.min(right, x));
  const birth = x < left ? .2 : .32;
  const progress = Math.max(0, Math.min(1, (age - birth) / .48));
  const upper = Math.max(0, Math.min(1, (960 - y) / 110));
  const sideScale = 1 - upper * .98 * (1 - progress * progress * (3 - 2 * progress));
  const woodX = inner + (x - inner) * sideScale;
  const rootHeight = Math.min(z, 2);
  const stemHeight = Math.max(0, z - 2);
  return [(woodX - 520) / 120 * spread * (1 - .55 * life) + life * .04 * z, 0,
    rootHeight * (1 - .78 * life) + stemHeight * (1 - .86 * life)];
}));
// 用实际消费的三角网格追踪源图点，避免用独立曲线推算挂点。
const crownPoints = {
  C1: [530, 115], C2: [397, 220], C3: [607, 220],
  C4: [330, 310], C5: [740, 310], C6: [299, 420],
  C7: [741, 525], C8: [255, 740], C9: [810, 740],
  早生叶0: [530, 115], 早生叶1: [486, 115], 早生叶2: [530, 115],
  下左次枝展叶: [150, 685], 下右次枝展叶: [850, 695],
  中左次枝展叶: [260, 550], 中右次枝展叶: [741, 525],
};
const attachments = Object.entries({ ...junctions.attachments, ...crownPoints }).map(([name, [x, y]]) => {
  if (data[(y * width + x) * 4 + 3] < 128) throw Error(`挂点位于透明区：${name}`);
  for (let i = 0; i < corners.length; i += 9) {
    const triangle = [corners[i], corners[i + 3], corners[i + 6]];
    const [[ax, ay], [bx, by], [cx, cy]] = triangle.map(index => pixels[index]);
    const u = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) /
      ((by - cy) * (ax - cx) + (cx - bx) * (ay - cy));
    const v = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) /
      ((by - cy) * (ax - cx) + (cx - bx) * (ay - cy));
    const weights = [u, v, 1 - u - v];
    if (weights.some(weight => weight < -1e-8)) continue;
    return {
      name, pixel: [x, y], triangle, weights,
      frames: poses.map((pose, frame) => ({
        age: ages[frame],
        position: [0, 1, 2].map(axis => weights.reduce(
          (sum, weight, j) => sum + weight * Math.fround(pose[triangle[j]][axis]), 0)),
      })),
    };
  }
  throw Error(`挂点缺少对应三角形：${name}`);
});
// 复用已验证开孔的木框局部网格。先扣除旧母枝位置，再接入当前表皮。
const donor = 'build/qa/development-tree-round2-proof';
const donorMeta = JSON.parse(await readFile(`${donor}/mesh.json`));
const donorReport = JSON.parse(await readFile(`${donor}/result.json`));
const donorBytes = await readFile(`${donor}/mesh.bin`);
const mature = donorMeta.sections[donorMeta.vertexPoseSections.at(-1)];
const readPosition = index => [0, 1, 2].map(axis =>
  donorBytes.readFloatLE(mature.offset + 4 * (index * 3 + axis)));
const triangleTextures = Array(corners.length / 9).fill(0);
const frameNodes = ages.map(() => [[0, 0, 0], [0, 0, 5.75]]);
const plaques = [];
const framePatches = donorReport.patches.filter(patch => patch.material === 2);
const components = [
  ...['左侧牌候选挂点', '右侧牌候选挂点'].map((name, i) => ({ name, patch: framePatches[i], plaque: donorMeta.plaques[i] })),
  ...Object.keys(crownPoints).map(name => ({ name, patch: donorReport.patches.find(p => p.name === name) })),
];
for (const { name, patch, plaque } of components) {
  const attachment = attachments.find(point => point.name === name);
  const original = readPosition(patch.anchorVertex);
  const first = poses[0].length;
  const [start, end] = patch.vertexRange;
  function place(point, frame) {
    const early = name.startsWith('早生叶');
    const t = Math.max(0, Math.min(1, (ages[frame] - (plaque ? .18 : .06)) / .72));
    const growth = early ? .8 + .2 * ages[frame] : .003 + .997 * t * t * (3 - 2 * t);
    return point.map((value, axis) =>
      attachment.frames[frame].position[axis] +
      (value - original[axis]) * (axis === 1 ? 1 : growth) - (axis === 1 && !plaque ? .08 : 0));
  }
  for (let index = start; index < end; index++) {
    const point = readPosition(index);
    poses.forEach((pose, frame) => pose.push(place(point, frame)));
  }
  const block = donorMeta.sections.corners;
  for (let offset = 0; offset < block.length; offset += 9) {
    if (donorMeta.triangleTextures[offset / 9] !== patch.material) continue;
    const triangle = [0, 3, 6].map(delta =>
      donorBytes.readFloatLE(block.offset + (offset + delta) * 4));
    if (triangle.some(index => index < start || index >= end)) continue;
    triangle.forEach((index, corner) => {
      const uvOffset = block.offset + (offset + corner * 3 + 1) * 4;
      corners.push(first + index - start, donorBytes.readFloatLE(uvOffset), donorBytes.readFloatLE(uvOffset + 4));
    });
    triangleTextures.push(plaque ? 1 : 2);
  }
  if (!plaque) continue;
  const paperCorners = plaque.corners.map(index => {
    const next = frameNodes[0].length;
    frameNodes.forEach((nodes, frame) => nodes.push(place(donorMeta.nodes[index], frame)));
    return next;
  });
  plaques.push({ ...plaque, corners: paperCorners });
}
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
section('normals', poses[0].flatMap(() => [0, -1, 0]));
section('corners', corners);
poses.forEach((pose, i) => section(`positions${i}`, pose.flat()));
const nodes = frameNodes.at(-1);
// 幼龄可见域沿主干延伸。外侧根趾和枝梢分批显露，所有年龄共用源图与网格。
const vertexBirthAges = pixels.map(([x, y]) => {
  const center = y < 500 ? 511 : 505;
  const radius = y > 1150 ? 125 : y > 750 ? 108 : 42;
  const distance = Math.abs(x - center) - radius;
  return distance <= 0 ? 0 : .10 + .45 * Math.min(1, distance / 240);
});
while (vertexBirthAges.length < poses[0].length) vertexBirthAges.push(0);
const metadata = {
  format: '参考表皮枝牌接合-v1', vertexCount: poses[0].length, triangleCount: corners.length / 9,
  sections, byteLength, nodes, edges: [[0, 1]],
  poseFrames: ages.map((age, frame) => ({ age, nodes: frameNodes[frame], radial: [1] })),
  vertexPoseSections: ages.map((_, i) => `positions${i}`),
  samples: ages.map((age, i) => ({ age, vertices: poses[i].map((position, index) => ({ index, position })) })),
  camera: { target: [0, 0, 6.1], right: [1, 0, 0], up: [0, 0, 1], back: [0, -1, 0], scale: 16 },
  unlitTexture: true, textureStyles: ['referenceWood', 'frame', 'leaf'], juvenileContrast: .24,
  extraTextures: ['frames.png', 'canopy.png'], triangleTextures, plaques, foliageParts: Object.keys(crownPoints).length,
  vertexBirthAges,
  groundShadow: false, nearOffset: [0, -2.8], nearSpan: [5, 3.6],
  scope: '参考表皮整树第二套',
};
await writeFile(`${out}/mesh.bin`, Buffer.concat(chunks));
await writeFile(`${out}/mesh.json`, JSON.stringify(metadata));
await copyFile(source, `${out}/baked-bark.png`);
await copyFile(`${donor}/frames.png`, `${out}/frames.png`);
await copyFile(`${donor}/canopy.png`, `${out}/canopy.png`);
await writeFile(`${out}/attachments.json`, JSON.stringify(attachments, null, 2));
await writeFile(`${out}/result.json`, JSON.stringify({
  script_sha256: hash(await readFile(new URL(import.meta.url))), source_sha256: guide.sha256,
  frame_donor_sha256: hash(donorBytes),
  mesh_export: { vertices: metadata.vertexCount, triangles: metadata.triangleCount, bytes: byteLength },
}, null, 2));
console.log(metadata.vertexCount, '顶点', metadata.triangleCount, '三角形');
