import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { rasterTexturedTriangle } from './raster-textured-triangle.mjs';

const assembly = process.argv.includes('--assembly');
const capture = assembly && process.argv.includes('--capture');
const raster = process.argv.includes('--raster');
const roundTwo = capture && process.argv.includes('--round-two');
const output = raster ? 'build/qa/layered-tree-raster' : roundTwo ? 'build/qa/layered-tree-second-review' : capture ? 'build/qa/layered-tree-first-review'
  : assembly ? 'build/qa/layered-tree-assembly' : 'build/qa/root-collar-stem-transition';
await mkdir(output, { recursive: true });
const root = await readFile('assets/source/magic_tree/textures_source/root_collar_buttress_v1.png');
const crown = assembly ? await readFile('assets/source/magic_tree/textures_source/secondary_bough_layered_v1.png') : root;
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  headless: true,
});
try {
  const width = capture ? 380 : 1140;
  const page = await browser.newPage({ viewport: { width, height: assembly ? 600 : 380 } });
  await page.setContent(`<body style="margin:0"><canvas width="${width}" height="${assembly ? 600 : 380}"></canvas>`);
  await page.addScriptTag({content:rasterTexturedTriangle.toString()});
  await page.evaluate(async ([source, crownSource, assembly, capture, roundTwo, raster]) => {
    const image = new Image();
    image.src = source;
    const leaves = new Image();
    leaves.src = crownSource;
    await Promise.all([image.decode(), leaves.decode()]);
    const textureCanvas = new OffscreenCanvas(image.width,image.height);
    const textureContext = textureCanvas.getContext('2d');
    textureContext.drawImage(image,0,0);
    const sourceTexture = textureContext.getImageData(0,0,image.width,image.height);
    const ctx = document.querySelector('canvas').getContext('2d');
    // 横向控制线分别经过侧根、前根与根颈，各区随高度独立展宽。
    const columns = [0, 370, 640, 887, 1150, 1440, 1774];
    const youngOffsets = [350, 235, 123, 0, -105, -202, -320];
    window.renderAssembly = (selectedAge, near = false) => {
    ctx.setTransform(1,0,0,1,0,0);
    ctx.fillStyle = '#f6efdf';
    ctx.fillRect(0,0,ctx.canvas.width,ctx.canvas.height);
    if (near) ctx.setTransform(2,0,0,2,-310,-320);
    let triangles = 0;
    let minimumArea = Infinity;
    const ages = capture ? [selectedAge] : [0, .5, 1];
    for (const [index, age] of ages.entries()) {
      const center = 190 + index * 380;
      const scale = assembly ? .07 + .04 * age : .12 + .06 * age;
      const anchorY = 76;
      const height = .53 + .47 * age;
      const top = (assembly ? 520 : 295) - Math.round((833 - anchorY) * scale * height);
      // 上段从接缝同一采样行开始，往上保持木纹纵向比例。
      ctx.filter = 'saturate(.83) brightness(.94)';
      const stemHeight = Math.round(assembly ? 105 + (roundTwo ? 110 : 140) * age : 51 + 20 * age);
      for (let distance = stemHeight; distance > 0; distance--) {
        const travel = distance / (scale * height);
        const repeat = travel % 284;
        const sourceY = 76 + Math.min(repeat, 284 - repeat);
        const taper = 1 - (assembly ? (roundTwo ? .62 : .81) : .21) * distance / stemHeight;
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
        const leafScale = .045 + (roundTwo ? .049 : .041) * age;
        crownAt(center, top - stemHeight, leafScale);
        for (const [side, level, reach] of [[-1,.38,1], [1,.55,1.1], [-1,.75,.78]]) {
          const y = top - stemHeight * level;
          const endX = center + side * (23 + 65 * age) * reach;
          const endY = y - (13 + 28 * age);
          ctx.save();
          // 同一截面数组驱动木枝轮廓、纹理映射与枝端接点。
          const rings = [];
          const radius = 501 * scale * (1 - (roundTwo ? .62 : .81) * level) * (roundTwo ? .32 : .23);
          for (let step = 0; step <= 12; step++) {
            const t = step / 12;
            const x = center + (endX - center) * t;
            const z = y + (endY - y) * t * t;
            const half = radius * (1 - (roundTwo ? .72 : .86) * t);
            rings.push([[x, z - half], [x, z + half]]);
          }
          const paintedCanvas = new OffscreenCanvas(ctx.canvas.width,ctx.canvas.height);
          const paintedContext = paintedCanvas.getContext('2d');
          const painted = paintedContext.createImageData(ctx.canvas.width,ctx.canvas.height);
          const drawTriangle = (destination, source) => {
            const [a,b,c] = source, [p,q,r] = destination;
            const determinant = (b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]);
            const area = (q[0]-p[0])*(r[1]-p[1])-(r[0]-p[0])*(q[1]-p[1]);
            if (Math.abs(area) < .0001 || Math.abs(determinant) < .0001) throw Error('母枝纹理三角退化');
            if (area * side <= 0) throw Error('母枝三角朝向错误');
            triangles++;
            minimumArea = Math.min(minimumArea, Math.abs(area));
            if(raster){window.rasterTexturedTriangle(painted,sourceTexture,destination,source);return;}
            const m11=((q[0]-p[0])*(c[1]-a[1])-(r[0]-p[0])*(b[1]-a[1]))/determinant;
            const m21=((r[0]-p[0])*(b[0]-a[0])-(q[0]-p[0])*(c[0]-a[0]))/determinant;
            const m12=((q[1]-p[1])*(c[1]-a[1])-(r[1]-p[1])*(b[1]-a[1]))/determinant;
            const m22=((r[1]-p[1])*(b[0]-a[0])-(q[1]-p[1])*(c[0]-a[0]))/determinant;
            ctx.save();
            ctx.beginPath();
            ctx.moveTo(...p);
            ctx.lineTo(...q);
            ctx.lineTo(...r);
            ctx.closePath();
            ctx.clip();
            ctx.transform(m11,m12,m21,m22,p[0]-m11*a[0]-m21*a[1],p[1]-m12*a[0]-m22*a[1]);
            ctx.drawImage(image,0,0);
            ctx.restore();
          };
          for (let row = 0; row < rings.length - 1; row++) {
            const v0 = 76 + row * 12, v1 = v0 + 12;
            const uvLeft = roundTwo ? 795 : 636, uvRight = roundTwo ? 978 : 1137;
            const source = [[uvLeft,v0],[uvRight,v0],[uvLeft,v1],[uvRight,v1]];
            const points = [...rings[row], ...rings[row+1]];
            for (const ids of [[0,2,1],[1,2,3]]) {
              drawTriangle(ids.map(i=>points[i]),ids.map(i=>source[i]));
            }
          }
          if(raster){paintedContext.putImageData(painted,0,0);ctx.drawImage(paintedCanvas,0,0);}
          ctx.restore();
          crownAt(endX, endY, leafScale * .83, side > 0);
          if (side > 0 && age > .65) {
            const px = center + (endX-center)*.72;
            const py = y + (endY-y)*.55;
            ctx.fillStyle = '#65432c';
            if (roundTwo) {
              ctx.beginPath();
              ctx.roundRect(px - 15, py - 46, 30, 48, [8,7,5,8]);
              ctx.fill();
              ctx.strokeStyle = '#a27c46';
              ctx.lineWidth = 1.3;
              ctx.stroke();
            } else ctx.fillRect(px - 13, py - 44, 26, 46);
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
    return { triangles, minimumArea };
    };
    window.renderAssembly(0);
  }, [...[root,crown].map(bytes => `data:image/png;base64,${bytes.toString('base64')}`), assembly, capture, roundTwo, raster]);
  if (capture) {
    for (const [name, age, near] of [['young',0],['middle',.5],['mature',1],['plaque-close',1,true]]) {
      await page.evaluate(([age,near]) => window.renderAssembly(age,near), [age,near]);
      await page.screenshot({path:`${output}/${name}.png`});
    }
    const frames = [], checks = [];
    for (let frame=0; frame<=40; frame++) {
      checks.push(await page.evaluate(age=>window.renderAssembly(age),frame/40));
      frames.push(await page.screenshot({type:'jpeg',quality:90}));
    }
    const ffmpeg=resolve(process.env.LOCALAPPDATA,'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe');
    const encode=spawnSync(ffmpeg,['-y','-f','image2pipe','-r','8','-c:v','mjpeg','-i','pipe:0',
      '-c:v','libvpx','-pix_fmt','yuv420p',resolve(output,'growth.webm')],{input:Buffer.concat(frames),encoding:'utf8'});
    if(encode.status!==0) throw Error(encode.error?.message??encode.stderr);
    await writeFile(`${output}/result.json`,JSON.stringify({frames:frames.length,fps:8,
      triangles:checks[0].triangles,minimumArea:Math.min(...checks.map(check=>check.minimumArea))},null,2));
  } else await page.screenshot({ path: `${output}/comparison.png` });
} finally {
  await browser.close();
}
