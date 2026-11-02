import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

// 对顶点线性插值区间求有向面积二次式的最小值，而非仅抽查姿态端点。
const proof=resolve(process.argv[2]??'build/qa/contour-cage-proof');
const metadata=await readFile(resolve(proof,'mesh.json')),meta=JSON.parse(metadata);
const binary=await readFile(resolve(proof,'mesh.bin'));
if(meta.camera.right?.join(',')!=='1,0,0'||meta.camera.up?.join(',')!=='0,0,1')
  throw Error('本审计要求X-Z正交投影，不将其结论外推到其他相机');
function section(name){const s=meta.sections[name];return Array.from({length:s.length},(_,i)=>binary.readFloatLE(s.offset+i*4));}
const poses=meta.vertexPoseSections.map(section),corners=section('corners');
const maxCoordinate=Math.max(...poses.map(p=>Math.max(...p.map(Math.abs))));
const roundingError=(2*maxCoordinate+Math.max(...meta.camera.target.map(Math.abs)))*2**-24;
function area(p){return (p[1][0]-p[0][0])*(p[2][1]-p[0][1])-(p[1][1]-p[0][1])*(p[2][0]-p[0][0]);}
const intervals=[];
for(let frame=0;frame<poses.length-1;frame++){
  let minimum=Infinity,minimumMargin=Infinity,unsafe=0;
  for(let i=0;i<corners.length;i+=9){
    const ids=[corners[i],corners[i+3],corners[i+6]].map(Math.round);
    const a=ids.map(v=>[poses[frame][v*3],poses[frame][v*3+2]]);
    const b=ids.map(v=>[poses[frame+1][v*3],poses[frame+1][v*3+2]]);
    const middle=a.map((p,j)=>p.map((v,k)=>(v+b[j][k])/2));
    const c=area(a),q1=area(b),qhalf=area(middle);
    const quadratic=2*(q1+c-2*qhalf),linear=q1-c-quadratic;
    const t=quadratic>0?Math.max(0,Math.min(1,-linear/(2*quadratic))):0;
    const smallest=Math.min(c,q1,c+linear*t+quadratic*t*t);
    // 每个端点/插值位置坐标误差不超过e，边误差不超过2e；包含Float32投影舍入。
    const edgeBound=Math.max(...[a,b].map(p=>
      Math.abs(p[1][0]-p[0][0])+Math.abs(p[1][1]-p[0][1])+
      Math.abs(p[2][0]-p[0][0])+Math.abs(p[2][1]-p[0][1])));
    const bound=2*roundingError*edgeBound+8*roundingError**2;
    const margin=smallest-bound;
    minimum=Math.min(minimum,smallest);minimumMargin=Math.min(minimumMargin,margin);
    if(margin<=0)unsafe++;
  }
  intervals.push({from:meta.poseFrames[frame].age,to:meta.poseFrames[frame+1].age,
    triangles:corners.length/9,minimumSignedArea:minimum,minimumAreaAfterRoundingBound:minimumMargin,unsafeTriangles:unsafe});
}
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const report={success:intervals.every(v=>v.unsafeTriangles===0),meshSha256:hash(binary),metadataSha256:hash(metadata),
  intervals,coordinateRoundingBound:roundingError,
  scope:'X-Z局部顶点姿态的线性插值；smoothstep只重参数化[0,1]，二次面积式覆盖整个区间。保守Float32坐标误差界不代表GPU逐像素、自然造型或整树验收。未含完整树冠、枝牌及业务交互。'};
await writeFile(resolve(proof,'interval-audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
if(!report.success)process.exitCode=1;
