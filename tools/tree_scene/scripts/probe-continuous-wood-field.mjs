import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { rasterTexturedTriangle } from './raster-textured-triangle.mjs';

// 独立二维分叉验证：轮廓、体积明暗和木纹共用连续场，不叠贴侧枝。
const bark = process.argv.includes('--bark');
const output = bark ? 'build/qa/continuous-wood-bark' : 'build/qa/continuous-wood-field';
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 560, height: 520 } });
  await page.setContent('<body style="margin:0"><canvas width="560" height="520"></canvas>');
  await page.addScriptTag({content:rasterTexturedTriangle.toString()});
  await page.evaluate(bark => {
    const canvas = document.querySelector('canvas');
    const ctx = canvas.getContext('2d');
    const width = canvas.width, height = canvas.height, count = width * height;
    const noise = new Float32Array(count);
    let seed = 73421;
    for (let i = 0; i < count; i++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      noise[i] = seed / 4294967296;
    }
    const sample = (data, x, y) => {
      x = Math.max(0, Math.min(width - 1.001, x));
      y = Math.max(0, Math.min(height - 1.001, y));
      const ix = Math.floor(x), iy = Math.floor(y), u = x - ix, v = y - iy;
      const i = iy * width + ix;
      return (data[i] * (1-u) + data[i+1] * u) * (1-v)
        + (data[i+width] * (1-u) + data[i+width+1] * u) * v;
    };
    const bakeWoodField = age => {
      const segments = [];
      const branchLength = 65 + 115 * age;
      const curves = [
        { p: [[280, 510], [257, 330], [290, 160], [275, 15]], r: [43+17*age, 26+11*age] },
        { p: [[273, 344], [317, 326], [320+branchLength*.5, 277], [290+branchLength, 232-35*age]], r: [24+13*age, 6+4*age] },
      ];
      for (const curve of curves) {
        const point = t => {
          const s = 1-t;
          return [0,1].map(axis => s*s*s*curve.p[0][axis] + 3*s*s*t*curve.p[1][axis]
            + 3*s*t*t*curve.p[2][axis] + t*t*t*curve.p[3][axis]);
        };
        for (let k=0; k<28; k++) {
          const a = point(k/28), b = point((k+1)/28);
          const dx = b[0]-a[0], dy = b[1]-a[1], length = Math.hypot(dx,dy);
          segments.push({a, dx, dy, length, curve, t:k/28});
        }
      }
      const depth = new Float32Array(count), flowX = new Float32Array(count), flowY = new Float32Array(count);
      for (let y=0; y<height; y++) for (let x=0; x<width; x++) {
        const nearest = [];
        for (let group=0; group<2; group++) {
          let best = {d:-Infinity};
          for (const s of segments.slice(group*28,group*28+28)) {
            const t = Math.max(0,Math.min(1,((x-s.a[0])*s.dx+(y-s.a[1])*s.dy)/(s.length*s.length)));
            const radius = s.curve.r[0] + (s.curve.r[1]-s.curve.r[0])*(s.t+t/28);
            const d = radius-Math.hypot(x-s.a[0]-t*s.dx,y-s.a[1]-t*s.dy);
            if (d>best.d) best = {d, vx:s.dx/s.length, vy:s.dy/s.length};
          }
          nearest.push(best);
        }
        const [a,b] = nearest;
        // 光滑并集只作用于接头，木纹沿同一个混合方向场延伸。
        const blend = Math.max(0,Math.min(1,.5+.5*(a.d-b.d)/18));
        const i = y*width+x;
        depth[i] = b.d*(1-blend)+a.d*blend+18*blend*(1-blend);
        const vx=a.vx*blend+b.vx*(1-blend), vy=a.vy*blend+b.vy*(1-blend);
        const length=Math.hypot(vx,vy);
        flowX[i]=vx/length; flowY[i]=vy/length;
      }
      const image = ctx.createImageData(width,height);
      const youngImage = ctx.createImageData(width,height);
      const relief = new Float32Array(count), plateTone = new Float32Array(count);
      if(bark) {
        // 块面种子只分布一次，方向取自同一木质场，分叉不另起贴图。
        const cells=[],cellColumns=Math.ceil(width/16)+2;
        const hash=(x,y)=>{
          let value=Math.imul(x+173,374761393)^Math.imul(y+419,668265263);
          value=Math.imul(value^(value>>>13),1274126177);
          return ((value^(value>>>16))>>>0)/4294967296;
        };
        for(let row=-1;row<=Math.ceil(height/16);row++) for(let col=-1;col<=Math.ceil(width/16);col++) {
          const x=(col+.2+.6*hash(col,row))*16,y=(row+.2+.6*hash(row,col))*16;
          cells.push({x,y,vx:sample(flowX,x,y),vy:sample(flowY,x,y),tone:hash(col+31,row-17)});
        }
        for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
          const i=y*width+x;
          if(depth[i]<-.5) continue;
          const col=Math.floor(x/16),row=Math.floor(y/16);
          const px=x+(sample(noise,x*.13,y*.13)-.5)*5;
          const py=y+(sample(noise,100+x*.11,70+y*.11)-.5)*5;
          let first=Infinity,second=Infinity,tone=0;
          for(let cy=Math.max(-1,row-3);cy<=Math.min(Math.ceil(height/16),row+3);cy++) {
            for(let cx=Math.max(-1,col-3);cx<=Math.min(Math.ceil(width/16),col+3);cx++) {
              const cell=cells[(cy+1)*cellColumns+cx+1];
              const dx=px-cell.x,dy=py-cell.y;
              const along=dx*cell.vx+dy*cell.vy,across=dx*cell.vy-dy*cell.vx;
              const distance=Math.hypot(along*.45,across*1.3);
              if(distance<first) {second=first;first=distance;tone=cell.tone;}
              else if(distance<second) second=distance;
            }
          }
          const gap=second-first;
          relief[i]=(1-Math.exp(-gap*1.2))*(.86+.14*sample(noise,x*.19,y*.19));
          plateTone[i]=tone;
        }
      }
      let covered=0;
      for (let y=0; y<height; y++) for (let x=0; x<width; x++) {
        const i=y*width+x, pixel=i*4;
        if(depth[i]<-.5) continue;
        let grain=0, weights=0;
        // 对固定噪声做双向流线卷积，避免每条枝独立UV造成横向断带。
        for (const sign of [-1,1]) {
          let px=x,py=y;
          for(let step=0;step<32;step++) {
            const weight=1-step/33;
            grain+=sample(noise,px,py)*weight; weights+=weight;
            const vx=sample(flowX,px,py),vy=sample(flowY,px,py);
            px+=vx*1.2*sign; py+=vy*1.2*sign;
          }
        }
        grain=grain/weights;
        const dx=(sample(depth,x+1,y)-sample(depth,x-1,y))*.5;
        const dy=(sample(depth,x,y+1)-sample(depth,x,y-1))*.5;
        const rim=Math.exp(-Math.max(0,depth[i])/13);
        const light=.78+rim*(-dx*.24-dy*.12-.18);
        const fissure=Math.max(0,(.48-grain)*8);
        let color=[133,99,61].map((base,c)=>base*light-fissure*[55,45,29][c]+(grain-.5)*90);
        if(bark) {
          const nx=(sample(relief,x+1,y)-sample(relief,x-1,y))*.5;
          const ny=(sample(relief,x,y+1)-sample(relief,x,y-1))*.5;
          const facet=.83-nx*.38-ny*.28+(plateTone[i]-.5)*.22;
          const crack=Math.exp(-relief[i]*5);
          const barkLight=.60+.28*(1-rim)+rim*(dx*.24-dy*.12);
          color=[142,115,78].map((base,c)=>base*barkLight*facet-crack*[63,51,33][c]
            -fissure*[75,58,36][c]+(grain-.5)*120+(noise[i]-.5)*7);
        }
        const alpha=Math.max(0,Math.min(1,depth[i]+.5));
        for(let c=0;c<3;c++) image.data[pixel+c]=color[c];
        image.data[pixel+3]=255*alpha;
        if(bark) {
          const barkLight=.60+.28*(1-rim)+rim*(dx*.24-dy*.12);
          for(let c=0;c<3;c++) youngImage.data[pixel+c]=[129,112,73][c]*barkLight*.9+(grain-.5)*32;
          youngImage.data[pixel+3]=image.data[pixel+3];
        }
        covered++;
      }
      return {image,youngImage,covered,finite:[...depth,...flowX,...flowY].every(Number.isFinite)};
    };
    // 只生成一次成熟材质；局部发育只改变网格位置，不重新计算木纹。
    const baked = bakeWoodField(1);
    const vertices=[];
    for(let y=0;y<=height;y+=4) for(let x=0;x<=width;x+=4) {
      // 枝内逐渐转为侧枝长度控制；主干及接合处使用同一组顶点。
      const reach=Math.max(0,Math.min(1,(x-290)/80));
      const branchWeight=reach*reach*(3-2*reach);
      vertices.push({uv:[x,y],branchWeight});
    }
    const columns=width/4+1;
    const triangles=[];
    for(let row=0;row<height/4;row++) for(let col=0;col<width/4;col++) {
      const a=row*columns+col,b=a+1,c=a+columns,d=c+1;
      triangles.push([a,b,c],[b,d,c]);
    }
    window.renderWoodField = age => {
      const trunkScale=(43+17*age)/60;
      const branchScale=(65+115*age)/180;
      const positions=vertices.map(({uv:[x,y],branchWeight:w})=>[
        275+(x-275)*trunkScale+w*(x-290)*(branchScale-trunkScale),
        y+w*(344-y)*.16*(1-age),
      ]);
      const image=ctx.createImageData(width,height);
      let texture=baked.image;
      if(bark) {
        // 仅改变同一UV处裂纹的可见强度，纹理位置及随机种子保持不变。
        texture=ctx.createImageData(width,height);
        const maturity=age**1.5;
        for(let i=0;i<texture.data.length;i++) texture.data[i]=baked.youngImage.data[i]
          +(baked.image.data[i]-baked.youngImage.data[i])*maturity;
      }
      let minimumArea=Infinity;
      for(const ids of triangles) {
        const points=ids.map(i=>positions[i]);
        const [a,b,c]=points;
        const area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
        if(area<=0) throw Error('共享木质网格发生翻转');
        minimumArea=Math.min(minimumArea,area);
        window.rasterTexturedTriangle(image,texture,points,ids.map(i=>vertices[i].uv));
      }
      ctx.clearRect(0,0,width,height);
      ctx.putImageData(image,0,0);
      ctx.globalCompositeOperation='destination-over';
      ctx.fillStyle='#f6efdf';ctx.fillRect(0,0,width,height);
      ctx.globalCompositeOperation='source-over';
      ctx.fillStyle='#493824'; ctx.font='16px Microsoft YaHei';
      ctx.fillText(`共享木质域 · 年龄 ${age.toFixed(2)}`,20,30);
      return {age,sourceCovered:baked.covered,finite:baked.finite,minimumArea,triangles:triangles.length};
    };
  },bark);
  const results=[];
  for (const [name,age] of [['young',0],['middle',.5],['mature',1]]) {
    const check=await page.evaluate(age=>window.renderWoodField(age),age);
    if(!check.finite) throw Error('木质场含非有限数值');
    results.push(check);
    await page.screenshot({path:`${output}/${name}.png`});
  }
  const intervals=[],frames=[];
  for(let frame=0;frame<=40;frame++) {
    intervals.push(await page.evaluate(age=>window.renderWoodField(age),frame/40));
    frames.push(await page.screenshot({type:'jpeg',quality:90}));
  }
  const encode=spawnSync(resolve(process.env.LOCALAPPDATA,'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe'),
    ['-y','-f','image2pipe','-r','8','-c:v','mjpeg','-i','pipe:0','-c:v','libvpx','-pix_fmt','yuv420p',resolve(output,'deformation.webm')],
    {input:Buffer.concat(frames),encoding:'utf8'});
  if(encode.status!==0) throw Error(encode.error?.message??encode.stderr);
  await writeFile(`${output}/result.json`,JSON.stringify({stills:results,frames:intervals.length,
    minimumArea:Math.min(...intervals.map(x=>x.minimumArea)),textureBakes:1,fixedUV:true},null,2));
} finally { await browser.close(); }
