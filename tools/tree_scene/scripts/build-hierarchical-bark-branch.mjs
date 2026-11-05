import { readFile, writeFile, mkdir } from 'node:fs/promises';

// 在冻结的局部分叉上增加真实二级枝，九个基点直接复用一级枝上缘索引。
const input='docs/Reports/Codex/共享图集分叉材质验证';
const output='build/qa/hierarchical-bark-proof';
await mkdir(output,{recursive:true});
const meta=JSON.parse(await readFile(`${input}/mesh.json`));
const binary=await readFile(`${input}/mesh.bin`);
if(meta.vertexCount!==801 || meta.triangleCount!==1408) throw Error('多级验证需要冻结的单分叉版本');
const values=name=>{
  const section=meta.sections[name];
  return Array.from({length:section.length},(_,i)=>binary.readFloatLE(section.offset+i*4));
};
const poses=meta.vertexPoseSections.map(values);
const normals=values('normals');
const originalCorners=values('corners'),originalFaces=Array.from({length:meta.triangleCount},(_,i)=>[0,3,6].map(k=>originalCorners[i*9+k]));
const attachment=[701,710,719],splits=[];
// 只在实际接入口细分两条母枝边，保持原有母枝轮廓并得到九点短接边。
for(let edge=0;edge<2;edge++) {
  const [a,b]=attachment.slice(edge,edge+2),chain=[a];
  for(let step=1;step<4;step++) {
    const t=step/4,index=poses[0].length/3;chain.push(index);
    for(const pose of poses) for(let axis=0;axis<3;axis++) pose.push(pose[a*3+axis]*(1-t)+pose[b*3+axis]*t);
    for(let axis=0;axis<3;axis++) normals.push(normals[a*3+axis]*(1-t)+normals[b*3+axis]*t);
  }
  chain.push(b);splits.push({a,b,chain});
}
const boundary=[...splits[0].chain,...splits[1].chain.slice(1)];
const faces=[];
for(const face of originalFaces) {
  const split=splits.find(s=>face.includes(s.a)&&face.includes(s.b));
  if(!split) {faces.push(face);continue;}
  const other=face.find(i=>i!==split.a&&i!==split.b);
  const ai=face.indexOf(split.a),forward=face[(ai+1)%3]===split.b;
  const chain=forward ? split.chain : [...split.chain].reverse();
  for(let i=1;i<chain.length;i++) faces.push([other,chain[i-1],chain[i]]);
}
const parentFaceCount=faces.length;
const lengths=[.035,.05,.65,1.8];
const start=poses[0].length/3;
for(const [frame,pose] of poses.entries()) {
  const base=boundary.map(i=>pose.slice(i*3,i*3+3));
  const center=[0,1,2].map(axis=>base.reduce((sum,p)=>sum+p[axis],0)/base.length);
  const dx=base[8][0]-base[0][0],dz=base[8][2]-base[0][2],span=Math.hypot(dx,dz);
  const tx=dx/span,tz=dz/span,nx=-tz,nz=tx;
  for(let row=1;row<=24;row++) {
    const t=row/24,reach=.1*t+.9*t*t,bend=.18*t*t*t;
    const x=center[0]+lengths[frame]*(nx*reach+tx*bend);
    const z=center[2]+lengths[frame]*(nz*reach+tz*bend);
    const tangentX=nx*(.1+1.8*t)+tx*.54*t*t,tangentZ=nz*(.1+1.8*t)+tz*.54*t*t;
    const tangentLength=Math.hypot(tangentX,tangentZ),crossX=tangentZ/tangentLength,crossZ=-tangentX/tangentLength;
    const half=span*.5*(1-.97*t),blend=Math.min(1,t*5),smooth=blend*blend*(3-2*blend);
    for(let col=0;col<9;col++) {
      const u=col/4-1;
      const residualX=base[col][0]-center[0]-tx*span*.5*u;
      const residualZ=base[col][2]-center[2]-tz*span*.5*u;
      pose.push(x+crossX*half*u+residualX*(1-smooth),
        center[1]-half*Math.sqrt(Math.max(0,1-u*u))*smooth,
        z+crossZ*half*u+residualZ*(1-smooth));
      if(frame===poses.length-1) normals.push(crossX*u,-Math.sqrt(Math.max(0,1-u*u)),crossZ*u);
    }
  }
}
for(let row=0;row<24;row++) {
  const previous=row===0 ? boundary : Array.from({length:9},(_,i)=>start+(row-1)*9+i);
  const current=Array.from({length:9},(_,i)=>start+row*9+i);
  for(let col=0;col<8;col++) for(const face of [
    [previous[col],current[col+1],current[col]],
    [previous[col],previous[col+1],current[col+1]],
  ]) faces.push(face);
}
const rest=poses.at(-1),corners=faces.flatMap(face=>face.flatMap(index=>[index,(rest[index*3]+.5)/4,(6.9-rest[index*3+2])/7.2]));
const arrays={normals,corners,...Object.fromEntries(poses.map((p,i)=>[`positions${i}`,p]))};
const payload=[],sections={};
for(const [name,array] of Object.entries(arrays)) {
  sections[name]={offset:payload.length*4,length:array.length};payload.push(...array);
}
const bytes=Buffer.alloc(payload.length*4);
payload.forEach((v,i)=>bytes.writeFloatLE(v,i*4));
const metadata={...meta,format:'共享两级分叉材质验证-v1',vertexCount:poses[0].length/3,triangleCount:faces.length,
  sections,byteLength:bytes.length,scope:'仅共享两级分叉与材质，不含根冠枝牌或完整幼苗',
  materialDomains:[
    {name:'主干',faceStart:0,faceCount:1024,parent:null,boundary:[]},
    {name:'一级枝',faceStart:1024,faceCount:parentFaceCount-1024,parent:0,boundary:Array.from({length:9},(_,i)=>(20+i)*9+8)},
    {name:'二级枝',faceStart:parentFaceCount,faceCount:384,parent:1,boundary},
  ],samples:poses.map((p,frame)=>({age:meta.poseFrames[frame].age,
    vertices:Array.from({length:p.length/3},(_,i)=>({index:i,position:p.slice(i*3,i*3+3)}))}))};
await writeFile(`${output}/mesh.bin`,bytes);
await writeFile(`${output}/mesh.json`,JSON.stringify(metadata));
console.log(JSON.stringify({vertices:metadata.vertexCount,triangles:metadata.triangleCount,boundary}));
