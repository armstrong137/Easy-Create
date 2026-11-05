import { chromium } from 'playwright';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { rasterTexturedTriangle } from './raster-textured-triangle.mjs';

// 复用已验证的局部分枝几何，只验证连续材质图集，不恢复退役整树。
const hierarchical=process.argv.includes('--hierarchical');
const painted=hierarchical || process.argv.includes('--painted');
const directory=hierarchical ? 'build/qa/hierarchical-bark-proof' : 'build/qa/branch-development-proof';
const output=hierarchical ? 'build/qa/hierarchical-painted-bark' : painted ? 'build/qa/painted-shared-bark' : 'build/qa/transported-bark';
await mkdir(output,{recursive:true});
const metadata=JSON.parse(await readFile(`${directory}/mesh.json`));
if(metadata.vertexCount!==(hierarchical ? 1023 : 801) || metadata.triangleCount!==(hierarchical ? 1798 : 1408)) throw Error('分叉网格版本不匹配');
const binary=await readFile(`${directory}/mesh.bin`);
const values=name=>{
  const section=metadata.sections[name];
  return Array.from({length:section.length},(_,i)=>binary.readFloatLE(section.offset+i*4));
};
const corners=values('corners');
const faces=Array.from({length:corners.length/9},(_,i)=>[corners[i*9],corners[i*9+3],corners[i*9+6]]);
const sourcePath=hierarchical ? 'assets/source/magic_tree/textures_source/hierarchical_fork_bark_field_v1.png'
  : painted ? 'assets/source/magic_tree/textures_source/shared_fork_bark_field_v1.png'
  : 'assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png';
