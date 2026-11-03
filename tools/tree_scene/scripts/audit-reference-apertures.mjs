import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {PNG} from 'pngjs';

// 从真实子网格的UV/姿态反解纸面轮廓，与源PNG独立比较，不读取生成器的纸面坐标。
const directory=resolve(process.argv[2]??'build/qa/reference-crown-round2-proof');
const meta=JSON.parse(await readFile(resolve(directory,'mesh.json'),'utf8'));
const result=JSON.parse(await readFile(resolve(directory,'result.json'),'utf8'));
const bytes=await readFile(resolve(directory,'mesh.bin'));
const png=PNG.sync.read(await readFile(result.sourceImages[2].path));
function section(name){const s=meta.sections[name];return Array.from({length:s.length},(_,i)=>bytes.readFloatLE(s.offset+i*4));}
const pose=section(meta.vertexPoseSections[2]),corners=section('corners'),checks=[];
function inside(x,y,polygon){let value=false;for(let i=0,j=polygon.length-1;i<polygon.length;j=i++){
  const a=polygon[i],b=polygon[j];
  if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])value=!value;
}return value;}
for(const [index,plaque] of meta.plaques.entries()){
  const part=result.parts.find(p=>p.name===(index===0?'左章牌':'右节牌'));
  let basis;
  for(let i=0;i<corners.length;i+=9){
    const ids=[0,3,6].map(k=>Math.round(corners[i+k]));
    if(ids.some(v=>v<part.vertexRange[0]||v>=part.vertexRange[1]))continue;
    const world=ids.map(v=>[pose[v*3],pose[v*3+2]]);
    const d=(world[1][0]-world[0][0])*(world[2][1]-world[0][1])-(world[2][0]-world[0][0])*(world[1][1]-world[0][1]);
    if(Math.abs(d)>1e-9){basis={world,d,uv:[0,3,6].map(k=>[corners[i+k+1]*png.width,(1-corners[i+k+2])*png.height])};break;}
  }
  if(!basis)throw Error('木框没有可反解三角');
  function source(p){const {world:w,d,uv}=basis,dx=p[0]-w[0][0],dy=p[2]-w[0][1];
    const u=(dx*(w[2][1]-w[0][1])-(w[2][0]-w[0][0])*dy)/d;
    const v=((w[1][0]-w[0][0])*dy-dx*(w[1][1]-w[0][1]))/d;
    return [0,1].map(k=>uv[0][k]+u*(uv[1][k]-uv[0][k])+v*(uv[2][k]-uv[0][k]));
  }
  const nodes=plaque.corners.map(i=>meta.poseFrames[2].nodes[i]);
  const center=[0,1,2].map(k=>nodes.reduce((s,p)=>s+p[k]/4,0));
  const paper=nodes.map(p=>p.map((v,k)=>center[k]+(v-center[k])*(plaque.inset??.79)));
  const polygon=plaque.aperture.map(([u,v])=>source([0,1,2].map(k=>
    (paper[0][k]*(1-u)+paper[1][k]*u)*(1-v)+(paper[3][k]*(1-u)+paper[2][k]*u)*v)));
  const minX=Math.floor(Math.min(...polygon.map(p=>p[0]))),maxX=Math.ceil(Math.max(...polygon.map(p=>p[0])));
  const minY=Math.floor(Math.min(...polygon.map(p=>p[1]))),maxY=Math.ceil(Math.max(...polygon.map(p=>p[1])));
  let checked=0,woodCovered=0,holeMissed=0;
  const alpha=(x,y)=>png.data[(y*png.width+x)*4+3];
  // 距离边缘2像素以上才判错，避免把抗锯齿/逐行折线边界当作整块空窗错位。
  for(let y=minY+3;y<maxY-3;y+=3)for(let x=minX+3;x<maxX-3;x+=3){
    const neighborhood=[[-2,0],[2,0],[0,-2],[0,2],[0,0]].map(([dx,dy])=>alpha(x+dx,y+dy)>=128);
    const inPaper=inside(x+.5,y+.5,polygon);checked++;
    if(inPaper&&neighborhood.every(Boolean))woodCovered++;
    if(!inPaper&&neighborhood.every(v=>!v))holeMissed++;
  }
  const check={title:plaque.title,outlinePoints:polygon.length,checked,woodCovered,holeMissed};checks.push(check);
  if(woodCovered||holeMissed)throw Error(`纸面与实际空窗不符：${JSON.stringify(check)}`);
}
await writeFile(resolve(directory,'aperture-audit.json'),JSON.stringify({checks,
  scope:'成熟姿态实际子网格UV反解，3像素间隔采样，2像素边界容差；展开中间帧另看实际短片，不证明整体视觉通过'},null,2)+'\n');
console.log(JSON.stringify(checks));
