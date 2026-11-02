import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { Readable } from 'node:stream';

// 独立构建与实验资产分别提供；不覆盖build/web，不打开小说数据库。
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const compact=process.argv.includes('--compact');
const tree=process.argv.includes('--tree');
const surface=process.argv.includes('--surface');
const whole=process.argv.includes('--authored-whole');
const fork=process.argv.includes('--fork');
const lap=process.argv.includes('--pair-lap');
const pair=process.argv.includes('--pair')||lap;
const illustratedRound2=process.argv.includes('--illustrated-whole-round2');
const core=process.argv.includes('--continuous-core');
const illustrated=process.argv.includes('--illustrated-whole')||illustratedRound2||core;
const web=resolve(root,'build/volume-web'), proof=resolve(root,core?'build/qa/continuous-core-proof':illustratedRound2?'build/qa/illustrated-whole-round2-proof':illustrated?'build/qa/illustrated-whole-proof':lap?'build/qa/illustrated-pair-lap-proof':pair?'build/qa/illustrated-pair-proof':fork?'build/qa/illustrated-fork-proof':whole?'build/qa/authored-whole-control-round2':surface?'build/qa/authored-surface-proof':tree?'build/qa/whole-tree-mesh-round2':compact?'build/qa/volume-proof-compact':'build/qa/volume-proof-baked');
const output=resolve(root,core?'build/qa/continuous-core-2d':illustratedRound2?'build/qa/illustrated-whole-round2-2d':illustrated?'build/qa/illustrated-whole-2d':lap?'build/qa/illustrated-pair-lap-2d':pair?'build/qa/illustrated-pair-2d':fork?'build/qa/illustrated-fork-2d':whole?'build/qa/authored-whole-2d-round2':surface?'build/qa/authored-surface-2d':tree?'build/qa/whole-tree-2d-round2':compact?'build/qa/volume-2d-compact':'build/qa/volume-2d',new Date().toISOString().replaceAll(':','-'));
await mkdir(output,{recursive:true});
const mime={'.js':'text/javascript','.mjs':'text/javascript','.html':'text/html',
  '.json':'application/json','.wasm':'application/wasm','.png':'image/png','.css':'text/css'};
