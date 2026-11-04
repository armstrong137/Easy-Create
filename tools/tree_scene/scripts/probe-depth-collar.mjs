import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';

const output = 'build/qa/depth-collar-fused';
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 920, height: 480 } });
  await page.setContent('<body style="margin:0"><canvas width="920" height="480"></canvas>');
  await page.evaluate(() => {
    const ctx = document.querySelector('canvas').getContext('2d');
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0, 0, 920, 480);
    const buffer = ctx.getImageData(0, 0, 920, 480);
    const ground = 400;
    for (const [index, age] of [.42, 1].entries()) {
      const center = 230 + index * 460;
      const components = [];
      function tube(sections) {
        components.push(sections.slice(1).map((end, i) => {
          const [x, y, z, radius] = sections[i];
          const [dx, dy, dz] = end.slice(0, 3).map((value, axis) => value - sections[i][axis]);
          return [x, y, z, radius, dx, dy, dz, end[3] - radius, 1 / (dx*dx + dy*dy + dz*dz)];
        }));
      }
      // 各木体的距离场在接头附近融合，投影采样同一连续表面。
      function field(x, y, z) {
        let surface = Infinity;
        for (const segments of components) {
          let part = Infinity;
          for (const [px, py, pz, radius, dx, dy, dz, dr, inv] of segments) {
            const qx = x - px, qy = y - py, qz = z - pz;
            const t = Math.max(0, Math.min(1, (qx*dx + qy*dy + qz*dz) * inv));
            part = Math.min(part, Math.hypot(qx - t*dx, qy - t*dy, qz - t*dz) - radius - t*dr);
          }
          const blend = Math.max(0, .29 - Math.abs(surface - part));
          surface = Math.min(surface, part) - blend * blend / 1.16;
        }
        return Math.max(surface, -z);
      }
      const thickness = .38 + .62 * age;
      tube([[0,0,.22,.82*thickness], [.04,0,.72,.56*thickness], [.14,.02,1.4,.42*thickness],
        [.08,.06,2.15,.35*thickness], [-.15,.12,3.15,.27*thickness], [-.25,.12,3.7+age,.19*thickness]]);
      for (const [x, y, reach] of [[-1,-.32,1.7],[1,.22,1.82],[-.42,-1,1.22],[.72,-.8,1.45]]) {
        const size = .55 + .45 * age;
        tube([[x*.18,y*.12,.79,.31*thickness], [x*.67*size,y*.48,.38,.34*thickness],
          [x*1.04*size,y*.83,.19,.22*thickness], [x*reach*size,y*1.3,.05,.05*thickness]]);
      }
      tube([[.14,0,1.45,.29*thickness], [.14+.41*age,-.08,1.61,.26*thickness], [1.05*age,-.21,1.94,.21*thickness],
        [1.42*age,-.26,2.35,.16*thickness], [1.93*age,-.24,2.65,.07*thickness]]);
      for (let py = 54; py < 440; py++) for (let px = center - 155; px < center + 165; px++) {
        const x = (px + .5 - center) / 67;
        const screenZ = (ground - py - .5) / 67;
        for (let y = -2.4, step = 0; y < 2.3 && step < 90; step++) {
          const z = screenZ - y * .22;
          const distance = field(x, y, z);
          if (distance > .003) {
            y += Math.max(.004, distance * .63);
            continue;
          }
          const epsilon = .004;
          const nx = field(x+epsilon,y,z)-field(x-epsilon,y,z);
          const ny = field(x,y+epsilon,z)-field(x,y-epsilon,z);
          const nz = field(x,y,z+epsilon)-field(x,y,z-epsilon);
          const light = .54 + .52 * Math.max(0, (-.48*nx-.72*ny+.49*nz) / (Math.hypot(nx,ny,nz) || 1));
          const pixel = (py * 920 + px) * 4;
          buffer.data[pixel] = 145 * light;
          buffer.data[pixel+1] = 105 * light;
          buffer.data[pixel+2] = 69 * light;
          break;
        }
      }
    }
    ctx.putImageData(buffer, 0, 0);
    ctx.font = '18px Microsoft YaHei';
    ctx.fillStyle = '#493824';
    ctx.fillText('生长姿态 0.42', 24, 36);
    ctx.fillText('生长姿态 1.00', 484, 36);
  });
  await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
