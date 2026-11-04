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
const stem = (age, t) => [.24 * t * t + .06 * age * t, t * (1.6 + .9 * age)];
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
        const [x, z] = path(age, t);
        const [ax, az] = path(age, t - .001), [bx, bz] = path(age, t + .001);
        const length = Math.hypot(bx - ax, bz - az);
        const radius = width(age, t);
        poses[frame].push([x + (bz - az) / length * radius * across,
          -radius * Math.sqrt(1 - across * across), z - (bx - ax) / length * radius * across]);
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
strip(stem, (age, t) => (.076 + .044 * age) * (1 - .91 * t) * (1 + .65 * Math.exp(-t * 14)));
const shoots = [-1, 1].map((side, i) => (age, t) => {
  const [x, z] = stem(age, i ? .66 : .51);
  const reach = .28 + .55 * smooth((age - i * .13) / .75);
  return [x + side * reach * t, z + reach * (.18 * t + .56 * t * t)];
});
for (const path of shoots) strip(path, (age, t) => (.029 + .026 * age) * (1 - .9 * t));
for (const [side, reach] of [[-1, .24], [1, .33], [-1, .15]]) {
  strip((age, t) => [side * reach * (1 + age * .45) * t, .075 - .085 * t + .018 * t * t],
    (age, t) => (.037 + .022 * age) * (1 - .93 * t));
}

const woodVertices = poses[0].length;
const meta = JSON.parse(await readFile(`${donor}/mesh.json`));
const report = JSON.parse(await readFile(`${donor}/result.json`));
const binary = await readFile(`${donor}/mesh.bin`);
const mature = meta.sections[meta.vertexPoseSections.at(-1)];
const position = id => [0, 1, 2].map(axis => binary.readFloatLE(mature.offset + (id * 3 + axis) * 4));
for (const [i, path] of [...shoots, stem].entries()) {
  const patch = report.patches.find(item => item.name === `早生叶${i}`);
  const base = position(patch.anchorVertex);
  const first = poses[0].length;
  const [start, end] = patch.vertexRange;
  for (let id = start; id < end; id++) {
    const point = position(id);
    normals.push(0, -1, 0);
    ages.forEach((age, frame) => {
      const [x, z] = path(age, 1);
      const scale = .69 + .28 * smooth(age);
      poses[frame].push([x + (point[0] - base[0]) * scale, -.035, z + (point[2] - base[2]) * scale]);
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
const nodes = [[0, 0, 0], [0, 0, 2.5]];
const metadata = {
  format: '独立幼苗实体发育-v1', vertexCount: poses[0].length, triangleCount: corners.length / 9,
  byteLength, sections, nodes, edges: [[0, 1]],
  poseFrames: ages.map(age => ({ age, nodes, radial: [1] })),
  vertexPoseSections: ages.map((_, i) => `positions${i}`),
  samples: ages.map((age, i) => ({ age, vertices: poses[i].map((position, index) => ({ index, position })) })),
  camera: { target: [0, 0, 1.5], right: [1, 0, 0], up: [0, 0, 1], back: [0, -1, 0], scale: 4.7 },
  textureStyles: ['wood', 'leaf'], extraTextures: ['canopy.png'], triangleTextures, foliageParts: 3,
  postTextureLightingMaterials: [0], unlitVertexStart: woodVertices, juvenileContrast: .12,
  nearSpan: [1.4, 2.3], nearOffset: [0, -.1], groundShadow: false,
  scope: '独立幼苗与两根实体侧枝的局部发育',
};
await mkdir(out, { recursive: true });
await writeFile(`${out}/mesh.bin`, Buffer.concat(chunks));
await writeFile(`${out}/mesh.json`, JSON.stringify(metadata));
await copyFile('assets/source/magic_tree/textures_source/development_bark_v1.png', `${out}/baked-bark.png`);
await copyFile(`${donor}/canopy.png`, `${out}/canopy.png`);
await writeFile(`${out}/result.json`, JSON.stringify({
  script_sha256: createHash('sha256').update(await readFile(new URL(import.meta.url))).digest('hex'),
}, null, 2));
console.log(metadata.vertexCount, '顶点', metadata.triangleCount, '三角形');
