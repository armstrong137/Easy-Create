import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const out = 'build/qa/native-seedling-proof';
const donor = 'build/qa/development-tree-round2-proof';
const ages = [0, .25, .5, .75, 1];
const poses = ages.map(() => []);
const corners = [], normals = [], triangleTextures = [];
const smooth = value => {
  const t = Math.max(0, Math.min(1, value));
  return t * t * (3 - 2 * t);
};
const maturity = age => smooth((age - .25) / .75);
const juvenile = age => Math.min(1, age * 4);
const stem = (age, t) => {
  const adult = maturity(age);
  return [.24 * t * t + .06 * juvenile(age) * t + adult * (.53 * t - .72 * t * t),
    t * (1.6 + .9 * juvenile(age) + 2.5 * adult)];
};
function addTriangle(ids, uv, material) {
  ids.forEach((id, i) => corners.push(id, ...uv[i]));
  triangleTextures.push(material);
}
function strip(path, width) {
  const first = poses[0].length;
  const rows = 16, columns = 6;
  for (let row = 0; row <= rows; row++) {
    const t = row / rows;
    for (let column = 0; column <= columns; column++) {
      const across = column / columns * 2 - 1;
      normals.push(across * .8, -Math.sqrt(1 - across * across * .64), 0);
      ages.forEach((age, frame) => {
        const [x, z, depth = 0] = path(age, t);
        const [ax, az] = path(age, t - .001), [bx, bz] = path(age, t + .001);
        const length = Math.hypot(bx - ax, bz - az);
        const radius = width(age, t);
        poses[frame].push([x + (bz - az) / length * radius * across,
          depth - radius * Math.sqrt(1 - across * across), z - (bx - ax) / length * radius * across]);
      });
    }
  }
  for (let row = 0; row < rows; row++) for (let column = 0; column < columns; column++) {
    const a = first + row * (columns + 1) + column;
    const ids = [a, a + 1, a + columns + 2, a + columns + 1];
    const uv = [[column / columns, row / rows], [(column + 1) / columns, row / rows],
      [(column + 1) / columns, (row + 1) / rows], [column / columns, (row + 1) / rows]];
    for (const triangle of [[0, 1, 2], [0, 2, 3]]) addTriangle(triangle.map(i => ids[i]), triangle.map(i => uv[i]), 0);
  }
}

// 主干从幼苗尺寸起步，侧枝的基点每次由同一母干曲线求出。
strip(stem, (age, t) => (.076 + .044 * juvenile(age) + .43 * maturity(age)) *
  (1 - .91 * t + .13 * maturity(age) * Math.sin(3 * Math.PI * t) ** 2) *
  (1 + .65 * Math.exp(-t * 14)));
const shoots = [-1, 1].map((side, i) => (age, t) => {
  const [x, z] = stem(age, i ? .66 : .51);
  const adult = maturity(age);
  const reach = .28 + .55 * smooth((juvenile(age) - i * .13) / .75) + adult * (i ? 2.05 : 2.4);
  return [x + side * reach * t, z + reach * ((.18 - adult * .27) * t + (.56 - adult * .13) * t * t)];
});
for (const path of shoots) strip(path, (age, t) =>
  (.029 + .026 * juvenile(age) + .20 * maturity(age)) * (1 - .9 * t));
// 二级枝以母枝参数定位，向冠层内部填补主枝间的空隙。
const twigs = [
  [shoots[0], .68, 1, .14, .23],
  [shoots[1], .60, -1, .16, .25],
  [stem, .80, -1, .26, .23],
  [stem, .89, 1, .24, .18],
  [shoots[0], .43, -1, .20, .35],
  [shoots[1], .40, 1, .21, .30],
  [shoots[0], .78, -1, .17, .19],
  [shoots[1], .76, 1, .12, .18],
  [stem, .73, -1, .24, .21],
].map(([parent, origin, side, reach, rise], i) => (age, t) => {
  const [x, z] = parent(age, origin);
  const extension = i < 4
    ? .48 + .68 * smooth((juvenile(age) - i * .08) / .76) + 2.2 * maturity(age)
    : .045 + 2.2 * maturity(age);
  return [x + side * reach * extension * t, z + rise * extension * t * (.66 + .34 * t)];
});
for (const [index, path] of twigs.entries()) strip(path, (age, t) =>
  ((index < 4 ? .013 + .008 * juvenile(age) : .0015) + .06 * maturity(age)) * (1 - .91 * t));
for (const [side, reach, forward] of [[-1, .24, .13], [1, .33, -.06], [-1, .15, .48], [1, .17, .62]]) {
  strip((age, t) => {
    const adult = maturity(age);
    return [side * reach * (1 + juvenile(age) * .45 + 4.1 * adult) * t,
      .075 - .085 * t + .018 * t * t + adult * (.52 - (.57 + forward * .31) * t + .13 * t * t),
      -adult * forward * (.30 + t)];
  }, (age, t) => (.037 + .022 * juvenile(age) + .18 * maturity(age)) * (1 - .93 * t));
}

