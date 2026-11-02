import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 只读检查实际导出的UV像素面积；不修改资产，不以坐标通过代替美术验收。
const folder=resolve(process.argv[2]??'build/qa/whole-tree-mesh-round2');
const metaBytes=await readFile(resolve(folder,'mesh.json'));
const meta=JSON.parse(metaBytes),binary=await readFile(resolve(folder,'mesh.bin'));
const atlasBytes=await readFile(resolve(folder,'baked-bark.png'));
const atlas=PNG.sync.read(atlasBytes),section=meta.sections.corners;
const data=Array.from({length:section.length},(_,i)=>binary.readFloatLE(section.offset+i*4));
const areas=[];
for(let i=0;i<data.length;i+=9){
  const u=data[i+1],v=data[i+2],du=data[i+4]-u,dv=data[i+5]-v;
  areas.push(Math.abs(du*(data[i+8]-v)-dv*(data[i+7]-u))*atlas.width*atlas.height/2);
}
areas.sort((a,b)=>a-b);
const countBelow=limit=>areas.filter(area=>area<limit).length;
const quantile=q=>areas[Math.floor((areas.length-1)*q)];
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const report={
  source:folder,meshSha256:hash(binary),metadataSha256:hash(metaBytes),atlasSha256:hash(atlasBytes),
  atlasWidth:atlas.width,atlasHeight:atlas.height,triangles:areas.length,
  textureMode:meta.repeatTexture?'重复采样材质；UV可超出0至1':'固定图集',
  uvAreaTexels:{p10:quantile(.1),median:quantile(.5),p90:quantile(.9),
    below1:countBelow(1),below4:countBelow(4),below16:countBelow(16)},
  sumTriangleUvAreaFraction:areas.reduce((sum,area)=>sum+area,0)/(atlas.width*atlas.height),
  scope:'实际三角形UV面积，不含图表边距；总和不等于去重覆盖率，也不证明图表不重叠或黑片的唯一原因。',
  visualAcceptance:'UV像素面积不证明视觉验收，需检查对应实图与验证范围。',
};
await writeFile(resolve(folder,'uv-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
