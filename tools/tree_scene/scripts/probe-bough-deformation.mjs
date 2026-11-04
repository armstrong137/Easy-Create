import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';

const output = 'build/qa/bough-deformation';
await mkdir(output, { recursive: true });
const asset = await readFile('assets/source/magic_tree/textures_source/canopy_boughs_v1.png');
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 460 } });
  await page.setContent('<body style="margin:0"><canvas width="900" height="460"></canvas>');
  await page.evaluate(async url => {
    const image = new Image();
    image.src = url;
    await image.decode();
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 900, 460);
    ctx.font = '18px Microsoft YaHei';
    const crop = { x: 665, y: 110, width: 586, height: 490 };
    const anchor = { x: 24, y: 464 };
    for (const [index, bend] of [0, -54, 54].entries()) {
      const jointX = 42 + index * 300, jointY = 346;
      const scale = .35;
      // 沿源图高度改变横向位移，连接点位移恒为零。
      const shift = y => bend * ((y - anchor.y) / anchor.y) ** 2;
      for (let row = 0; row < Math.floor(crop.height * scale); row++) {
        const y = row / scale;
        ctx.drawImage(image, crop.x, crop.y + y, crop.width, 1 / scale,
          jointX + (shift(y) - anchor.x) * scale, Math.round(jointY - anchor.y * scale) + row,
          crop.width * scale, 1);
      }
      ctx.fillStyle = '#493824';
      ctx.fillRect(jointX - 10, jointY - 2, 12, 40);
      ctx.strokeStyle = '#ac7440';
      ctx.beginPath();
      ctx.arc(jointX, jointY, 7, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillText(['原形', '向左弯', '向右弯'][index], 22 + index * 300, 42);
    }
  }, `data:image/png;base64,${asset.toString('base64')}`);
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
