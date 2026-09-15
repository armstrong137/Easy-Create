import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import assert from 'node:assert/strict';

// 独立几何样件，不写入生产素材；透明度由 WebGL 输出而非抠色获得。
const root = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
const output = resolve(root, process.argv[2] ?? 'build/branch-study');
await mkdir(output, { recursive: true });
const html = `<!doctype html><style>html,body{margin:0;background:transparent}canvas{display:block}</style>
<script type="importmap">{"imports":{"three":"/tools/tree_scene/node_modules/three/build/three.module.js","three/addons/":"/tools/tree_scene/node_modules/three/examples/jsm/"}}</script>
<script type="module">
import * as T from '/tools/tree_scene/node_modules/three/build/three.module.js';
import {createBranchStudySurface} from '/tools/tree_scene/src/BranchStudySurface.js';
const renderer = new T.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:true});
renderer.setSize(1536,1024);renderer.setClearColor(0,0);
renderer.outputColorSpace=T.SRGBColorSpace;
document.body.appendChild(renderer.domElement);
const scene=new T.Scene();
const camera=new T.OrthographicCamera(-2.3,2.3,1.53,-1.53,.1,30);
camera.position.set(0,0,8);camera.lookAt(0,0,0);
scene.add(new T.HemisphereLight(0xffedc9,0x38311c,2));
const light=new T.DirectionalLight(0xffe2af,3);light.position.set(-3,5,6);scene.add(light);
const loader=new T.TextureLoader();
const bark=await loader.loadAsync('/assets/source/magic_tree/textures_source/bark_old_basecolor_source.png');
bark.colorSpace=T.SRGBColorSpace;bark.wrapS=bark.wrapT=T.RepeatWrapping;
const material=new T.MeshStandardMaterial({map:bark,bumpMap:bark,bumpScale:.025,roughness:.93});
const normal=await loader.loadAsync('/assets/source/magic_tree/textures_source/pbr/bark_old_normal.png');
const roughness=await loader.loadAsync('/assets/source/magic_tree/textures_source/pbr/bark_old_roughness.png');
for(const texture of [normal,roughness])texture.wrapS=texture.wrapT=T.RepeatWrapping;
material.normalMap=normal;material.normalScale.set(.65,.65);material.roughnessMap=roughness;
material.bumpMap=null;
scene.add(createBranchStudySurface(material));
// 从现有真实透明叶片图集取 UV，叶片有弯曲深度，叶柄落在枝梢上。
const atlas=await loader.loadAsync('/assets/source/magic_tree/textures_source/leaf_atlas_rgba.png');
atlas.colorSpace=T.SRGBColorSpace;
const leafMaterial=new T.MeshStandardMaterial({map:atlas,alphaTest:.4,side:T.DoubleSide,roughness:.85});
const leafGeometry=new T.PlaneGeometry(.2,.34,8,12);
const lp=leafGeometry.getAttribute('position'),luv=leafGeometry.getAttribute('uv');
for(let i=0;i<lp.count;i++){
 const u=luv.getX(i),v=luv.getY(i);
 lp.setZ(i,.045*Math.sin(v*Math.PI)-.02*Math.abs(u-.5));
 lp.setY(i,lp.getY(i)+.17);
 luv.setXY(i,.035+u*.20,.64+v*.35);
}
leafGeometry.computeVertexNormals();
for(const [x,y,z,angle,tilt] of [
 [-1.72,.59,.01,.8,-.3],[-1.72,.59,.01,-1.1,.2],[-1.55,.48,.01,.3,.3],
 [-.95,.85,.01,.7,.25],[-.95,.85,.01,-.8,-.2],[-.82,.65,.01,-1.3,.2],
 [.43,.07,.01,.6,.2],[.43,.07,.01,-.9,-.3],
 [-.9,.1,.05,-1.8,.1],[1.1,-.42,.08,1.2,-.2],
 ]){
 const leaf=new T.Mesh(leafGeometry,leafMaterial);leaf.position.set(x,y,z);leaf.rotation.set(tilt,0,angle);scene.add(leaf);
}
renderer.render(scene,camera);window.ready=true;
</script>`;
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end(html);return;}
  const path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://local').pathname));
  if(!path.startsWith(root+sep)){res.writeHead(403);res.end();return;}
  res.setHeader('Content-Type',extname(path)==='.js'?'text/javascript':'image/png');res.end(await readFile(path));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--use-angle=swiftshader','--enable-webgl']});
 const page=await browser.newPage({viewport:{width:1536,height:1024}});
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto('http://127.0.0.1:'+server.address().port);
 await page.waitForFunction(()=>window.ready,{},{timeout:60000});
 const bytes=await page.screenshot({omitBackground:true});
 await writeFile(resolve(output,'branch.png'),bytes);
 // 另存米白底预览以检查真实合成观感，透明原图保持不变。
 await page.evaluate(()=>document.body.style.background='#FDF6EC');
 await page.screenshot({path:resolve(output,'preview.png')});
 const png=PNG.sync.read(bytes);let clear=0,solid=0;
 for(let i=3;i<png.data.length;i+=4){if(png.data[i]===0)clear++;if(png.data[i]===255)solid++;}
 const report={width:png.width,height:png.height,transparentFraction:clear/(png.width*png.height),opaqueFraction:solid/(png.width*png.height),errors,visualAcceptance:'待人工检查，不自动宣告通过'};
 await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));
 assert.equal(errors.length,0,'渲染不得有脚本错误');
 assert.ok(report.transparentFraction>.7&&report.opaqueFraction>.01,'必须同时包含真实透明背景与可见枝体');
 console.log(JSON.stringify({output,...report}));
}finally{await browser?.close();await new Promise(r=>server.close(r));}
