import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';

const output = 'build/qa/root-collar-asset';
await mkdir(output, { recursive: true });
const root = await readFile('assets/source/magic_tree/textures_source/root_collar_buttress_v1.png');
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 1140, height: 380 } });
  await page.setContent('<body style="margin:0"><canvas width="1140" height="380"></canvas>');
  await page.evaluate(async source => {
    const image = new Image();
    image.src = source;
    await image.decode();
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 1140, 380);
    // 横向控制线分别经过侧根、前根与根颈，各区随高度独立展宽。
    const columns = [0, 370, 640, 887, 1150, 1440, 1774];
    const youngOffsets = [350, 235, 123, 0, -105, -202, -320];
    const ages = [0, .5, 1];
    for (const [index, age] of ages.entries()) {
      const center = 190 + index * 380;
      const scale = .18;
      const anchorY = 76;
      const height = .63 + .37 * age;
      const top = 295 - Math.round((833 - anchorY) * scale * height);
      // 接合上缘使用同一素材的短截面，便于直接识别纵纹过渡问题。
      ctx.drawImage(image, 636, 81, 501, 80, center + (636 - 887) * scale, top - 68, 501 * scale, 70);
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
      ctx.fillStyle = '#493824';
      ctx.font = '17px Microsoft YaHei';
      ctx.fillText(`根颈发育 ${age.toFixed(2)}`, 20 + index * 380, 32);
    }
  }, `data:image/png;base64,${root.toString('base64')}`);
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
