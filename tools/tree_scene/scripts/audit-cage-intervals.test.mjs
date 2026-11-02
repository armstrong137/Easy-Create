import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

async function fixture(name,last){
  const path=resolve('build/qa/cage-audit-tests',name);await mkdir(path,{recursive:true});
  const values=[0,0,0,1,1,0,2,0,1, 0,0,0,1,0,0,0,0,1, ...last];
  const bytes=Buffer.alloc(values.length*4);values.forEach((v,i)=>bytes.writeFloatLE(v,i*4));
  await writeFile(resolve(path,'mesh.bin'),bytes);
  await writeFile(resolve(path,'mesh.json'),JSON.stringify({
    sections:{corners:{offset:0,length:9},positions0:{offset:36,length:9},positions1:{offset:72,length:9}},
    vertexPoseSections:['positions0','positions1'],poseFrames:[{age:0},{age:1}],
    camera:{target:[0,0,0],right:[1,0,0],up:[0,0,1]},
  }));
  const run=spawnSync(process.execPath,['tools/tree_scene/scripts/audit-cage-intervals.mjs',path],{encoding:'utf8'});
  return {status:run.status,report:JSON.parse(await readFile(resolve(path,'interval-audit.json'),'utf8'))};
}

test('有向面积全程保持正值的局部三角通过',async()=>{
  const {status,report}=await fixture('positive',[0,0,0,2,0,0,0,0,1.5]);
  assert.equal(status,0);assert.equal(report.success,true);
  assert(report.intervals[0].minimumAreaAfterRoundingBound>0);
});

test('两端面积均为正但中间翻折的三角必须拒绝',async()=>{
  // 起终面积均为1，中间t=.5的有向面积式为-.125；端点检查会漏掉它。
  const {status,report}=await fixture('interior-fold',[0,0,0,-2,0,0,0,0,-.5]);
  assert.equal(status,1);assert.equal(report.success,false);
  assert.equal(report.intervals[0].unsafeTriangles,1);
  assert(Math.abs(report.intervals[0].minimumSignedArea+.125)<1e-10);
});
