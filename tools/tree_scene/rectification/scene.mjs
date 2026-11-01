// 独立二维造型验证；不接数据库，不替换正式Flutter绘制器。
const canvas = document.querySelector('canvas');
const ctx = canvas.getContext('2d');
const label = document.querySelector('#label');
const slider = document.querySelector('input');
const clamp = v => Math.max(0, Math.min(1, v));
const smooth = v => { const t = clamp(v); return t * t * (3 - 2 * t); };
const point = (x, y) => ({ x, y });
const noise = n => (Math.sin(n * 127.1 + 31.7) + 1) / 2;
const curve = (a, b, c, d) => [a, b, c, d];
function at(c, t) {
  const s = 1 - t;
  return point(s*s*s*c[0].x + 3*s*s*t*c[1].x + 3*s*t*t*c[2].x + t*t*t*c[3].x,
    s*s*s*c[0].y + 3*s*s*t*c[1].y + 3*s*t*t*c[2].y + t*t*t*c[3].y);
}
function normal(c, t) {
  const a = at(c, Math.max(0, t - .001));
  const b = at(c, Math.min(1, t + .001));
  const length = Math.hypot(b.x-a.x, b.y-a.y) || 1;
  return point(-(b.y-a.y)/length, (b.x-a.x)/length);
}
const trunk = curve(point(580,1420),point(475,1120),point(660,680),point(570,230));
const branches = [];
const sprays = [];
const ends = [[150,760],[1030,740],[180,490],[1000,460],[330,280],[870,245],[590,160]];
for (let i=0;i<7;i++) {
  const birth = .30+i*.083;
  const start = at(trunk,birth);
  const end = point(...ends[i]);
  const side = end.x < start.x ? -1 : 1;
  const spine = curve(start,point(start.x+side*95,start.y+10),point(end.x-side*120,end.y+30),end);
  branches.push({spine,birth,seed:i});
  for(let j=0;j<7;j++) {
    const attach = .25+j*.105;
    const a = at(spine,attach);
    const angle = -.4-Math.PI*.72*noise(i*11+j);
    const length = 65+100*noise(i*39+j+2);
    const end = point(a.x+Math.cos(angle)*length,a.y+Math.sin(angle)*length);
    const twig = curve(a,point(a.x+side*25,a.y-5),point(end.x,end.y+35),end);
    sprays.push({spine:twig,parent:i,attach,seed:i*17+j});
  }
}
const roots = Array.from({length:11},(_,i)=>{
  const side=i%2 ? 1:-1;
  const reach=70+noise(i+10)*315;
  const end=point(580+side*reach,1440+noise(i+88)*75);
  return {spine:curve(at(trunk,.09),point(568+side*20,1390),
    point(end.x-side*reach*.22,end.y-6),end),seed:i};
});
const bark = new Image();
bark.src = '../../../assets/tree_scene/illustrated/bark_detail.png';
await bark.decode();
const barkPattern = ctx.createPattern(bark,'repeat');
let age=clamp(Number(new URL(location.href).searchParams.get('age')??1)), close=false, playing=false;

