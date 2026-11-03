import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 从实际消费的二进制UV和顶点重建连接，不把源脚本的共点声明当验证结果。
const proof=resolve(process.argv[2]??'build/qa/cage-whole-round2-proof');
const [metaBytes,bytes,sourceBytes]=await Promise.all(['mesh.json','mesh.bin','result.json'].map(n=>readFile(resolve(proof,n))));
const meta=JSON.parse(metaBytes),source=JSON.parse(sourceBytes);
const images=await Promise.all(source.sourceImages.map(async p=>PNG.sync.read(await readFile(resolve(p.path)))));
function section(name){const s=meta.sections[name];return Array.from({length:s.length},(_,i)=>bytes.readFloatLE(s.offset+i*4));}
const corners=section('corners'),poses=meta.vertexPoseSections.map(section),items=[];
const coreUV=new Map();
for(let i=0;i<corners.length;i+=9)if(meta.triangleTextures[i/9]===0)
  for(const k of [0,3,6])coreUV.set(Math.round(corners[i+k]),[corners[i+k+1],corners[i+k+2]]);
function weights(p,a,b,c){
  const d=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);
  if(Math.abs(d)<1e-15)return null;
  const u=((b[1]-c[1])*(p[0]-c[0])+(c[0]-b[0])*(p[1]-c[1]))/d;
  const v=((c[1]-a[1])*(p[0]-c[0])+(a[0]-c[0])*(p[1]-c[1]))/d;
  return [u,v,1-u-v];
}
for(const part of source.parts){
  const image=images[part.material],[x,y]=part.childBaseSource,[mx,my]=part.anchorSource;
  const childAlpha=image.data[(Math.round(y)*image.width+Math.round(x))*4+3];
  const motherAlpha=images[0].data[(Math.round(my)*images[0].width+Math.round(mx))*4+3];
  if(childAlpha<128||motherAlpha<128)throw Error(`实体端口失败：${part.name} 母体${motherAlpha} 子件${childAlpha}`);
  const p=[x/image.width,1-y/image.height];let child;
  for(let i=0;i<corners.length;i+=9){
    if(meta.triangleTextures[i/9]!==part.material)continue;
    const ids=[0,3,6].map(k=>Math.round(corners[i+k]));
    if(ids.some(v=>v<part.vertexRange[0]||v>=part.vertexRange[1]))continue;
    const uv=[0,3,6].map(k=>[corners[i+k+1],corners[i+k+2]]);
    const w=weights(p,...uv);
    if(w&&Math.min(...w)>=-1e-6){child={ids,weights:w};break;}
  }
  if(!child)throw Error(`子件端口不在其实际网格内：${part.name}`);
  const motherUV=part.coreTriangle.map(i=>coreUV.get(i));
  if(motherUV.some(p=>!p))throw Error(`母体三角不在木体网格内：${part.name}`);
  const parentWeights=weights([mx/images[0].width,1-my/images[0].height],...motherUV);
  if(!parentWeights||Math.min(...parentWeights)<-1e-6||
      parentWeights.some((v,i)=>Math.abs(v-part.weights[i])>1e-5))
    throw Error(`母体权重无效：${part.name}`);
  const errors=poses.map(pose=>{
    const parent=[0,2].map(axis=>part.coreTriangle.reduce((sum,v,k)=>sum+pose[v*3+axis]*parentWeights[k],0));
    const current=[0,2].map(axis=>child.ids.reduce((sum,v,k)=>sum+pose[v*3+axis]*child.weights[k],0));
    return Math.hypot(parent[0]-current[0],parent[1]-current[1]);
  });
  const maxError=Math.max(...errors);
  if(maxError>1e-5)throw Error(`实际网格连接偏移：${part.name} ${maxError}`);
  items.push({name:part.name,motherAlpha,childAlpha,keyframeProjectedErrors:errors,maxProjectedError:maxError});
}
const hash=b=>createHash('sha256').update(b).digest('hex');
const report={success:true,meshSha256:hash(bytes),metadataSha256:hash(metaBytes),items,
  maxProjectedError:Math.max(...items.map(p=>p.maxProjectedError)),
  scope:'源像素实体性及实际UV三角中基点的X-Z投影；三姿态间差值线性，范数不超过端点最大值。Y深度有意分层，不证明木纹、遮挡和整体视觉自然，也不证明正式页面或点击。'};
await writeFile(resolve(proof,'attachment-audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({success:true,parts:items.length,maxProjectedError:report.maxProjectedError}));
