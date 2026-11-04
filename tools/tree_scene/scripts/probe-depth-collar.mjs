import { chromium } from 'playwright';
import { mkdir, readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const output = 'build/qa/depth-collar-first-review';
const bark = await readFile('assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png');
const canopy = await readFile('assets/source/magic_tree/textures_source/canopy_boughs_v1.png');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 460, height: 480 } });
  await page.setContent('<body style="margin:0"><canvas width="460" height="480"></canvas>');
  await page.evaluate(async ([barkSource, canopySource]) => {
    const image = new Image();
    image.src = barkSource;
    await image.decode();
    const leaves = new Image();
    leaves.src = canopySource;
    await leaves.decode();
    const texture = new OffscreenCanvas(256, 256).getContext('2d');
    texture.drawImage(image, 0, 0, 256, 256);
    const texels = texture.getImageData(0, 0, 256, 256).data;
    const grain = (u, v) => texels[4 * (((Math.floor(v * 96) & 255) << 8) + (Math.floor(u * 128) & 255))] / 255;
    const ctx = document.querySelector('canvas').getContext('2d');
    const smooth = value => {
      const t = Math.max(0, Math.min(1, value));
      return t * t * (3 - 2 * t);
    };
    window.renderTree = (age, near = false) => {
      const width = ctx.canvas.width;
      const scale = near ? 145 : 67;
      const center = near ? 25 : 230;
      const ground = near ? 605 : 400;
      const crowns = [];
      const captions = [];
      ctx.fillStyle = '#f6efdf';
      ctx.fillRect(0, 0, width, 480);
      const buffer = ctx.getImageData(0, 0, width, 480);
      const components = [];
      // 每件冠枝定位到其发育管体末端，同一投影用于木体和冠枝。
      const crown = ([x, y, z], [sx, sy, width, height, ax, ay], scale) => {
        const size = scale * (.37 + .63 * age) * (near ? 145 / 67 : 1);
        const projection = near ? 145 : 67;
        crowns.push([sx, sy, width, height, center + x * projection - (ax - sx) * size,
          ground - (z + y * .22) * projection - (ay - sy) * size, width * size, height * size]);
      };
      const leftLeaves = [0,110,620,490,590,565];
      const rightLeaves = [665,110,586,490,689,574];
      const archLeaves = [0,730,776,420,374,1134];
      const seat = [.31 + 1.11 * age, -.26, 2.10 + .25 * age];
      const frameSize = smooth((age - .57) / .40);
      const paperReveal = smooth((age - .69) / .28);
      const plaque = [seat[0], seat[1] - .105 * frameSize, seat[2] + .42 * frameSize];
      const fuse = (a, b, radius) => {
        const blend = Math.max(0, radius - Math.abs(a - b));
        return Math.min(a, b) - blend * blend / (4 * radius);
      };
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
          surface = fuse(surface, part, .29);
        }
        if (frameSize > 0) {
          const dx = Math.abs(x - plaque[0]) - .25 * frameSize;
          const dy = Math.abs(y - plaque[1]) - .074 * frameSize;
          const dz = Math.abs(z - plaque[2]) - .32 * frameSize;
          const box = Math.hypot(Math.max(dx, 0), Math.max(dy, 0), Math.max(dz, 0))
            + Math.min(Math.max(dx, dy, dz), 0) - .046 * frameSize;
          surface = fuse(surface, box, .17 * frameSize);
        }
        return Math.max(surface, -z);
      }
      const thickness = .38 + .62 * age;
      const leader = [-.25,.12,2.96+1.74*age,.19*thickness];
      tube([[0,0,.22,.82*thickness], [.04,0,.72,.56*thickness], [.14,.02,1.4,.42*thickness],
        [.08,.06,2.15,.35*thickness], [-.15,.12,2.64+.51*age,.27*thickness], leader]);
      crown(leader, archLeaves, .153);
      for (const [x, y, reach] of [[-1,-.32,1.7],[1,.22,1.82],[-.42,-1,1.22],[.72,-.8,1.45]]) {
        const size = .55 + .45 * age;
        tube([[x*.18,y*.12,.79,.31*thickness], [x*.67*size,y*.48,.38,.34*thickness],
          [x*1.04*size,y*.83,.19,.22*thickness], [x*reach*size,y*1.3,.05,.05*thickness]]);
      }
      const rightTip = [.40+1.53*age,-.24,2.45+.20*age,.07*thickness];
      tube([[.14,0,1.45,.29*thickness], [.14+.41*age,-.08,1.61,.26*thickness], [.23+.82*age,-.21,1.94,.21*thickness],
        [...seat,.16*thickness], rightTip]);
      crown(rightTip, rightLeaves, .143);
      for (const [side, matureHeight, length, depth, leaf] of [
        [-1,1.68,1.70,-.12,leftLeaves], [-1,2.85,1.19,.13,leftLeaves],
        [1,2.94,1.10,.14,rightLeaves], [1,2.23,.95,.37,archLeaves],
      ]) {
        const height = matureHeight * (.76 + .24 * age);
        const reach = .25 + length * age;
        const tip = [side*reach,depth,height+.37+.46*age,.06*thickness];
        tube([[0,0,height,.19*thickness], [side*reach*.46,depth*.55,height+.19,.13*thickness], tip]);
        crown(tip, leaf, .127);
      }
      if (paperReveal === 1) captions.push([center + plaque[0]*scale, ground - (plaque[2] + (plaque[1] - .12*frameSize)*.22)*scale]);
      for (let py = near ? 0 : 54; py < (near ? 480 : 440); py++) {
        for (let px = near ? 0 : center - 155; px < (near ? width : center + 165); px++) {
        const x = (px + .5 - center) / scale;
        const screenZ = (ground - py - .5) / scale;
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
          // 各方向采样按同一表面法线混合，融合接头无需分配纹理边界。
          const wx = nx * nx, wy = ny * ny, wz = nz * nz;
          const wood = (wx * grain(y,z) + wy * grain(x,z) + wz * grain(x,y)) / (wx + wy + wz || 1);
          const tone = light * (.72 + wood * (.33 + .23 * age));
          const pixel = (py * width + px) * 4;
          const paperHeight = .262 * frameSize;
          const paper = paperReveal > 0 && Math.abs(x - plaque[0]) < .205 * frameSize
            && z > plaque[2] - paperHeight && z < plaque[2] - paperHeight + 2 * paperHeight * paperReveal
            && Math.abs(y - (plaque[1] - .12 * frameSize)) < .013;
          buffer.data[pixel] = paper ? 229 : 159 * tone;
          buffer.data[pixel+1] = paper ? 205 : 121 * tone;
          buffer.data[pixel+2] = paper ? 157 : 80 * tone;
          break;
        }
      }
      }
      ctx.putImageData(buffer, 0, 0);
      for (const placement of crowns) ctx.drawImage(leaves, ...placement);
      ctx.font = '15px Microsoft YaHei';
      ctx.fillStyle = '#493824';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'alphabetic';
      ctx.fillText(`树龄 ${age.toFixed(2)} · ${(age*5).toFixed(1)} 秒`, 18, 28);
      ctx.font = `${near ? 18 : 9}px Microsoft YaHei`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (const [x, y] of captions) {
        ['第', '一', '节'].forEach((character, i) => ctx.fillText(character, x, y + (i - 1) * scale * .15));
      }
    };
  }, [bark, canopy].map(bytes => `data:image/png;base64,${bytes.toString('base64')}`));
  for (const [name, age, near] of [['young', 0], ['middle', .5], ['mature', 1], ['plaque-close', 1, true]]) {
    await page.evaluate(([age, near]) => window.renderTree(age, near), [age, near]);
    await page.screenshot({ path: `${output}/${name}.png` });
  }
  const frames = [];
  for (let frame = 0; frame <= 40; frame++) {
    await page.evaluate(age => window.renderTree(age), frame / 40);
    frames.push(await page.screenshot({ type: 'jpeg', quality: 90 }));
  }
  const ffmpeg = resolve(process.env.LOCALAPPDATA, 'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe');
  const video = spawnSync(ffmpeg, ['-y', '-f', 'image2pipe', '-r', '8', '-c:v', 'mjpeg', '-i', 'pipe:0',
    '-c:v', 'libvpx', '-pix_fmt', 'yuv420p', resolve(output, 'growth.webm')],
  { input: Buffer.concat(frames), encoding: 'utf8' });
  if (video.status !== 0) throw Error(video.error?.message ?? video.stderr);
} finally {
  await browser.close();
}
