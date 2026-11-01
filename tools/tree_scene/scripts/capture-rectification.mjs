import { chromium } from 'playwright';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

// 只提供仓库内的本地资源；样件不连接正式应用或小说数据库。
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const output=resolve(root,'build/qa/rectification-round-2',new Date().toISOString().replaceAll(':','-'));
await mkdir(output,{recursive:true});
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext({viewport:{width:900,height:1280},deviceScaleFactor:1});
const errors=[];
const page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));
async function localRoute(route){
  const url=new URL(route.request().url());
  const path=resolve(root,'.'+decodeURIComponent(url.pathname));
  if(url.hostname!=='specimen.local'||relative(root,path).startsWith('..'))return route.abort();
  const types={'.html':'text/html','.mjs':'text/javascript','.png':'image/png'};
  try {await route.fulfill({body:await readFile(path),contentType:types[extname(path)]??'application/octet-stream'});}
  catch {await route.fulfill({status:404,body:'not found'});}
}
await context.route('**/*',localRoute);
let motionContext;
try {
  await page.goto('http://specimen.local/tools/tree_scene/rectification/index.html');
  await page.waitForFunction(()=>window.treeSpecimen);
  for(const [name,age] of [['sapling',0],['middle',.5],['mature',1]]){
    await page.evaluate(age=>window.treeSpecimen.render(age,false),age);
    await page.screenshot({path:resolve(output,`${name}.png`)});
  }
  await page.setViewportSize({width:430,height:932});
  await page.evaluate(()=>window.treeSpecimen.render(1,true));
  await page.screenshot({path:resolve(output,'plaque-close.png')});
  // 独立录制只包含0到1的连续成长，不混入静帧切换和镜头切换。
  motionContext=await browser.newContext({viewport:{width:900,height:1280},deviceScaleFactor:1,
    recordVideo:{dir:resolve(output,'video'),size:{width:900,height:1280}}});
  await motionContext.route('**/*',localRoute);
  const motion=await motionContext.newPage();
  motion.on('pageerror',e=>errors.push(e.message));
  await motion.goto('http://specimen.local/tools/tree_scene/rectification/index.html?age=0');
  await motion.waitForFunction(()=>window.treeSpecimen);
  await motion.locator('#play').click();
  await motion.waitForFunction(()=>window.treeSpecimen.age===1,{},{timeout:15000});
  await motion.waitForTimeout(600);
  await motionContext.close();
  await motion.video().saveAs(resolve(output,'growth.webm'));
  if(errors.length)throw Error(JSON.stringify(errors));
  const source=await readFile(resolve(root,'tools/tree_scene/rectification/scene.mjs'));
  await writeFile(resolve(output,'result.json'),JSON.stringify({
    sourceSha256:createHash('sha256').update(source).digest('hex'),
    renderer:'独立Canvas2D连续曲线样件，尚未集成Flutter',
    images:['sapling.png','middle.png','mature.png','plaque-close.png'],
    animation:'growth.webm：独立上下文只录制树龄0到1；固定相机，不混入静帧及镜头切换',
    errors,visualAcceptance:'待整套人工审查，不由本脚本自动判定',
  },null,2));
  console.log(output);
}finally{await motionContext?.close();await context.close();await browser.close();}
