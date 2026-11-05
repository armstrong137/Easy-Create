import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { rasterTexturedTriangle } from './raster-textured-triangle.mjs';
import { continuousTreeCurves } from './continuous-tree-layout.mjs';

// 独立二维分叉验证：轮廓、体积明暗和木纹共用连续场，不叠贴侧枝。
const whole = process.argv.includes('--whole');
const roundTwo = whole && process.argv.includes('--round-two');
const bark = whole || process.argv.includes('--bark');
const output = roundTwo ? 'build/qa/continuous-field-second-review' : whole ? 'build/qa/continuous-field-first-review' : bark ? 'build/qa/continuous-wood-bark' : 'build/qa/continuous-wood-field';
await mkdir(output, { recursive: true });
const browser = await chromium.launch({
  executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 560, height: whole ? 700 : 520 } });
  await page.setContent(`<body style="margin:0"><canvas width="560" height="${whole ? 700 : 520}"></canvas>`);
  await page.addScriptTag({content:rasterTexturedTriangle.toString()});
  await page.addScriptTag({content:continuousTreeCurves.toString()});
  await page.evaluate(([bark,whole,roundTwo]) => {
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
    let referenceSegments;
    const bakeWoodField = (age,material=null,camera=null) => {
      const segments = [];
      const branchLength = 65 + 115 * age;
      const curves = whole ? window.continuousTreeCurves(age,roundTwo) : [
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
      if(!material) referenceSegments=segments;
      const bounds=curves.map(curve=>({left:Math.min(...curve.p.map(p=>p[0]))-Math.max(...curve.r)-32,
        right:Math.max(...curve.p.map(p=>p[0]))+Math.max(...curve.r)+32,
        top:Math.min(...curve.p.map(p=>p[1]))-Math.max(...curve.r)-32,
        bottom:Math.max(...curve.p.map(p=>p[1]))+Math.max(...curve.r)+32}));
      const depth = new Float32Array(count), flowX = new Float32Array(count), flowY = new Float32Array(count);
      const uvX=material ? new Float32Array(count) : null,uvY=material ? new Float32Array(count) : null;
      for (let row=0; row<height; row++) for (let col=0; col<width; col++) {
        const x=camera ? camera.x+(col-width/2)/camera.scale : col;
        const y=camera ? camera.y+(row-height/2)/camera.scale : row;
        const i=row*width+col;
        if(material && !bounds.some(b=>x>=b.left && x<=b.right && y>=b.top && y<=b.bottom)) {
          depth[i]=-100;flowY[i]=-1;
          continue;
        }
        const nearest = [];
        for (let group=0; group<curves.length; group++) {
          let best = {d:-Infinity};
          for (let k=0;k<28;k++) {
            const s=segments[group*28+k];
            const t = Math.max(0,Math.min(1,((x-s.a[0])*s.dx+(y-s.a[1])*s.dy)/(s.length*s.length)));
            const radius = s.curve.r[0] + (s.curve.r[1]-s.curve.r[0])*(s.t+t/28);
            const d = radius-Math.hypot(x-s.a[0]-t*s.dx,y-s.a[1]-t*s.dy);
            const sign=whole && s.dy>0 ? -1 : 1;
            if (d>best.d) best = {d, vx:sign*s.dx/s.length, vy:sign*s.dy/s.length,s,t,radius,group,k};
          }
          nearest.push(best);
        }
        let a=nearest[0];
        // 光滑并集只作用于接头，木纹沿同一个混合方向场延伸。
        for(const b of nearest.slice(1)) {
        const join=whole ? 8 : 18;
        const blend = Math.max(0,Math.min(1,.5+.5*(a.d-b.d)/join));
        a={d:b.d*(1-blend)+a.d*blend+join*blend*(1-blend),
          vx:a.vx*blend+b.vx*(1-blend),vy:a.vy*blend+b.vy*(1-blend)};
        }
        if(material && a.d>=-.5) {
          const maxDistance=Math.max(...nearest.map(b=>b.d));
          let sum=0,sx=0,sy=0;
          for(const b of nearest) {
            const weight=Math.exp((b.d-maxDistance)/4),s=b.s,source=referenceSegments[b.group*28+b.k];
            const px=s.a[0]+s.dx*b.t,py=s.a[1]+s.dy*b.t;
            const along=((x-px)*s.dx+(y-py)*s.dy)/s.length;
            const across=((y-py)*s.dx-(x-px)*s.dy)/s.length;
            const radius=source.curve.r[0]+(source.curve.r[1]-source.curve.r[0])*(source.t+b.t/28);
            sx+=(source.a[0]+source.dx*b.t+along*source.dx/s.length-across*source.dy/source.length*radius/b.radius)*weight;
            sy+=(source.a[1]+source.dy*b.t+along*source.dy/s.length+across*source.dx/source.length*radius/b.radius)*weight;
            sum+=weight;
          }
          uvX[i]=sx/sum;uvY[i]=sy/sum;
        }
        depth[i] = a.d;
        const vx=a.vx, vy=a.vy;
        const length=Math.hypot(vx,vy);
        flowX[i]=vx/length; flowY[i]=vy/length;
      }
      const image = ctx.createImageData(width,height);
      const youngImage = ctx.createImageData(width,height);
      const relief = new Float32Array(count), plateTone = new Float32Array(count);
      if(bark && !material) {
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
      let covered=0,emptyMaterialSamples=0;
      for (let y=0; y<height; y++) for (let x=0; x<width; x++) {
        const i=y*width+x, pixel=i*4;
        if(depth[i]<-.5) continue;
        if(material) {
          // 记录实体表面反查到源材质透明区的情况，不用填色掩盖绑定错误。
          if(depth[i]>.5 && sample(material.alphaChannel,uvX[i],uvY[i])<1) emptyMaterialSamples++;
          const maturity=age**1.5;
          for(let c=0;c<3;c++) image.data[pixel+c]=sample(material.youngChannels[c],uvX[i],uvY[i])*(1-maturity)
            +sample(material.channels[c],uvX[i],uvY[i])*maturity;
          image.data[pixel+3]=255*Math.max(0,Math.min(1,depth[i]*(camera?.scale ?? 1)+.5));
          covered++;
          continue;
        }
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
      return {image,youngImage,covered,emptyMaterialSamples,finite:[...depth,...flowX,...flowY].every(Number.isFinite)
        && (!material || (uvX.every(Number.isFinite) && uvY.every(Number.isFinite)))};
    };
    // 只生成一次源材质；局部用固定网格UV，整树按当前枝截面反查。
    const baked = bakeWoodField(1);
    if(whole) {
      baked.alphaChannel=Float32Array.from({length:count},(_,i)=>baked.image.data[i*4+3]);
      baked.channels=[0,1,2].map(c=>Float32Array.from({length:count},(_,i)=>baked.image.data[i*4+c]));
      baked.youngChannels=[0,1,2].map(c=>Float32Array.from({length:count},(_,i)=>baked.youngImage.data[i*4+c]));
    }
    const vertices=[];
    if(!whole) for(let y=0;y<=height;y+=4) for(let x=0;x<=width;x+=4) {
      // 枝内逐渐转为侧枝长度控制；主干及接合处使用同一组顶点。
      const reach=Math.max(0,Math.min(1,(x-290)/80));
      const branchWeight=reach*reach*(3-2*reach);
      vertices.push({uv:[x,y],branchWeight});
    }
    const columns=width/4+1;
    const triangles=[];
    if(!whole) for(let row=0;row<height/4;row++) for(let col=0;col<width/4;col++) {
      const a=row*columns+col,b=a+1,c=a+columns,d=c+1;
      triangles.push([a,b,c],[b,d,c]);
    }
    window.renderWoodField = (age,near=false) => {
      const trunkScale=(43+17*age)/60;
      const branchScale=(65+115*age)/180;
      const current=whole ? window.continuousTreeCurves(age,roundTwo) : null;
      const point=(p,t)=>[0,1].map(axis=>(1-t)**3*p[0][axis]+3*(1-t)**2*t*p[1][axis]
        +3*(1-t)*t*t*p[2][axis]+t**3*p[3][axis]);
      const frame=current?.[10];
      const positions=vertices.map(({uv:[x,y],branchWeight:w})=>[
        275+(x-275)*trunkScale+w*(x-290)*(branchScale-trunkScale),
        y+w*(344-y)*.16*(1-age),
      ]);
      const camera=roundTwo && near ? {scale:2.5,x:frame.p[0][0],y:frame.p[0][1]-29} : null;
      const surface=whole ? bakeWoodField(age,baked,camera) : null;
      const image=surface?.image ?? ctx.createImageData(width,height);
      let texture=baked.image;
      if(bark && !whole) {
        // 仅改变同一UV处裂纹的可见强度，纹理位置及随机种子保持不变。
        texture=ctx.createImageData(width,height);
        const maturity=age**1.5;
        for(let i=0;i<texture.data.length;i++) texture.data[i]=baked.youngImage.data[i]
          +(baked.image.data[i]-baked.youngImage.data[i])*maturity;
      }
      let minimumArea=Infinity;
      for(const ids of whole ? [] : triangles) {
        const points=ids.map(i=>positions[i]);
        const [a,b,c]=points;
        const area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
        if(area<=0) throw Error(`共享木质网格发生翻转 ${JSON.stringify({age,area,source:ids.map(i=>vertices[i].uv),points})}`);
        minimumArea=Math.min(minimumArea,area);
        window.rasterTexturedTriangle(image,texture,points,ids.map(i=>vertices[i].uv));
      }
      ctx.setTransform(1,0,0,1,0,0);
      ctx.clearRect(0,0,width,height);
      if(whole) {
        const woodCanvas=new OffscreenCanvas(width,height);
        woodCanvas.getContext('2d').putImageData(image,0,0);
        if(near && !roundTwo) ctx.setTransform(2.5,0,0,2.5,width/2-frame.p[0][0]*2.5,height/2-(frame.p[0][1]-25)*2.5);
        ctx.drawImage(woodCanvas,0,0);
        if(camera) ctx.setTransform(camera.scale,0,0,camera.scale,width/2-camera.x*camera.scale,height/2-camera.y*camera.scale);
      } else ctx.putImageData(image,0,0);
      const drawCrown=front=>{
        if(!whole) return;
        let seed=59231;
        const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
        if(roundTwo) {
          for(const [index,branch] of current.entries()) {
            if(branch.kind!=='branch') continue;
            const growth=branch.growth,side=index%2 ? 1 : -1;
            for(const level of [.25,.58,.9]) {
              const base=point(branch.p,level);
              const twig=(x,y,length,angle,depth)=>{
                const bend=(random()-.5)*.4;
                const end=[x+Math.cos(angle+bend)*length,y+Math.sin(angle+bend)*length];
                ctx.strokeStyle=depth>1 ? '#645334' : '#75633a';
                ctx.lineWidth=(.3+growth*.45)*depth;
                ctx.beginPath();ctx.moveTo(x,y);
                ctx.quadraticCurveTo(x+Math.cos(angle)*length*.6,y+Math.sin(angle)*length*.6,...end);ctx.stroke();
                if(depth>1) {
                  twig(...end,length*(.59+random()*.1),angle-.55-random()*.18,depth-1);
                  twig(...end,length*(.59+random()*.1),angle+.50+random()*.2,depth-1);
                }
                const count=depth===1 ? 7 : 2;
                for(let n=0;n<count;n++) {
                  const t=.3+n/count*.7,flip=n%2 ? 1 : -1;
                  const leafAngle=angle+flip*(.55+random()*.5),light=random(),layer=random()>.42;
                  const size=1.8+(1.8+random()*1.3)*growth;
                  const px=x+(end[0]-x)*t,py=y+(end[1]-y)*t;
                  if(layer!==front) continue;
                  ctx.save();ctx.translate(px,py);ctx.rotate(leafAngle);
                  ctx.fillStyle=`rgb(${65+Math.round(light*63)},${65+Math.round(light*48)},${27+Math.round(light*24)})`;
                  ctx.beginPath();ctx.ellipse(size*.7,0,size,size*.42,0,0,Math.PI*2);ctx.fill();
                  ctx.strokeStyle='rgba(208,182,95,.32)';ctx.lineWidth=.3;
                  ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(size*1.6,0);ctx.stroke();ctx.restore();
                }
              };
              twig(...base,5+(32+13*level)*growth,-Math.PI/2+side*(.3+level*.3),5);
            }
          }
          return;
        }
        for(const [index,branch] of current.entries()) {
          if(branch.kind!=='branch') continue;
          const growth=branch.growth;
          for(const level of [.45,.72,1]) {
            const base=point(branch.p,level);
            const spread=4+35*growth;
            const side=index%2 ? 1 : -1;
            const center=[base[0]+side*spread*.2,base[1]-spread*.5];
            ctx.strokeStyle='#5c4d2d';ctx.lineWidth=.5+growth;
            ctx.beginPath();ctx.moveTo(...base);ctx.lineTo(...center);ctx.stroke();
            for(let n=0;n<190;n++) {
              const radius=Math.sqrt(random()),angle=random()*Math.PI*2;
              const x=center[0]+Math.cos(angle)*radius*spread*1.15;
              const y=center[1]+Math.sin(angle)*radius*spread*.72;
              const turn=random()*Math.PI,light=random(),layer=random()>.45;
              const leafLength=1.1+(1.1+random()*2.2)*growth;
              if(layer!==front || n>24+166*growth) continue;
              ctx.strokeStyle='rgba(61,54,28,.4)';ctx.lineWidth=.4;
              ctx.beginPath();ctx.moveTo(...center);ctx.lineTo(x,y);ctx.stroke();
              ctx.save();ctx.translate(x,y);ctx.rotate(turn);
              ctx.fillStyle=`rgb(${68+Math.round(light*61)},${67+Math.round(light*48)},${29+Math.round(light*20)})`;
              ctx.beginPath();ctx.ellipse(0,0,leafLength,leafLength*.43,0,0,Math.PI*2);ctx.fill();
              ctx.strokeStyle='rgba(208,182,95,.28)';ctx.lineWidth=.35;
              ctx.beginPath();ctx.moveTo(-leafLength*.6,0);ctx.lineTo(leafLength*.8,0);ctx.stroke();ctx.restore();
            }
          }
        }
      };
      ctx.globalCompositeOperation='destination-over';
      if(roundTwo) {
        const shadow=ctx.createRadialGradient(280,650,3,280,650,135);
        shadow.addColorStop(0,'rgba(65,48,26,.32)');shadow.addColorStop(1,'rgba(65,48,26,0)');
        ctx.save();ctx.translate(280,650);ctx.scale(1,.14);ctx.translate(-280,-650);
        ctx.fillStyle=shadow;ctx.fillRect(140,510,280,280);ctx.restore();
      }
      drawCrown(false);
      ctx.fillStyle='#f6efdf';ctx.fillRect(0,0,width,height);
      ctx.globalCompositeOperation='source-over';
      drawCrown(true);
      if(whole && frame.growth>.08) {
        const foot=frame.p[0],high=.6+(roundTwo ? 62 : 53)*frame.growth,half=.3+(roundTwo ? 21 : 17)*frame.growth;
        ctx.fillStyle='#ead3a3';
        ctx.beginPath();ctx.ellipse(foot[0],foot[1]-high*.5,half*.9,high*.40,0,0,Math.PI*2);ctx.fill();
        if(roundTwo) {
          ctx.strokeStyle='#a17c42';ctx.lineWidth=.8;
          ctx.beginPath();ctx.ellipse(foot[0],foot[1]-high*.5,half*.99,high*.46,0,0,Math.PI*2);ctx.stroke();
        }
        if(frame.growth>.85) {
          ctx.fillStyle='#372a1b';ctx.font='10px Microsoft YaHei';ctx.textAlign='center';
          ['第','一','节'].forEach((text,i)=>ctx.fillText(text,foot[0],foot[1]-high*.7+i*11));
          ctx.textAlign='left';
        }
      }
      ctx.setTransform(1,0,0,1,0,0);
      ctx.fillStyle='#493824'; ctx.font='16px Microsoft YaHei';
      if(whole) {
        ctx.fillStyle='rgba(246,239,223,.94)';ctx.fillRect(0,0,width,42);ctx.fillStyle='#493824';
      }
      ctx.fillText(whole ? `树龄 ${age.toFixed(2)} · 演示时间 ${(age*5).toFixed(2)} 秒` : `共享木质域 · 年龄 ${age.toFixed(2)}`,20,30);
      return {age,sourceCovered:baked.covered,covered:surface?.covered,finite:surface?.finite ?? baked.finite,
        emptyMaterialSamples:surface?.emptyMaterialSamples,
        minimumArea:whole ? null : minimumArea,triangles:whole ? 0 : triangles.length};
    };
  },[bark,whole,roundTwo]);
  const results=[];
  const poses=[['young',0],['middle',.5],['mature',1],...(whole ? [['plaque-close',1,true]] : [])];
  for (const [name,age,near=false] of poses) {
    const check=await page.evaluate(([age,near])=>window.renderWoodField(age,near),[age,near]);
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
    minimumArea:whole ? null : Math.min(...intervals.map(x=>x.minimumArea)),textureBakes:1,fixedUV:!whole,
    emptyMaterialSamplesMax:whole ? Math.max(...intervals.map(x=>x.emptyMaterialSamples)) : null,
    materialMapping:whole ? '按当前枝截面反查同一源木质域；接头混合，附着仍待独立验证' : '固定网格UV'},null,2));
} finally { await browser.close(); }
