import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 只标记透明图中的独立构件，给网格生成器选择对应区域；不修改源图像素。
const source=resolve('assets/source/magic_tree/textures_source/illustrated_components_v1.png');
const output=resolve('build/qa/illustrated-components-analysis');
await mkdir(output,{recursive:true});
const bytes=await readFile(source),image=PNG.sync.read(bytes),{width,height,data}=image;
const labels=new Uint32Array(width*height),queue=new Int32Array(width*height),components=[];
let id=0;
for(let first=0;first<labels.length;first++){
  if(labels[first]||data[first*4+3]<128)continue;
  id++;let head=0,tail=1,minX=width,maxX=0,minY=height,maxY=0;
  queue[0]=first;labels[first]=id;
  while(head<tail){
    const pixel=queue[head++],x=pixel%width,y=Math.floor(pixel/width);
    minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
    for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){
      const xx=x+dx,yy=y+dy;
      if(xx<0||xx>=width||yy<0||yy>=height)continue;
      const next=yy*width+xx;
      if(!labels[next]&&data[next*4+3]>=128){labels[next]=id;queue[tail++]=next;}
    }
  }
  components.push({id,pixels:tail,bounds:[minX,minY,maxX,maxY]});
}
components.sort((a,b)=>b.pixels-a.pixels);
const report={source,sha256:createHash('sha256').update(bytes).digest('hex'),width,height,
  threshold:128,components,note:'实际连通区域，不假定生成图严格符合六等分网格；标签用于网格UV选区，不改变PNG。'};
await writeFile(resolve(output,'labels.bin'),new Uint8Array(labels.buffer));
await writeFile(resolve(output,'components.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
