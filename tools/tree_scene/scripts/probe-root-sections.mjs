import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';

const output = 'build/qa/root-sections';
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 430 } });
  await page.setContent('<body style="margin:0"><canvas width="900" height="430"></canvas>');
  await page.evaluate(() => {
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 900, 430);
    const pixels = ctx.getImageData(0, 0, 900, 430);
    const lightDirection = [-.53, -.75, .39];
    const roots = [[-2.89, 1.31], [-2.16, 1.45], [-1.21, 1.28], [-.31, 1.54], [1.36, .75]];
    const ages = [.34, 1];
    for (const [panel, age] of ages.entries()) {
      const center = 225 + panel * 450;
      const extent = .58 + .42 * age;
      // 截面由中心宽度及定向根脊定义，根之间直接留出凹部。
      function surface(x, y, z) {
        const height = Math.max(0, z);
        const centerX = .11 * Math.sin(height * 1.9);
        const px = x - centerX;
        const py = y * 1.10;
        const angle = Math.atan2(py, px);
        const radial = Math.hypot(px, py);
        let ridge = 0;
        for (const [direction, length] of roots) {
          const alignment = Math.max(0, Math.cos(angle - direction));
          ridge = Math.max(ridge, length * alignment ** 22);
        }
        const profile = (.35 + .20 * Math.exp(-height * 2.6)) * extent;
        const perimeter = profile + ridge * Math.exp(-height * 3.2) * extent;
        const leftCavity = Math.hypot((x + .49 * extent) / .24, (y + .70 * extent) / .48, (z - .02) / .20) - 1;
        const rightCavity = Math.hypot((x - .52 * extent) / .23, (y + .62 * extent) / .46, (z - .015) / .18) - 1;
        return Math.max(radial - perimeter, -z, z - (1.65 + .56 * age),
          -.23 * Math.min(leftCavity, rightCavity));
      }
      for (let py = 42; py < 389; py++) for (let px = center - 205; px < center + 205; px++) {
        const x = (px + .5 - center) / 100;
        const screenZ = (340 - py - .5) / 100;
        // 固定相机沿深度取首个交点，保留前根对后根的遮挡。
        for (let y = -2.3; y <= 2.1; y += .018) {
          let z = screenZ - .27 * y;
          if (z < 0 || z > 2.22 || surface(x, y, z) > 0) continue;
          let low = y - .018, high = y;
          for (let step = 0; step < 6; step++) {
            const middle = (low + high) / 2;
            if (surface(x, middle, screenZ - .27 * middle) <= 0) high = middle;
            else low = middle;
          }
          y = high;
          z = screenZ - .27 * y;
          const eps = .006;
          const normal = [
            surface(x+eps,y,z) - surface(x-eps,y,z),
            surface(x,y+eps,z) - surface(x,y-eps,z),
            surface(x,y,z+eps) - surface(x,y,z-eps),
          ];
          const diffuse = normal.reduce((sum, value, axis) => sum + value * lightDirection[axis], 0)
            / (Math.hypot(...normal) || 1);
          const tone = .40 + .57 * Math.max(0, diffuse);
          const pixel = (py * 900 + px) * 4;
          [159, 116, 74].forEach((value, axis) => { pixels.data[pixel + axis] = value * tone; });
          break;
        }
      }
    }
    ctx.putImageData(pixels, 0, 0);
    ctx.fillStyle = '#493824';
    ctx.font = '18px Microsoft YaHei';
    ages.forEach((age, i) => ctx.fillText(`根颈发育 ${age.toFixed(2)}`, 24 + 450 * i, 32));
  });
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
