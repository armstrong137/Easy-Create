import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';

const output = 'build/qa/depth-collar';
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
    const depth = new Float32Array(920 * 480).fill(Infinity);
    const ground = 400;
    for (const [index, age] of [.42, 1].entries()) {
      const center = 230 + index * 460;
      const project = ([x, y, z]) => [center + x * 67, ground - (z + y * .22) * 67, y - z * .22];
      function paint(face, light) {
        const [a, b, c] = face.map(project);
        const cross = (p, q, x, y) => (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0]);
        const area = cross(a, b, c[0], c[1]);
        if (Math.abs(area) < .001) return;
        const minX = Math.max(index * 460, Math.floor(Math.min(a[0], b[0], c[0])));
        const maxX = Math.min(index * 460 + 459, Math.ceil(Math.max(a[0], b[0], c[0])));
        const minY = Math.max(0, Math.floor(Math.min(a[1], b[1], c[1])));
        const maxY = Math.min(479, Math.ceil(Math.max(a[1], b[1], c[1])));
        for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
          const u = cross(b, c, x + .5, y + .5) / area;
          const v = cross(c, a, x + .5, y + .5) / area;
          const w = 1 - u - v;
          if (Math.min(u, v, w) < 0) continue;
          const z = u * a[2] + v * b[2] + w * c[2];
          const pixel = y * 920 + x;
          if (z >= depth[pixel]) continue;
          depth[pixel] = z;
          [145, 105, 69].forEach((channel, i) => { buffer.data[pixel * 4 + i] = channel * light; });
        }
      }
      // 局部管体保留真实深度，同一相机与光向下投影。
      function tube(sections) {
        const sides = 28;
        const rings = sections.map(([x, y, z, radius], i) => {
          const before = sections[Math.max(0, i - 1)], after = sections[Math.min(sections.length - 1, i + 1)];
          const dx = after[0] - before[0], dz = after[2] - before[2];
          const length = Math.hypot(dx, dz);
          return Array.from({ length: sides }, (_, side) => {
            const angle = side * Math.PI * 2 / sides;
            const across = radius * Math.cos(angle);
            return [x + dz / length * across, y + radius * Math.sin(angle), z - dx / length * across];
          });
        });
        for (let row = 0; row < rings.length - 1; row++) for (let side = 0; side < sides; side++) {
          const next = (side + 1) % sides;
          const a = rings[row][side], b = rings[row][next], c = rings[row + 1][side], d = rings[row + 1][next];
          for (const face of [[a, b, c], [b, d, c]]) {
            const [p, q, r] = face;
            const u = q.map((value, axis) => value - p[axis]);
            const v = r.map((value, axis) => value - p[axis]);
            const normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]];
            const magnitude = Math.hypot(...normal);
            if (magnitude === 0) continue;
            const light = .54 + .52 * Math.max(0, (-.48 * normal[0] - .72 * normal[1] + .49 * normal[2]) / magnitude);
            paint(face, light);
          }
        }
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