const source=await readFile(sourcePath);
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
try {
  const page=await browser.newPage({viewport:{width:560,height:700}});
  await page.setContent('<body style="margin:0"><canvas width="560" height="700"></canvas>');
  await page.addScriptTag({content:rasterTexturedTriangle.toString()});
  const bake=await page.evaluate(async ({poses,faces,normals,ages,photo,painted,hierarchical})=>{
    const resolution=painted ? 2 : 1,width=400*resolution,height=720*resolution,count=width*height;
    const ctx=document.querySelector('canvas').getContext('2d');
    const source=new Image();source.src=photo;await source.decode();
    const photoCanvas=new OffscreenCanvas(source.width,source.height),photoContext=photoCanvas.getContext('2d');
    photoContext.drawImage(source,0,0);
    const pixels=photoContext.getImageData(0,0,source.width,source.height);
    for(let i=3;i<pixels.data.length;i+=4) if(pixels.data[i]!==255) throw Error('树皮材质源包含透明像素');
    const rest=poses.at(-1);
    const uv=Array.from({length:rest.length/3},(_,i)=>[((rest[i*3]+.5)*95+20)*resolution,((6.9-rest[i*3+2])*95+20)*resolution]);
    const atlas=new ImageData(width,height);
    const white={width:1,height:1,data:new Uint8ClampedArray([255,255,255,255])};
    if(!painted) for(const face of faces) window.rasterTexturedTriangle(atlas,white,face.map(i=>uv[i]),[[.5,.5],[.5,.5],[.5,.5]]);
    const sample=(data,x,y)=>{
      x=Math.max(0,Math.min(width-1.001,x));y=Math.max(0,Math.min(height-1.001,y));
      const ix=Math.floor(x),iy=Math.floor(y),a=x-ix,b=y-iy,i=iy*width+ix;
      return (data[i]*(1-a)+data[i+1]*a)*(1-b)+(data[i+width]*(1-a)+data[i+width+1]*a)*b;
    };
    const groups=[];
    const parent=Array.from({length:65},(_,row)=>({center:uv[row*9+4],radius:Math.abs(uv[row*9+8][0]-uv[row*9][0])/2}));
    const base=Array.from({length:9},(_,i)=>uv[(20+i)*9+8]);
    const child=[{center:[base.reduce((v,p)=>v+p[0],0)/9,base.reduce((v,p)=>v+p[1],0)/9],
      radius:Math.hypot(base[8][0]-base[0][0],base[8][1]-base[0][1])/2},
      ...Array.from({length:24},(_,row)=>({center:uv[585+row*9+4],
        radius:Math.hypot(uv[585+row*9+8][0]-uv[585+row*9][0],uv[585+row*9+8][1]-uv[585+row*9][1])/2}))];
    for(const chain of [parent,child]) groups.push(chain.slice(1).map((b,i)=>{
      const a=chain[i],dx=b.center[0]-a.center[0],dy=b.center[1]-a.center[1];
      return {a:a.center,dx,dy,length:Math.hypot(dx,dy),radius:(a.radius+b.radius)/2};
    }));
    const flowX=new Float32Array(count),flowY=new Float32Array(count);
    if(!painted) for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
      const nearest=groups.map(group=>{
        let best={d:-Infinity};
        for(const s of group) {
          const t=Math.max(0,Math.min(1,((x-s.a[0])*s.dx+(y-s.a[1])*s.dy)/(s.length*s.length)));
          const d=s.radius-Math.hypot(x-s.a[0]-s.dx*t,y-s.a[1]-s.dy*t);
          if(d>best.d) best={d,vx:s.dx/s.length,vy:s.dy/s.length};
        }
        return best;
      });
      const [a,b]=nearest,weight=Math.max(0,Math.min(1,.5+(a.d-b.d)/16));
      const vx=a.vx*weight+b.vx*(1-weight),vy=a.vy*weight+b.vy*(1-weight),length=Math.hypot(vx,vy);
      flowX[y*width+x]=vx/length;flowY[y*width+x]=vy/length;
    }
    let covered=0,unfinished=0;
    const baseY=parent[0].center[1];
    const chartX=new Float32Array(count),chartY=new Float32Array(count);
    for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
      const i=y*width+x;
      if(!painted && !atlas.data[i*4+3]) continue;
      if(painted) atlas.data[i*4+3]=255;
      let px=x,py=y,distance=0;
      if(!painted) for(let step=0;step<900 && py<baseY;step++) {
        const vx=sample(flowX,px,py),vy=sample(flowY,px,py);
        px-=vx*1.1;py-=vy*1.1;distance+=1.1;
      }
      if(!painted && py<baseY) unfinished++;
      chartX[i]=px;chartY[i]=distance;
      // 沿同一流线反查底部纤维标签与累计长度，不平均主干和子枝UV。
      const sx=painted ? (x+.5)/width*source.width-.5 : ((px*5)%source.width+source.width)%source.width;
      const sy=painted ? (y+.5)/height*source.height-.5 : ((distance*3)%source.height+source.height)%source.height;
      const ix=Math.floor(sx),iy=Math.floor(sy),tx=sx-ix,ty=sy-iy;
      for(let c=0;c<3;c++) {
        let value=0;
        for(let row=0;row<2;row++) for(let col=0;col<2;col++) value+=pixels.data[
          ((((iy+row+source.height)%source.height)*source.width+(ix+col+source.width)%source.width)*4+c)]*(col?tx:1-tx)*(row?ty:1-ty);
        atlas.data[i*4+c]=value;
      }
      covered++;
    }
    if(unfinished) throw Error(`材质流线未抵达基部：${unfinished}`);
    if(!chartX.every(Number.isFinite)||!chartY.every(Number.isFinite)) throw Error('材质坐标非有限');
    const lighting=new Float32Array(count).fill(1);
    if(painted) for(const face of faces) {
      const [a,b,c]=face.map(i=>uv[i]);
      const area=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
      const shade=face.map(i=>.72+.28*Math.max(0,Math.min(1,-normals[i*3]*.5-normals[i*3+1]*.8+normals[i*3+2]*.3)));
      for(let y=Math.max(0,Math.floor(Math.min(a[1],b[1],c[1])));y<=Math.min(height-1,Math.ceil(Math.max(a[1],b[1],c[1])));y++) {
        for(let x=Math.max(0,Math.floor(Math.min(a[0],b[0],c[0])));x<=Math.min(width-1,Math.ceil(Math.max(a[0],b[0],c[0])));x++) {
          const u=((b[0]-x-.5)*(c[1]-y-.5)-(b[1]-y-.5)*(c[0]-x-.5))/area;
          const v=((c[0]-x-.5)*(a[1]-y-.5)-(c[1]-y-.5)*(a[0]-x-.5))/area,w=1-u-v;
          if(Math.min(u,v,w)<-1e-10) continue;
          lighting[y*width+x]=u*shade[0]+v*shade[1]+w*shade[2];
        }
      }
    }
    for(let i=0;i<count;i++) for(let c=0;c<3;c++) atlas.data[i*4+c]*=lighting[i];
    const textureCanvas=document.createElement('canvas');textureCanvas.width=width;textureCanvas.height=height;
    textureCanvas.getContext('2d').putImageData(atlas,0,0);
    window.barkAtlasURL=textureCanvas.toDataURL('image/png');
    window.barkChart={uv,faces};
    let sourceEmptySamples=0;
    for(const face of faces) for(const weights of [[1/3,1/3,1/3],[.8,.1,.1],[.1,.8,.1],[.1,.1,.8]]) {
      const [x,y]=[0,1].map(axis=>face.reduce((sum,index,k)=>sum+uv[index][axis]*weights[k],0));
      if(x<0 || y<0 || x>=width || y>=height) throw Error('图集坐标越界');
      if(atlas.data[(Math.floor(y)*width+Math.floor(x))*4+3]!==255) sourceEmptySamples++;
    }
    if(painted && sourceEmptySamples) throw Error('共享图集实体采样含透明区');
    const original=new Uint8ClampedArray(atlas.data);
    window.renderTransported=(age,near=false)=>{
      let segment=0;
      while(segment<ages.length-2 && age>ages[segment+1]) segment++;
      const t=(age-ages[segment])/(ages[segment+1]-ages[segment]);
      const positions=Array.from({length:uv.length},(_,i)=>{
        const x=poses[segment][i*3]*(1-t)+poses[segment+1][i*3]*t;
        const z=poses[segment][i*3+2]*(1-t)+poses[segment+1][i*3+2]*t;
        return near ? [280+(x-1)*160,350-(z-3.2)*160] : [170+x*95,660-z*90];
      });
      const image=ctx.createImageData(560,700),detail=.07+.93*age;
      for(let i=0;i<atlas.data.length;i+=4) for(let c=0;c<3;c++) atlas.data[i+c]=[112,95,65][c]*lighting[i/4]*(1-detail)+original[i+c]*detail;
      let minimumArea=Infinity;
      for(const face of faces) {
        const area=points=>(points[1][0]-points[0][0])*(points[2][1]-points[0][1])-(points[2][0]-points[0][0])*(points[1][1]-points[0][1]);
        const current=face.map(i=>positions[i]),source=face.map(i=>uv[i]);
        if(area(current)*area(source)<=0) throw Error('材质验证网格翻面');
        minimumArea=Math.min(minimumArea,Math.abs(area(current)));
        window.rasterTexturedTriangle(image,atlas,current,source);
      }
      ctx.putImageData(image,0,0);ctx.globalCompositeOperation='destination-over';
      ctx.fillStyle='#f6efdf';ctx.fillRect(0,0,560,700);ctx.globalCompositeOperation='source-over';
      ctx.fillStyle='rgba(246,239,223,.94)';ctx.fillRect(0,0,560,42);
      ctx.fillStyle='#493824';ctx.font='16px Microsoft YaHei';ctx.fillText(`${hierarchical ? '局部两级分叉' : '局部分叉'} · 树龄 ${age.toFixed(2)}`,20,30);
      return {age,minimumArea,triangles:faces.length};
    };
    return {covered,unfinished,sourceEmptySamples,sourceSize:[source.width,source.height],atlasSize:[width,height],vertices:uv.length,triangles:faces.length,
      fixedUV:true,sourceOpaque:true,scope:'共享局部分叉材质；不含根冠枝牌，不是完整A2样件'};
  },{poses:metadata.vertexPoseSections.map(values),faces,normals:values('normals'),ages:metadata.poseFrames.map(p=>p.age),photo:`data:image/png;base64,${source.toString('base64')}`,painted,hierarchical});
  const checks=[];
  for(const [name,age,near=false] of [['young',0],['middle',.5],['mature',1],['close',1,true]]) {
    checks.push(await page.evaluate(([age,near])=>window.renderTransported(age,near),[age,near]));
    await page.screenshot({path:`${output}/${name}.png`});
  }
  const frames=[],intervals=[];
  for(let frame=0;frame<=40;frame++) {
    intervals.push(await page.evaluate(age=>window.renderTransported(age),frame/40));
    frames.push(await page.screenshot({type:'jpeg',quality:90}));
  }
  const encode=spawnSync(resolve(process.env.LOCALAPPDATA,'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe'),
    ['-y','-f','image2pipe','-r','8','-c:v','mjpeg','-i','pipe:0','-c:v','libvpx','-pix_fmt','yuv420p',resolve(output,'deformation.webm')],
    {input:Buffer.concat(frames),encoding:'utf8'});
  if(encode.status!==0) throw Error(encode.error?.message??encode.stderr);
  await writeFile(`${output}/atlas.png`,Buffer.from((await page.evaluate(()=>window.barkAtlasURL)).split(',')[1],'base64'));
  await writeFile(`${output}/chart.json`,JSON.stringify(await page.evaluate(()=>window.barkChart)));
  await writeFile(`${output}/mesh.bin`,binary);
  await writeFile(`${output}/mesh.json`,JSON.stringify(metadata));
  const hash=data=>createHash('sha256').update(data).digest('hex');
  await writeFile(`${output}/result.json`,JSON.stringify({bake,checks,frames:intervals.length,
    minimumSampledArea:Math.min(...intervals.map(x=>x.minimumArea)),meshSha256:hash(binary),sourcePath,sourceSha256:hash(source)},null,2));
}finally{await browser.close();}
