import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {chromium} from 'playwright';

// 生成独立可编辑构图示意，不改批准参考PNG，也不作为运行时整树图片。
const directory=resolve('assets/source/magic_tree/guides');
const guide=JSON.parse(await readFile(resolve(directory,'reference_composition_v1.json'),'utf8'));
const canopy=depth=>guide.canopy.filter(p=>p.depth===depth).map(p=>
  `<ellipse cx="${p.cx}" cy="${p.cy}" rx="${p.rx}" ry="${p.ry}" transform="rotate(${p.angle} ${p.cx} ${p.cy})" fill="${depth==='back'?'#87a892':'#6d894c'}" fill-opacity=".70" stroke="#43573b" stroke-width="3"/>`).join('');
const wood=[...guide.roots,...guide.trunk,...guide.branches].map(p=>
  `<path d="${p.path}" fill="none" stroke="#72533d" stroke-width="${p.width}" stroke-linecap="round"/>`).join('');
const labels=guide.canopy.map(p=>{const width=Math.max(116,50+p.name.length*20);return `<g><rect x="${p.cx-width/2}" y="${p.cy-18}" width="${width}" height="36" rx="8" fill="#fff9ec" stroke="#43573b"/><text x="${p.cx}" y="${p.cy+7}" text-anchor="middle" font-size="20">${p.id} ${p.name}</text></g>`;}).join('');
const zones=guide.readingZones.map(p=>`<g><rect x="${p.x}" y="${p.y}" width="${p.width}" height="${p.height}" rx="14" fill="#f5da9c" fill-opacity=".35" stroke="#a9782e" stroke-width="3" stroke-dasharray="12 8"/><text x="${p.x+p.width/2}" y="${p.y+80}" text-anchor="middle" font-size="25" fill="#775326">${p.name}</text></g>`).join('');
const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${guide.width}" height="${guide.height}" viewBox="0 0 ${guide.width} ${guide.height}" font-family="Microsoft YaHei, sans-serif" fill="#243321"><rect width="100%" height="100%" fill="#f8f3e9"/>${canopy('back')}${wood}${canopy('front')}${labels}${zones}<path d="M 100 ${guide.groundY} H 940" stroke="#998b72" stroke-width="2" stroke-dasharray="10 10"/><text x="40" y="1390" font-size="23">人工结构观察 · 非逐像素分割 · 不代表A2通过</text></svg>`;
await writeFile(resolve(directory,'reference_composition_v1.svg'),svg);
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
try{
  const page=await browser.newPage({viewport:{width:guide.width,height:guide.height},deviceScaleFactor:1});
  await page.setContent(`<body style="margin:0">${svg}</body>`);
  await page.evaluate(()=>document.fonts.ready);
  await page.locator('svg').screenshot({path:resolve(directory,'reference_composition_v1.png')});
}finally{await browser.close();}
console.log(resolve(directory,'reference_composition_v1.png'));
