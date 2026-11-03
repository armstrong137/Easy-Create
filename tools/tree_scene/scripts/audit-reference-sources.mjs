import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';

// 只读核对源图与实际连通区；不改PNG，不代表运行时视觉通过。
const sources=[];
for(const name of ['wood','canopy','frames']){
  const file=`assets/source/magic_tree/textures_source/reference_${name}_v1.png`;
  const bytes=await readFile(file),png=PNG.sync.read(bytes);
  const analysis=JSON.parse(await readFile(`build/qa/reference-${name}-analysis/components.json`,'utf8'));
  const sha256=createHash('sha256').update(bytes).digest('hex');
  if(analysis.sha256!==sha256)throw Error(`${name}连通分析已过期`);
  const major=analysis.components.filter(p=>p.pixels>100);
  if(major.length!==({wood:1,canopy:9,frames:2})[name])throw Error(`${name}主构件数量不符`);
  const item={name,file,bytes:bytes.length,sha256,width:png.width,height:png.height,
    threshold:128,major,minorComponentCount:analysis.components.length-major.length};
  if(name==='frames'){
    // 两个实际空窗的内接阅读矩形，坐标来自本版源图；不宣称整片不规则空窗已逐像素验收。
    item.apertureSamples=[[280,240,140,340],[1370,240,120,340]].map(([x,y,width,height])=>{
      let maxAlpha=0,nonzero=0;
      for(let yy=y;yy<y+height;yy++)for(let xx=x;xx<x+width;xx++){
        const alpha=png.data[(yy*png.width+xx)*4+3];maxAlpha=Math.max(maxAlpha,alpha);if(alpha)nonzero++;
      }
      return {rectangle:[x,y,width,height],pixels:width*height,maxAlpha,nonzero};
    });
    item.exactTransparentApertures=item.apertureSamples.every(p=>p.nonzero===0);
    // 如实保留残留像素，不能把“肉眼不可见”改记为完全透明通过。
    item.apertureStatus=item.exactTransparentApertures?'检查矩形全透明':'仍有低alpha残留，源稿未达到完全透明要求';
  }
  sources.push(item);
}
const report={scope:'源资产预制作核对，非整树候选或A2通过',sources,
  limitations:['冠簇不严格等分，必须按实际连通区选UV，不能九宫格裁切',
    '少量脱离主连通区的边缘像素尚未规划UV归属',
    '木体幼态材质、根尖、真实端口、完整冠层遮挡及连续成长尚未验证']};
const output=resolve('docs/Reports/Codex/参考主导统一源资产');
await mkdir(output,{recursive:true});
await writeFile(resolve(output,'sources.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
