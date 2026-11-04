import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 从实际三角索引/UV/姿态验证多级共边和透明构件基点；不把生成器共点声明当结果。
const directory=resolve(process.argv[2]??'build/qa/development-tree-proof');
const metaBytes=await readFile(resolve(directory,'mesh.json')),meta=JSON.parse(metaBytes);
const source=JSON.parse(await readFile(resolve(directory,'result.json'),'utf8'));
const bytes=await readFile(resolve(directory,'mesh.bin'));
const hash=b=>createHash('sha256').update(b).digest('hex');
function section(name){const s=meta.sections[name];return Array.from({length:s.length},(_,i)=>bytes.readFloatLE(s.offset+i*4));}
const poses=meta.vertexPoseSections.map(section),corners=section('corners');
const primaryRises=[];
for(const part of source.woodParts.filter(p=>/^(下|中|上)(左|右)$/.test(p.name))){
  // 当前原生表皮每圈九点，末圈中点由实际顶点范围定位。
  const mature=poses.at(-1),tip=part.vertexRange[1]-5;
  const baseHeight=part.boundary.reduce((sum,v)=>sum+mature[v*3+2]/part.boundary.length,0);
  const rise=mature[tip*3+2]-baseHeight;
  if(rise<=0)throw Error(`主枝上扬方向错误：${part.name} 高差${rise}`);
  primaryRises.push({name:part.name,rise});
}
const images=await Promise.all(source.sourceImages.map(async item=>{
  const b=await readFile(item.path);if(hash(b)!==item.sha256)throw Error('源PNG哈希不符');return PNG.sync.read(b);
}));
for(let i=3;i<images[0].data.length;i+=4)if(images[0].data[i]!==255)throw Error('后置明暗材质不是全不透明');
if(meta.unlitVertexStart!==source.woodVertexCount||JSON.stringify(meta.postTextureLightingMaterials)!=='[0]')throw Error('不透明表皮与透明图集的明暗边界不符');
const owners=new Int32Array(source.woodVertexCount),edges=new Map(),used=new Set(),adjacency=new Map();
source.woodParts.forEach((p,index)=>{for(let i=p.vertexRange[0];i<p.vertexRange[1];i++)owners[i]=index;});
let woodTriangles=0,minimumUvArea=Infinity;
for(let i=0;i<corners.length;i+=9){
  const ids=[0,3,6].map(k=>Math.round(corners[i+k]));
  if(meta.triangleTextures[i/9]!==0)continue;
  if(ids.some(v=>v>=source.woodVertexCount))throw Error('原生木体三角包含图集构件顶点');
  woodTriangles++;const owner=Math.max(...ids.map(v=>owners[v]));
  const uv=[0,3,6].map(k=>[corners[i+k+1],corners[i+k+2]]);
  minimumUvArea=Math.min(minimumUvArea,Math.abs((uv[1][0]-uv[0][0])*(uv[2][1]-uv[0][1])-(uv[2][0]-uv[0][0])*(uv[1][1]-uv[0][1])));
  for(let k=0;k<3;k++){
    const a=ids[k],b=ids[(k+1)%3],key=[Math.min(a,b),Math.max(a,b)].join(':');
    const item=edges.get(key)??{owners:[],direction:0};item.owners.push(owner);item.direction+=a<b?1:-1;edges.set(key,item);
    for(const [from,to] of [[a,b],[b,a]]){used.add(from);if(!adjacency.has(from))adjacency.set(from,new Set());adjacency.get(from).add(to);}
  }
}
const junctions=[];
for(let i=1;i<source.woodParts.length;i++){
  const part=source.woodParts[i],parent=source.woodParts.findIndex(p=>p.name===part.parent);
  const actual=[...edges.entries()].filter(([,v])=>v.owners.includes(i)&&v.owners.includes(parent)).map(([k])=>k).sort();
  const expected=part.boundary.slice(1).map((v,j)=>[v,part.boundary[j]].sort((a,b)=>a-b).join(':')).sort();
  if(actual.length!==8||JSON.stringify(actual)!==JSON.stringify(expected))throw Error(`实际共享边不符：${part.name}`);
  junctions.push({name:part.name,parent:part.parent,sharedEdges:actual.length});
}
for(const edge of edges.values())if(edge.owners.length>2||(edge.owners.length===2&&edge.direction!==0))throw Error('非流形边或母子面朝向不一致');
const visited=new Set(),queue=[0];while(queue.length){const v=queue.pop();if(visited.has(v))continue;visited.add(v);queue.push(...adjacency.get(v));}
if(visited.size!==source.woodVertexCount||used.size-edges.size+woodTriangles!==1)throw Error('原生前表面未完整连通或有孔');
if(minimumUvArea<=1e-12)throw Error('原生木质UV退化');
function weights(p,a,b,c){const d=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);if(Math.abs(d)<1e-15)return null;
  const u=((b[1]-c[1])*(p[0]-c[0])+(c[0]-b[0])*(p[1]-c[1]))/d,v=((c[1]-a[1])*(p[0]-c[0])+(a[0]-c[0])*(p[1]-c[1]))/d;return [u,v,1-u-v];}
const attachments=[];
for(const part of source.patches){
  const image=images[part.material],[x,y]=part.baseSource;
  const alpha=image.data[(y*image.width+x)*4+3];if(alpha<128)throw Error(`子素材基点不是实体：${part.name}`);
  if(part.anchorVertex>=source.woodVertexCount)throw Error('构件没有真实原生母体');
  const target=[x/image.width,1-y/image.height];let found;
  for(let i=0;i<corners.length;i+=9){
    const ids=[0,3,6].map(k=>Math.round(corners[i+k]));
    if(ids.some(v=>v<part.vertexRange[0]||v>=part.vertexRange[1]))continue;
    const w=weights(target,...[0,3,6].map(k=>[corners[i+k+1],corners[i+k+2]]));
    if(w&&Math.min(...w)>=-1e-6){found={ids,w};break;}
  }
  if(!found)throw Error('构件基点不在其实际UV三角内');
  const errors=poses.map(p=>Math.hypot(...[0,2].map(axis=>found.ids.reduce((sum,v,k)=>sum+p[v*3+axis]*found.w[k],0)-p[part.anchorVertex*3+axis])));
  if(Math.max(...errors)>1e-5)throw Error('母子实际投影接合偏移');
  attachments.push({name:part.name,alpha,anchorVertex:part.anchorVertex,maxProjectedError:Math.max(...errors)});
}
const report={success:true,meshSha256:hash(bytes),metadataSha256:hash(metaBytes),woodVertices:visited.size,woodTriangles,junctions,attachments,primaryRises,
  minimumWoodUvDoubleAreaTexels:minimumUvArea*images[0].width*images[0].height,
  scope:'实际多级开放前表面共边/连通及图集构件基点的X-Z投影；姿态间差值线性，范数不超过端点最大值。不是闭合三维焊接、自然造型或正式业务验收'};
await writeFile(resolve(directory,'development-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({success:true,junctions:junctions.length,attachments:attachments.length,maxProjectedError:Math.max(...attachments.map(p=>p.maxProjectedError))}));
