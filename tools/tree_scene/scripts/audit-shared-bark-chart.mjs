import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { PNG } from 'pngjs';

// 独立读取实际图集和原生网格，验证固定材质域未引入空域或断开的接头。
const directory=resolve(process.argv[2] ?? 'build/qa/painted-shared-bark');
const chart=JSON.parse(await readFile(resolve(directory,'chart.json')));
const metadata=JSON.parse(await readFile(resolve(directory,'mesh.json')));
const bytes=await readFile(resolve(directory,'mesh.bin'));
const atlas=PNG.sync.read(await readFile(resolve(directory,'atlas.png')));
for(let i=3;i<atlas.data.length;i+=4) if(atlas.data[i]!==255) throw Error('共享材质图集含非不透明像素');
if(chart.uv.length!==metadata.vertexCount) throw Error('材质坐标数量不匹配');
for(const [x,y] of chart.uv) if(!Number.isFinite(x)||!Number.isFinite(y)||x<0||y<0||x>=atlas.width||y>=atlas.height) throw Error('固定UV越界');
const corners=metadata.sections.corners,edges=new Map(),adjacency=new Map();
const domains=metadata.materialDomains ?? [
  {name:'主干',faceStart:0,faceCount:1024,parent:null,boundary:[]},
  {name:'一级枝',faceStart:1024,faceCount:384,parent:0,boundary:Array.from({length:9},(_,i)=>(20+i)*9+8)},
];
let minimumUvArea=Infinity;
for(let face=0;face<metadata.triangleCount;face++) {
  const ids=[0,3,6].map(k=>bytes.readFloatLE(corners.offset+(face*9+k)*4));
  if(JSON.stringify(ids)!==JSON.stringify(chart.faces[face])) throw Error('图集与原生面索引不一致');
  const [a,b,c]=ids.map(i=>chart.uv[i]);
  const area=Math.abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]));
  if(area<=0) throw Error('固定UV三角退化');
  minimumUvArea=Math.min(minimumUvArea,area);
  const kind=domains.findIndex(d=>face>=d.faceStart && face<d.faceStart+d.faceCount);
  if(kind<0) throw Error('实际面没有材质域归属');
  for(let k=0;k<3;k++) {
    const key=[ids[k],ids[(k+1)%3]].sort((a,b)=>a-b).join(':');
    const edge=edges.get(key) ?? {groups:new Set(),count:0,direction:0};
    edge.groups.add(kind);edge.count++;edge.direction+=ids[k]<ids[(k+1)%3] ? 1 : -1;edges.set(key,edge);
    for(const [a,b] of [[ids[k],ids[(k+1)%3]],[ids[(k+1)%3],ids[k]]]) {
      if(!adjacency.has(a)) adjacency.set(a,new Set());adjacency.get(a).add(b);
    }
  }
}
if(chart.faces.length!==metadata.triangleCount) throw Error('图集面数不一致');
const shared=[...edges.entries()].filter(([,edge])=>edge.groups.size===2).map(([key])=>key).sort();
const expected=new Map();
for(const [index,domain] of domains.entries()) if(domain.parent!==null) for(let i=1;i<domain.boundary.length;i++) {
  const key=[domain.boundary[i-1],domain.boundary[i]].sort((a,b)=>a-b).join(':');
  expected.set(key,[domain.parent,index].sort((a,b)=>a-b));
}
if(JSON.stringify(shared)!==JSON.stringify([...expected.keys()].sort())) throw Error('实际母子共享接头不匹配');
for(const [key,pair] of expected) if(JSON.stringify([...edges.get(key).groups].sort((a,b)=>a-b))!==JSON.stringify(pair)) throw Error('接头连接了错误的父子域');
for(const edge of edges.values()) if(edge.count>2 || (edge.count===2 && edge.direction!==0)) throw Error('存在非流形边或面朝向不一致');
const visited=new Set(),queue=[0];
while(queue.length) {
  const vertex=queue.pop();if(visited.has(vertex)) continue;
  visited.add(vertex);queue.push(...(adjacency.get(vertex) ?? []));
}
if(visited.size!==metadata.vertexCount || metadata.vertexCount-edges.size+metadata.triangleCount!==1) throw Error('木质表面断开或拓扑不符');
const report={atlasSize:[atlas.width,atlas.height],opaquePixels:atlas.width*atlas.height,
  vertices:chart.uv.length,triangles:chart.faces.length,sharedEdges:shared.length,domains:domains.map(d=>d.name),minimumUvArea,
  sourceEmptySamples:0,
  scope:'实际图集全像素不透明、固定UV界内非退化、原生面/父子接边一致及开放木面连通；不证明造型/根冠/整树或全连续几何安全'};
await writeFile(resolve(directory,'atlas-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