function radius(t, size, growth, root=false) {
  const front=smooth((growth-t)*15);
  return size * (root ? (.10+.90*Math.exp(-3.6*t)) : Math.pow(1-t,.85)+.025) * front;
}
function wood(c,size,growth,seed,root=false) {
  if(growth<=0) return;
  const upper=[],lower=[];
  for(let i=0;i<=64;i++){
    const t=growth*i/64,p=at(c,t),n=normal(c,t);
    const r=radius(t,size,growth,root)*(1+.06*Math.sin(t*24+seed));
    upper.push(point(p.x+n.x*r,p.y+n.y*r));lower.push(point(p.x-n.x*r,p.y-n.y*r));
  }
  const shape=new Path2D();shape.moveTo(upper[0].x,upper[0].y);
  for(const p of upper.slice(1))shape.lineTo(p.x,p.y);
  for(const p of lower.reverse())shape.lineTo(p.x,p.y);shape.closePath();
  ctx.save();ctx.clip(shape);
  const bounds=c.map(p=>p.x),min=Math.min(...bounds)-size,max=Math.max(...bounds)+size;
  const gradient=ctx.createLinearGradient(min,0,max,30);
  gradient.addColorStop(0,'#302e21');gradient.addColorStop(.30,'#71694b');
  gradient.addColorStop(.53,'#514b35');gradient.addColorStop(.72,'#302f22');gradient.addColorStop(1,'#1e241b');
  ctx.fillStyle=gradient;ctx.fill(shape);
  // 低强度贴图只增加树皮细节；大的明暗与纵向沟脊负责表现体积。
  ctx.globalAlpha=.20+.12*age;ctx.globalCompositeOperation='multiply';
  ctx.fillStyle=barkPattern;ctx.fill(shape);ctx.globalAlpha=1;ctx.globalCompositeOperation='source-over';
  const ridges=Math.max(5,Math.round(size*.30));
  for(let j=0;j<ridges;j++){
    const offset=(j/(ridges-1)*2-1)*.95;
    ctx.beginPath();
    for(let i=0;i<=50;i++){
      const t=growth*i/50,p=at(c,t),n=normal(c,t);
      const r=radius(t,size,growth,root);
      const drift=Math.sin(t*18+seed+j*2)*.055+Math.sin(t*7+j)*.04;
      const x=p.x+n.x*r*(offset+drift),y=p.y+n.y*r*(offset+drift);
      if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);
    }
    ctx.strokeStyle=j%3===0?'#c1ae734d':'#151b15a0';ctx.lineWidth=j%3===0?1.3:1.8+noise(j+seed)*2;ctx.stroke();
  }
  ctx.restore();
}
function leaf(x,y,angle,size,tone){
  ctx.save();ctx.translate(x,y);ctx.rotate(angle);
  const shape=new Path2D();shape.moveTo(0,0);shape.bezierCurveTo(-size*.34,-size*.3,-size*.28,-size*.86,0,-size);
  shape.bezierCurveTo(size*.31,-size*.88,size*.25,-size*.28,0,0);
  const light=ctx.createLinearGradient(-size*.3,0,size*.3,0);
  light.addColorStop(0,tone?'#242e17':'#39451d');light.addColorStop(.48,tone?'#66713b':'#7c8246');light.addColorStop(1,'#30391c');
  ctx.fillStyle=light;ctx.fill(shape);ctx.strokeStyle='#a49d6155';ctx.lineWidth=.65;
  ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(0,-size*.9);ctx.stroke();ctx.restore();
}
function cluster(p,spread,seed,progress){
  if(progress<=0)return;
  // 固定叶位逐片舒展，不随着新增或树龄重排。
  for(let i=0;i<30;i++){
    const grow=smooth(progress*1.35-noise(seed*9+i)*.35);
    const phase=i*2.39996+seed;
    const reach=Math.sqrt(noise(i*7+seed))*spread;
    const x=p.x+Math.cos(phase)*reach,y=p.y+Math.sin(phase)*reach*.66;
    const size=(13+noise(i+seed*19)*12)*grow;
    leaf(x,y,phase*.5,size,i%3===0);
  }
}
function plaque(a,right,growth){
  if(growth<=0)return;
  const side=right?1:-1;
  const end=point(a.x+side*190,a.y-5);
  const support=curve(a,point(a.x+side*85,a.y+75),point(end.x-side*45,end.y+35),end);
  wood(support,24,growth,44);
  if(growth<.98)return;
  ctx.save();ctx.translate(end.x,end.y-64);
  ctx.shadowColor='#261c1544';ctx.shadowBlur=8;
  ctx.fillStyle='#3b3625';ctx.beginPath();ctx.roundRect(-46,-68,92,137,[26,17,23,16]);ctx.fill();
  ctx.shadowBlur=0;ctx.strokeStyle='#a69a69';ctx.lineWidth=3;ctx.stroke();
  ctx.fillStyle='#ddcba5';ctx.beginPath();ctx.roundRect(-34,-55,68,112,[18,11,17,10]);ctx.fill();
  ctx.strokeStyle='#76603c';ctx.lineWidth=1.5;ctx.stroke();
  ctx.fillStyle='#2c281d';ctx.font='25px serif';ctx.textAlign='center';
  for(const [i,char] of [...(right?'第一节':'第九章')].entries())ctx.fillText(char,0,-20+i*29);
  ctx.restore();
  cluster(point(end.x+side*22,end.y-133),22,55+side,.9);
}
function render(value=age,near=close){
  age=clamp(value);close=near;
  const w=innerWidth,h=innerHeight,dpr=Math.min(devicePixelRatio,2);
  canvas.width=w*dpr;canvas.height=h*dpr;ctx.scale(dpr,dpr);
  ctx.fillStyle='#f7f0e3';ctx.fillRect(0,0,w,h);
  const scale=near ? Math.min(w/650,h/1000) : Math.min(w/1200,(h-115)/1672);
  ctx.translate(w/2,h/2+20);ctx.scale(scale,scale);ctx.translate(-580,near?-1040:-850);
  const g=.28+.72*smooth(age),thickness=.14+.86*smooth(age);
  const shadow=ctx.createRadialGradient(580,1480,0,580,1480,420*thickness);
  shadow.addColorStop(0,'#3b2e2340');shadow.addColorStop(1,'#3b2e2300');
  ctx.save();ctx.translate(0,1480);ctx.scale(1,.16);ctx.translate(0,-1480);
  ctx.fillStyle=shadow;ctx.fillRect(100,1000,950,950);ctx.restore();
  for(const root of roots)wood(root.spine,(45+noise(root.seed)*50)*thickness,
    .35+age*.65,root.seed,true);
  const branchGrowth=branches.map(b=>smooth((g-b.birth)/(.96-b.birth)));
  // 先画背部叶簇，再画主骨架与前景叶簇，形成统一前后层次。
  for(const s of sprays){
    const growth=smooth((branchGrowth[s.parent]-s.attach)/.38);
    cluster(at(s.spine,1),42+noise(s.seed)*25,s.seed,growth);
  }
  wood(trunk,115*thickness,g,11);
  for(let i=0;i<branches.length;i++)wood(branches[i].spine,47*thickness*(1-i*.045),branchGrowth[i],i+1);
  for(const s of sprays){
    const growth=smooth((branchGrowth[s.parent]-s.attach)/.38);
    wood(s.spine,7*thickness,growth,s.seed);
    if(s.seed%3===0)cluster(at(s.spine,.85),30,s.seed+90,growth);
  }
  // 幼苗有完整叶簇，新叶始终依附同一段已伸展中心线。
  for(const t of [.10,.16,.22]){
    if(g>t)cluster(at(trunk,t),20,100+t*100,smooth((g-t)/.08));
  }
  const supports=smooth((age-.12)/.22);
  plaque(at(trunk,.17),false,supports);plaque(at(trunk,.39),true,smooth((age-.32)/.25));
  label.textContent=`树龄 ${age.toFixed(3)} · 时间 ${(age*10).toFixed(1)}s · ${near?'枝牌近景':'固定全景'}`;
  slider.value=String(age);
  return {age,near,branches:branches.length,sprays:sprays.length};
}
window.treeSpecimen={render,get age(){return age;}};
slider.oninput=()=>{playing=false;render(Number(slider.value));};
document.querySelector('#close').onclick=()=>render(age,!close);
document.querySelector('#play').onclick=()=>{
  playing=true;const start=performance.now();
  function tick(now){if(!playing)return;render((now-start)/10000,false);if(age<1)requestAnimationFrame(tick);else playing=false;}
  requestAnimationFrame(tick);
};
addEventListener('resize',()=>render());render();
