import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { PNG } from 'pngjs';

const directory = 'assets/source/magic_tree/guides';
const source = '../textures_source/reference_wood_v2.png';
const bytes = await readFile(`${directory}/${source}`);
const { width, height, data } = PNG.sync.read(bytes);

// 横截面坐标可按解剖位置编辑。保留每段木质以及其间的透明空隙。
const stations = {
  '下分叉': [740, 760, 780, 800, 820, 840, 860],
  '主干': [880, 920, 960, 1000, 1040, 1080, 1120, 1160],
  '根颈及根趾': [1180, 1200, 1220, 1240, 1260, 1280, 1300, 1320, 1340, 1360, 1380, 1400],
};

const sections = Object.entries(stations).flatMap(([region, rows]) => rows.map(y => {
  const spans = [];
  let start = -1;
  for (let x = 0; x <= width; x++) {
    const solid = x < width && data[(y * width + x) * 4 + 3] >= 128;
    if (solid && start < 0) start = x;
    if (!solid && start >= 0) {
      spans.push({ start, endExclusive: x, uv: [start / width, x / width, 1 - (y + .5) / height] });
      start = -1;
    }
  }
  return { region, y, spans };
}));

const result = { source, sha256: createHash('sha256').update(bytes).digest('hex'), width, height, alphaThreshold: 128, sections };
await writeFile(`${directory}/reference_wood_sections.json`, JSON.stringify(result) + '\n');

const marks = sections.flatMap(({ y, spans }) => spans.map(({ start, endExclusive }) =>
  `<path d="M ${start} ${y + .5} H ${endExclusive}"/>`)).join('\n');
await writeFile(`${directory}/reference_wood_sections.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 710 ${width} 710">
<rect y="710" width="${width}" height="710" fill="#f4ebd9"/>
<image href="${source}" width="${width}" height="${height}"/>
<g fill="none" stroke="#80fff0" stroke-width="2">${marks}</g>
</svg>\n`);
