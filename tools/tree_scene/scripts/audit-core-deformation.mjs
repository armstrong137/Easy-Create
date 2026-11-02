import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

// 只读诊断平面骨骼候选的全三角翻面；不修改PNG、网格或姿态。
const proof=resolve(process.argv[2]??'build/qa/continuous-core-round2-proof');
const metaBytes=await readFile(resolve(proof,'mesh.json'));
const meta=JSON.parse(metaBytes),bytes=await readFile(resolve(proof,'mesh.bin'));
function section(name){
  const {offset,length}=meta.sections[name];
  return Array.from({length},(_,i)=>bytes.readFloatLE(offset+i*4));
}
const bindings=section('bindings'),corners=section('corners');
const frames=meta.poseFrames,nodes=meta.nodes,edges=meta.edges;
if([...nodes,...frames.flatMap(f=>f.nodes)].some(p=>Math.abs(p[1])>1e-7))
  throw Error('本审计仅适用于X-Z平面骨架，不用平面近似审计空间骨架');
const hash=data=>createHash('sha256').update(data).digest('hex');
const states=[];
for(const age of [0,.25,.5,.75,1]){
  const [first,last]=age<=.5?[frames[0],frames[1]]:[frames[1],frames[2]];
  let t=(age-first.age)/(last.age-first.age);t=t*t*(3-2*t);
  const grown=first.nodes.map((p,i)=>p.map((v,j)=>v+(last.nodes[i][j]-v)*t));
  const radial=first.radial.map((v,i)=>v+(last.radial[i]-v)*t);
  const rotations=edges.map(([a,b])=>{
    const x=nodes[b][0]-nodes[a][0],z=nodes[b][2]-nodes[a][2];
    const xx=grown[b][0]-grown[a][0],zz=grown[b][2]-grown[a][2];
    const length=Math.hypot(x,z)*Math.hypot(xx,zz);
    if(length<1e-12)throw Error('退化骨边不能形成有效旋转');
    return [(x*xx+z*zz)/length,(z*xx-x*zz)/length];
  });
  const positions=[];
  for(let i=0;i<meta.vertexCount;i++){
    const p=[0,0,0];
    for(let slot=0;slot<3;slot++){
      const k=i*18+slot*6,edge=Math.round(bindings[k]),s=bindings[k+1],weight=bindings[k+5];
      const [a,b]=edges[edge],[c,sine]=rotations[edge];
      const ox=bindings[k+2]*radial[edge],oy=bindings[k+3]*radial[edge],oz=bindings[k+4]*radial[edge];
      p[0]+=(grown[a][0]+(grown[b][0]-grown[a][0])*s+c*ox+sine*oz)*weight;
      p[1]+=oy*weight;
      p[2]+=(grown[a][2]+(grown[b][2]-grown[a][2])*s-sine*ox+c*oz)*weight;
    }
    positions.push(p);
  }
  let referenceError=0;
  const samples=meta.samples.filter(s=>s.age===age);
  for(const sample of samples)for(const v of sample.vertices)
    for(let axis=0;axis<3;axis++)referenceError=Math.max(referenceError,Math.abs(positions[v.index][axis]-v.position[axis]));
  if(referenceError>1e-5)throw Error(`审计重建不符合源样本：${referenceError}`);
  const byTexture=Array.from({length:meta.extraTextures.length+1},()=>({triangles:0,flipped:0,collapsed:0}));
  for(let i=0;i<corners.length;i+=9){
    const [a,b,c]=[corners[i],corners[i+3],corners[i+6]].map(v=>positions[Math.round(v)]);
    const area=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0]);
    const group=byTexture[meta.triangleTextures[i/9]];group.triangles++;
    if(area< -1e-12)group.flipped++;else if(Math.abs(area)<=1e-12)group.collapsed++;
  }
  states.push({age,referenceVertices:samples.reduce((sum,s)=>sum+s.vertices.length,0),
    referenceError:samples.length?referenceError:null,byTexture});
}
const report={meshSha256:hash(bytes),metadataSha256:hash(metaBytes),states,
  scope:'全部网格三角的五状态二维有向面积，不等于逐像素或全部连续时刻；透明像素所在三角也计入，负面积是翻面风险，不能直接当可见洞数量',
  productionIntegrated:false};
await writeFile(resolve(proof,'deformation-audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
