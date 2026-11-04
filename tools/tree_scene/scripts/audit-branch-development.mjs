import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 从实际二进制检查母子共用边界及沿枝UV；不把生成器声明的共点当作证据。
const directory=resolve(process.argv[2]??'build/qa/branch-development-proof');
const metaBytes=await readFile(resolve(directory,'mesh.json')),meta=JSON.parse(metaBytes);
const result=JSON.parse(await readFile(resolve(directory,'result.json'),'utf8'));
const bytes=await readFile(resolve(directory,'mesh.bin'));
const info=meta.sections.corners;
const corners=Array.from({length:info.length},(_,i)=>bytes.readFloatLE(info.offset+i*4));
const edges=new Map(),adjacency=new Map(),used=new Set();let minimumUvArea=Infinity;
for(let i=0;i<corners.length;i+=9){
  const ids=[0,3,6].map(k=>Math.round(corners[i+k]));
  const child=ids.some(v=>v>=result.branchStart);
  const uv=[0,3,6].map(k=>[corners[i+k+1],corners[i+k+2]]);
  const area=Math.abs((uv[1][0]-uv[0][0])*(uv[2][1]-uv[0][1])-(uv[2][0]-uv[0][0])*(uv[1][1]-uv[0][1]));
  minimumUvArea=Math.min(minimumUvArea,area);
  for(let k=0;k<3;k++){
    const a=ids[k],b=ids[(k+1)%3],key=[Math.min(a,b),Math.max(a,b)].join(':');
    const edge=edges.get(key)??{vertices:[a,b],parent:0,child:0,direction:0};
    edge[child?'child':'parent']++;edge.direction+=a<b?1:-1;edges.set(key,edge);
    for(const [from,to] of [[a,b],[b,a]]){used.add(from);if(!adjacency.has(from))adjacency.set(from,new Set());adjacency.get(from).add(to);}
  }
}
const shared=[...edges.entries()].filter(([,e])=>e.parent&&e.child);
const boundaries=[result.sharedBoundary,...(result.rootBoundaries??[])];
const expected=boundaries.flatMap(boundary=>boundary.slice(1)
  .map((v,i)=>[boundary[i],v].sort((a,b)=>a-b).join(':'))).sort();
if(JSON.stringify(shared.map(([key])=>key).sort())!==JSON.stringify(expected))throw Error('实际母子共享边界与预期接头不符');
for(const edge of edges.values())if(edge.parent+edge.child>2||
    (edge.parent+edge.child===2&&edge.direction!==0))throw Error('重复面、非流形边或朝向不一致');
const visited=new Set(),queue=[used.values().next().value];
while(queue.length){const v=queue.pop();if(visited.has(v))continue;visited.add(v);queue.push(...adjacency.get(v));}
if(visited.size!==meta.vertexCount)throw Error('局部表面未完整连通或含未使用顶点');
if(meta.vertexCount-edges.size+meta.triangleCount!==1)throw Error('局部开表面不满足无孔圆盘拓扑');
if(minimumUvArea<=1e-12)throw Error('存在退化UV三角');
const image=PNG.sync.read(await readFile(resolve(directory,'baked-bark.png')));
const hash=b=>createHash('sha256').update(b).digest('hex');
const report={success:true,meshSha256:hash(bytes),metadataSha256:hash(metaBytes),
  vertices:visited.size,sharedEdges:shared.length,sharedVertices:result.sharedBoundary,
  ...(result.rootBoundaries?{rootBoundaries:result.rootBoundaries}:{}),
  minimumUvDoubleAreaTexels:minimumUvArea*image.width*image.height,
  scope:'单个开放前表面的连通性、母子共用索引及UV非退化；不是闭合三维实体，UV分缝不保证材质无缝，不证明自然造型或整树通过'};
await writeFile(resolve(directory,'development-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