const woodVertices = poses[0].length;
const meta = JSON.parse(await readFile(`${donor}/mesh.json`));
const report = JSON.parse(await readFile(`${donor}/result.json`));
const binary = await readFile(`${donor}/mesh.bin`);
const mature = meta.sections[meta.vertexPoseSections.at(-1)];
const position = id => [0, 1, 2].map(axis => binary.readFloatLE(mature.offset + (id * 3 + axis) * 4));
const nodes = [[0, 0, 0], [0, 0, 5]];
const frameNodes = ages.map(() => [...nodes]);
const foliage = [
  ...[...shoots, stem].map((path, i) => ({ path, patchIndex: i, size: 1, depth: -.035 })),
  ...twigs.map((path, i) => ({
    path, patchIndex: (i + 1) % 3, size: i < 4 ? .68 : .82,
    depth: i % 2 ? -.31 : -.065, late: i >= 4,
  })),
];
for (const { path, patchIndex, size, depth, late } of foliage) {
  const patch = report.patches.find(item => item.name === `早生叶${patchIndex}`);
  const base = position(patch.anchorVertex);
  const first = poses[0].length;
  const [start, end] = patch.vertexRange;
  for (let id = start; id < end; id++) {
    const point = position(id);
    normals.push(0, -1, 0);
    ages.forEach((age, frame) => {
      const [x, z] = path(age, 1);
      const adult = maturity(age);
      const scale = size * (late ? .025 + 2.9 * adult : .69 + .28 * smooth(juvenile(age)) + 2.1 * adult);
      poses[frame].push([x + (point[0] - base[0]) * scale, depth * (.15 + .85 * adult),
        z + (point[2] - base[2]) * scale * (1 - .24 * adult)]);
    });
  }
  const block = meta.sections.corners;
  for (let i = 0; i < block.length; i += 9) {
    const values = Array.from({ length: 9 }, (_, j) => binary.readFloatLE(block.offset + (i + j) * 4));
    const ids = [values[0], values[3], values[6]];
    if (ids.some(id => id < start || id >= end)) continue;
    addTriangle(ids.map(id => first + id - start), [values.slice(1, 3), values.slice(4, 6), values.slice(7, 9)], 1);
  }
}
// 框体和纸面使用同一个母枝采样点，缩放时共用同一变换。
const firstFrameVertex = poses[0].length;
const plaques = report.patches.filter(patch => patch.material === 2).map((patch, index) => {
  const plaque = meta.plaques[index];
  const anchor = position(patch.anchorVertex);
  const place = (point, age) => {
    const [x, z] = shoots[index](age, .40);
    const scale = .012 + .46 * smooth((age - .2) / .65);
    return [x + (point[0] - anchor[0]) * scale, -.28 * maturity(age) - .08 + (point[1] - anchor[1]) * scale,
      z + (point[2] - anchor[2]) * scale + .075 * maturity(age)];
  };
  const first = poses[0].length;
  const [start, end] = patch.vertexRange;
  for (let id = start; id < end; id++) {
    const point = position(id);
    normals.push(0, -1, 0);
    ages.forEach((age, frame) => poses[frame].push(place(point, age)));
  }
  const block = meta.sections.corners;
  for (let i = 0; i < block.length; i += 9) {
    if (meta.triangleTextures[i / 9] !== patch.material) continue;
    const values = Array.from({ length: 9 }, (_, j) => binary.readFloatLE(block.offset + (i + j) * 4));
    const ids = [values[0], values[3], values[6]];
    if (ids.some(id => id < start || id >= end)) continue;
    addTriangle(ids.map(id => first + id - start), [values.slice(1, 3), values.slice(4, 6), values.slice(7, 9)], 2);
  }
  return { ...plaque, corners: plaque.corners.map(id => {
    const next = frameNodes[0].length;
    ages.forEach((age, frame) => frameNodes[frame].push(place(meta.nodes[id], age)));
    return next;
  }) };
});
const sections = {}, chunks = [];
let byteLength = 0;
function section(name, values) {
  const bytes = Buffer.alloc(values.length * 4);
  values.forEach((v, i) => bytes.writeFloatLE(v, i * 4));
  sections[name] = { offset: byteLength, length: values.length };
  chunks.push(bytes);
  byteLength += bytes.length;
}
section('normals', normals);
section('corners', corners);
poses.forEach((pose, i) => section(`positions${i}`, pose.flat()));
const metadata = {
  format: '独立魔树实体发育-v4', vertexCount: poses[0].length, triangleCount: corners.length / 9,
  byteLength, sections, nodes: frameNodes.at(-1), edges: [[0, 1]],
  poseFrames: ages.map((age, index) => ({ age, nodes: frameNodes[index], radial: [1] })),
  vertexPoseSections: ages.map((_, i) => `positions${i}`),
  samples: ages.map((age, i) => ({ age, vertices: poses[i].map((position, index) => ({ index, position })) })),
  camera: { target: [0, 0, 2.8], right: [1, 0, 0], up: [0, 0, 1], back: [0, -1, 0], scale: 13 },
  textureStyles: ['wood', 'leaf', 'wood'], extraTextures: ['canopy.png', 'frames.png'],
  triangleTextures, foliageParts: foliage.length, plaques,
  vertexBirthAges: poses[0].map((_, index) => index >= firstFrameVertex ? .18 : -1),
  postTextureLightingMaterials: [0], unlitVertexStart: woodVertices, juvenileContrast: .12,
  nearSpan: [3.8, 3.0], nearOffset: [0, .3], groundShadow: false,
  scope: '从独立幼苗到成熟宽冠的同拓扑发育',
};
await mkdir(out, { recursive: true });
await writeFile(`${out}/mesh.bin`, Buffer.concat(chunks));
await writeFile(`${out}/mesh.json`, JSON.stringify(metadata));
await copyFile('assets/source/magic_tree/textures_source/development_bark_v1.png', `${out}/baked-bark.png`);
await copyFile(`${donor}/canopy.png`, `${out}/canopy.png`);
await copyFile(`${donor}/frames.png`, `${out}/frames.png`);
await writeFile(`${out}/result.json`, JSON.stringify({
  script_sha256: createHash('sha256').update(await readFile(new URL(import.meta.url))).digest('hex'),
}, null, 2));
console.log(metadata.vertexCount, '顶点', metadata.triangleCount, '三角形');
