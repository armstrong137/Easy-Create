import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';

const output = 'build/qa/bough-grain-transition';
await mkdir(output, { recursive: true });
const asset = await readFile('assets/source/magic_tree/textures_source/canopy_boughs_v1.png');
const bark = await readFile('assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png');
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 460 } });
  await page.setContent('<body style="margin:0"><canvas width="900" height="460"></canvas>');
  await page.evaluate(async ([url, barkUrl]) => {
    const image = new Image();
    image.src = url;
    const barkImage = new Image();
    barkImage.src = barkUrl;
    await Promise.all([image.decode(), barkImage.decode()]);
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 900, 460);
    ctx.font = '18px Microsoft YaHei';
    const crop = { x: 665, y: 110, width: 586, height: 490 };
    const anchor = { x: 24, y: 464 };
    const transition = new OffscreenCanvas(40, 52);
    const grain = transition.getContext('2d');
    // 只取枝基内部的木纹，沿承托方向延展后渐隐。
    grain.drawImage(image, 696, 547, 11, 10, 0, 0, 40, 52);
    grain.globalCompositeOperation = 'destination-in';
    const fade = grain.createLinearGradient(0, 0, 0, 52);
    fade.addColorStop(0, '#fff');
    fade.addColorStop(1, '#fff0');
    grain.fillStyle = fade;
    grain.fillRect(0, 0, 40, 52);
    for (const [index, bend] of [0, -54, 54].entries()) {
      const jointX = 84 + index * 300, jointY = 330;
      const scale = .35;
      ctx.save();
      ctx.translate(jointX, jointY);
      const spread = bend / 9;
      const shadow = ctx.createRadialGradient(-20, 86, 3, -20, 86, 49);
      shadow.addColorStop(0, '#58432960');
      shadow.addColorStop(1, '#58432900');
      ctx.save();
      ctx.translate(0, 52);
      ctx.scale(1, .4);
      ctx.fillStyle = shadow;
      ctx.fillRect(-76, 35, 115, 100);
      ctx.restore();
      // 母枝与外露粗根共用一条轮廓，弯曲时枝基位置不变。
      const surface = new Path2D(`M -65 85 C -53 80 -38 72 -33 58 C -27 44 -22 27 -12 12 C -7 5 -3 0 4 -4 L 10 0 C 1 9 -4 20 -7 34 C -11 53 ${-11 + spread} 68 1 73 C 10 78 15 83 22 87 C 5 88 -7 82 -13 80 C -20 80 -27 91 -38 91 C -34 87 -30 81 -32 79 C -43 86 -53 88 -65 85 Z`);
      const light = ctx.createLinearGradient(-21, 8, 3, 30);
      light.addColorStop(0, '#4d3825');
      light.addColorStop(.35, '#8e7150');
      light.addColorStop(.68, '#665038');
      light.addColorStop(1, '#372a1e');
      ctx.fillStyle = light;
      ctx.fill(surface);
      ctx.clip(surface);
      ctx.globalAlpha = .39;
      ctx.drawImage(barkImage, -70, -12, 98, 110);
      ctx.save();
      ctx.translate(3, -3);
      ctx.rotate(.48);
      ctx.globalAlpha = .55;
      ctx.drawImage(transition, -12, 0, 22, 36);
      ctx.restore();
      ctx.strokeStyle = '#bc9b6b';
      ctx.globalAlpha = .32;
      ctx.lineWidth = 1.2;
      ctx.stroke(new Path2D('M -27 78 C -19 50 -19 25 1 0 M -21 79 C -14 48 -14 29 6 1'));
      ctx.restore();
      // 沿源图高度改变横向位移，连接点位移恒为零。
      const shift = y => bend * ((y - anchor.y) / anchor.y) ** 2;
      for (let row = 0; row < Math.floor(crop.height * scale); row++) {
        const y = row / scale;
        ctx.drawImage(image, crop.x, crop.y + y, crop.width, 1 / scale,
          jointX + (shift(y) - anchor.x) * scale, Math.round(jointY - anchor.y * scale) + row,
          crop.width * scale, 1);
      }
      ctx.fillStyle = '#493824';
      ctx.fillText(['原形', '向左弯', '向右弯'][index], 22 + index * 300, 42);
      ctx.drawImage(ctx.canvas, jointX - 18, jointY - 18, 43, 45,
        106 + index * 300, 58, 86, 90);
    }
  }, [asset, bark].map(bytes => `data:image/png;base64,${bytes.toString('base64')}`));
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