const server=createServer(async(req,res)=>{
  const path=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  const base=path.startsWith('/proof/')?proof:web;
  const suffix=path.startsWith('/proof/')?path.slice(6):(path==='/'?'/index.html':path);
  const file=resolve(base,'.'+suffix);
  if(relative(base,file).startsWith('..')){res.writeHead(403);res.end();return;}
  try{const data=await readFile(file);res.writeHead(200,{'Content-Type':mime[extname(file)]??'application/octet-stream','Cache-Control':'no-store'});res.end(data);}
  catch{res.writeHead(404);res.end('not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext({viewport:{width:900,height:1280},deviceScaleFactor:1,
  recordVideo:{dir:resolve(output,'video'),size:{width:900,height:1280}}});
const errors=[];
const page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
try{
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(()=>window.volumeProofMetrics,{},{timeout:60000});
  const startup=await page.evaluate(()=>window.volumeProofMetrics);
  if(startup.error)throw Error(startup.error);
  const placeholder=page.locator('flt-semantics-placeholder');
  if(await placeholder.count())await placeholder.evaluate(el=>el.click());
  await page.waitForTimeout(4500);
  const states=[];
  for(const [title,age,name] of [['较细状态',0,'young'],['中间状态',.5,'middle'],['完整片段',1,'mature']]){
    await page.getByRole('button',{name:title,exact:true}).click();
    await page.waitForFunction(age=>window.volumeProofMetrics.age===age,age);
    await page.waitForTimeout(300);
    const metrics=await page.evaluate(()=>window.volumeProofMetrics);
    if(metrics.referenceError>1e-5)throw Error(`跨渲染器形变不一致：${JSON.stringify(metrics)}`);
    states.push(metrics);
    await page.screenshot({path:resolve(output,`${name}.png`)});
  }
  await page.setViewportSize({width:430,height:932});
  await page.waitForTimeout(600);
  await page.screenshot({path:resolve(output,'phone.png')});
  if(tree||surface||whole||fork||pair||illustrated){
    await page.getByRole('button',{name:'枝牌近景',exact:true}).click();
    await page.waitForTimeout(500);
    await page.screenshot({path:resolve(output,surface||fork||pair?'junction-close.png':'plaque-close.png')});
    await page.getByRole('button',{name:'返回全景',exact:true}).click();
  }
  await page.setViewportSize({width:900,height:1280});
  await page.evaluate(()=>{
    window.volumeFrames=[];window.volumeObserved=[];let previous,lastAge;
    const end=performance.now()+12000;
    function sample(now){
      if(previous!==undefined)window.volumeFrames.push(now-previous);previous=now;
      const paint=window.volumeProofPaint, geometry=window.volumeProofMetrics;
      if(paint && paint.age!==lastAge){
        window.volumeObserved.push({...paint,computeMs:geometry.age===paint.age?geometry.computeMs:null});
        lastAge=paint.age;
      }
      if(now<end)requestAnimationFrame(sample);
    }
    requestAnimationFrame(sample);
  });
  await page.getByRole('button',{name:'连续形变',exact:true}).click();
  await page.waitForFunction(()=>window.volumeProofMetrics.age<.1);
  await page.waitForFunction(()=>window.volumeProofMetrics.age===1,{},{timeout:30000});
  await page.waitForTimeout(2200);
  const intervals=await page.evaluate(()=>window.volumeFrames);
  const observed=(await page.evaluate(()=>window.volumeObserved)).filter(frame=>frame.age>0&&frame.age<1);
  function summary(values){
    const sorted=values.filter(value=>typeof value==='number').sort((a,b)=>a-b);
    return {count:sorted.length,p95Ms:sorted[Math.floor(sorted.length*.95)],worstMs:sorted.at(-1)};
  }
  intervals.sort((a,b)=>a-b);
  const result={success:false,states,assetBytes:JSON.parse(await readFile(resolve(proof,'mesh.json'),'utf8')).byteLength,
    frameSample:{count:intervals.length,p95Ms:intervals[Math.floor(intervals.length*.95)],worstMs:intervals.at(-1)},
    cpuGeometry:summary(observed.map(frame=>frame.computeMs)),cpuPaintRecording:summary(observed.map(frame=>frame.recordMs)),
    timingScope:'JS RAF探针不是绘制帧率；Dart指标只含几何/排序和绘图记录CPU，不含GPU完成时间',
    errors,visualAcceptance:'待人工检查，不以坐标校验代替视觉或真机验收'};
  const hash=async path=>createHash('sha256').update(await readFile(path)).digest('hex');
  result.provenance={
    dartSource:await hash(resolve(root,'tools/tree_scene/volume_mesh_preview.dart')),
    mesh:await hash(resolve(proof,'mesh.bin')),metadata:await hash(resolve(proof,'mesh.json')),
    atlas:await hash(resolve(proof,'baked-bark.png')),
    generator:JSON.parse(await readFile(resolve(proof,'result.json'),'utf8')).script_sha256,
    atlasPngBytes:(await readFile(resolve(proof,'baked-bark.png'))).length,
  };
  if(tree||whole){
    result.provenance.wholeSpec=await hash(resolve(root,whole?'tools/tree_scene/rectification/authored_whole_control.py':'tools/tree_scene/rectification/whole_tree_spec.py'));
    const expected=JSON.parse(await readFile(resolve(proof,'mesh.json'),'utf8'));
    if(states[0].plaques!==0||states.at(-1).plaques!==expected.plaques.length||states.at(-1).leaves!==expected.leaves.length)
      throw Error('整树出生或牌面数量与本轮样件规格不一致');
  }
  if(illustrated){
    const expected=JSON.parse(await readFile(resolve(proof,'result.json'),'utf8'));
    result.provenance.extraTextures={};
    const metadata=JSON.parse(await readFile(resolve(proof,'mesh.json'),'utf8'));
    for(const name of metadata.extraTextures??[])result.provenance.extraTextures[name]=await hash(resolve(proof,name));
    if(states[0].plaques!==0||states.at(-1).plaques!==2||states.at(-1).foliageParts!==expected.foliageParts)
      throw Error('插画整树构件或牌面数量不一致');
  }
  if(tree||surface||whole||fork||pair||illustrated){
    await writeFile(resolve(output,'result.json'),JSON.stringify(result,null,2));
    // 性能统计已结束；另行渲染固定相机的连续成长片，不混入静帧检查。
    const frames=resolve(output,'motion-frames');await mkdir(frames,{recursive:true});
    const referenceAges=new Set(JSON.parse(await readFile(resolve(proof,'mesh.json'),'utf8')).samples.map(sample=>sample.age));
    const checkedSampleAges=[];
    for(let frame=0;frame<=100;frame++){
      const age=frame/100;
      await page.evaluate(age=>window.setVolumeProofAge(age),age);
      await page.waitForFunction(age=>Math.abs(window.volumeProofMetrics.age-age)<1e-9&&
        Math.abs(window.volumeProofPaint.age-age)<1e-9,age);
      if(referenceAges.has(age)){
        const metrics=await page.evaluate(()=>window.volumeProofMetrics);
        if(metrics.referenceError>1e-5)throw Error(`连续片源坐标不一致：${JSON.stringify(metrics)}`);
        checkedSampleAges.push(age);
      }
      await page.screenshot({type:'jpeg',quality:95,path:resolve(frames,`${String(frame).padStart(3,'0')}.jpg`)});
    }
    let log='';
    await new Promise((resolvePromise,reject)=>{
      const ffmpeg=resolve(process.env.LOCALAPPDATA,'ms-playwright/ffmpeg-1011/ffmpeg-win64.exe');
      const child=spawn(ffmpeg,['-y','-f','image2pipe','-r','10','-c:v','mjpeg','-i','pipe:0',
        '-c:v','libvpx','-b:v','1400k',resolve(output,'growth.webm')],{windowsHide:true});
      child.stderr.on('data',data=>log+=data.toString());
      child.on('error',reject);child.on('close',code=>code===0?resolvePromise():reject(Error(log)));
      const input=Readable.from((async function*(){for(let frame=0;frame<=100;frame++)
        yield await readFile(resolve(frames,`${String(frame).padStart(3,'0')}.jpg`));})());
      input.on('error',reject);child.stdin.on('error',reject);input.pipe(child.stdin);
    });
    await writeFile(resolve(output,'motion-encode.log'),log);
    result.separateMotion={file:'growth.webm',frames:101,fps:10,checkedSampleAges,
      note:'真实Flutter网格逐帧渲染后编码，不含静帧/转屏切换；编码帧率不代表运行帧率'};
  }
  result.success=errors.length===0;
  await writeFile(resolve(output,'result.json'),JSON.stringify(result,null,2));
  if(errors.length)throw Error(JSON.stringify(errors));
  console.log(output);
}catch(error){
  await page.screenshot({path:resolve(output,'failure.png')}).catch(()=>{});
  await writeFile(resolve(output,'failure.json'),JSON.stringify({error:String(error),errors},null,2));
  throw error;
}finally{await context.close();await browser.close();await new Promise(resolve=>server.close(resolve));}
