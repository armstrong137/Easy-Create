import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';

const assembly = process.argv.includes('--assembly');
const output = assembly ? 'build/qa/layered-tree-assembly' : 'build/qa/root-collar-stem-transition';
await mkdir(output, { recursive: true });
const root = await readFile('assets/source/magic_tree/textures_source/root_collar_buttress_v1.png');
const crown = assembly ? await readFile('assets/source/magic_tree/textures_source/secondary_bough_layered_v1.png') : root;
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 1140, height: assembly ? 600 : 380 } });
  await page.setContent(`<body style="margin:0"><canvas width="1140" height="${assembly ? 600 : 380}"></canvas>`);
  await page.evaluate(async ([source, crownSource, assembly]) => {
    const image = new Image();
    image.src = source;
    const leaves = new Image();
    leaves.src = crownSource;
    await Promise.all([image.decode(), leaves.decode()]);
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 1140, ctx.canvas.height);
    // 横向控制线分别经过侧根、前根与根颈，各区随高度独立展宽。
    const columns = [0, 370, 640, 887, 1150, 1440, 1774];
    const youngOffsets = [350, 235, 123, 0, -105, -202, -320];
    const ages = [0, .5, 1];
    for (const [index, age] of ages.entries()) {
      const center = 190 + index * 380;
      const scale = assembly ? .07 + .04 * age : .12 + .06 * age;
      const anchorY = 76;
      const height = .53 + .47 * age;
      const top = (assembly ? 520 : 295) - Math.round((833 - anchorY) * scale * height);
      // 上段从接缝同一采样行开始，往上保持木纹纵向比例。
      ctx.filter = 'saturate(.83) brightness(.94)';
      const stemHeight = Math.round(assembly ? 105 + 140 * age : 51 + 20 * age);
      for (let distance = stemHeight; distance > 0; distance--) {
        const travel = distance / (scale * height);
        const repeat = travel % 284;
        const sourceY = 76 + Math.min(repeat, 284 - repeat);
        const taper = 1 - (assembly ? .81 : .21) * distance / stemHeight;
        const width = 501 * scale * taper;
        ctx.drawImage(image, 636, sourceY, 501, 1 / (scale * height),
          center + (636 + 250.5 - 887) * scale - width / 2, top - distance, width, 1);
      }
      const rows = Math.floor((image.height - anchorY) * scale * height);
      for (let row = 0; row < rows; row++) {
        const sourceY = anchorY + row / (scale * height);
        const reach = Math.min(1, (sourceY - anchorY) / (833 - anchorY));
        const weight = (1 - age) * reach * reach;
        const positions = columns.map((x, i) => Math.round(center + (x - 887 + youngOffsets[i] * weight) * scale));
        for (let col = 0; col < columns.length - 1; col++) {
          const width = positions[col + 1] - positions[col];
          if (width <= 0) throw Error('根颈分区出现翻转');
          ctx.drawImage(image, columns[col], sourceY, columns[col + 1] - columns[col], 1 / (scale * height),
            positions[col], top + row, width, 1);
        }
      }
      ctx.filter = 'none';
      if (assembly) {
        const crownAt = (x, y, size, mirror = false) => {
          ctx.save();
          ctx.translate(x, y);
          ctx.scale(mirror ? -size : size, size);
          ctx.drawImage(leaves, -1040, -863);
          ctx.restore();
        };
        const leafScale = .045 + .041 * age;
        crownAt(center, top - stemHeight, leafScale);
        for (const [side, level, reach] of [[-1,.38,1], [1,.55,1.1], [-1,.75,.78]]) {
          const y = top - stemHeight * level;
          const endX = center + side * (23 + 65 * age) * reach;
          const endY = y - (13 + 28 * age);
          ctx.save();
          const path = new Path2D();
          path.moveTo(center, y);
          path.quadraticCurveTo(center + (endX-center)*.52, y - 3, endX, endY);
          ctx.lineWidth = (501 * scale * (1 - .81 * level)) * .43;
          ctx.lineCap = 'round';
          ctx.strokeStyle = '#6e4930';
          ctx.stroke(path);
          ctx.restore();
          crownAt(endX, endY, leafScale * .83, side > 0);
          if (side > 0 && age > .65) {
            const px = center + (endX-center)*.72;
            const py = y + (endY-y)*.55;
            ctx.fillStyle = '#65432c';
            ctx.fillRect(px - 13, py - 44, 26, 46);
            ctx.fillStyle = '#e9d09c';
            ctx.fillRect(px - 9, py - 40, 18, 35);
            ctx.fillStyle = '#38291c';
            ctx.font = '10px Microsoft YaHei';
            ctx.textAlign = 'center';
            ['第','一','节'].forEach((text,i) => ctx.fillText(text, px, py - 30 + i*11));
            ctx.textAlign = 'left';
          }
        }
      }
      ctx.fillStyle = '#493824';
      ctx.font = '17px Microsoft YaHei';
      ctx.fillText(`根颈发育 ${age.toFixed(2)}`, 20 + index * 380, 32);
    }
  }, [...[root,crown].map(bytes => `data:image/png;base64,${bytes.toString('base64')}`), assembly]);
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
