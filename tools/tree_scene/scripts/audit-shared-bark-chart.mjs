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
const corners=metadata.sections.corners,edges=new Map();
let minimumUvArea=Infinity;
for(let face=0;face<metadata.triangleCount;face++) {
  const ids=[0,3,6].map(k=>bytes.readFloatLE(corners.offset+(face*9+k)*4));
  if(JSON.stringify(ids)!==JSON.stringify(chart.faces[face])) throw Error('图集与原生面索引不一致');
  const [a,b,c]=ids.map(i=>chart.uv[i]);
  const area=Math.abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]));
  if(area<=0) throw Error('固定UV三角退化');
  minimumUvArea=Math.min(minimumUvArea,area);
  const kind=ids.some(i=>i>=585) ? 'child' : 'parent';
  for(let k=0;k<3;k++) {
    const key=[ids[k],ids[(k+1)%3]].sort((a,b)=>a-b).join(':');
    const groups=edges.get(key) ?? new Set();groups.add(kind);edges.set(key,groups);
  }
}
if(chart.faces.length!==metadata.triangleCount) throw Error('图集面数不一致');
const shared=[...edges.entries()].filter(([,groups])=>groups.size===2).map(([key])=>key).sort();
const expected=Array.from({length:8},(_,i)=>[(20+i)*9+8,(21+i)*9+8].sort((a,b)=>a-b).join(':')).sort();
if(JSON.stringify(shared)!==JSON.stringify(expected)) throw Error('实际母子共享接头不匹配');
const report={atlasSize:[atlas.width,atlas.height],opaquePixels:atlas.width*atlas.height,
  vertices:chart.uv.length,triangles:chart.faces.length,sharedEdges:shared.length,minimumUvArea,
  sourceEmptySamples:0,
  scope:'实际图集全像素不透明、固定UV在界内且非退化、原生面与八条共用接边一致；不证明造型/根冠/整树或全连续几何安全'};
await writeFile(resolve(directory,'atlas-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
