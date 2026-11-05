import { readFile, writeFile, mkdir } from 'node:fs/promises';

// 根颈由主干边界长出；侧根与前根分别控制膝部、展幅和圆趾。
const input='docs/Reports/Codex/共享图集两级分叉验证',output='build/qa/rooted-bark-proof';
await mkdir(output,{recursive:true});
const meta=JSON.parse(await readFile(`${input}/mesh.json`)),binary=await readFile(`${input}/mesh.bin`);
const values=name=>{
  const s=meta.sections[name];return Array.from({length:s.length},(_,i)=>binary.readFloatLE(s.offset+i*4));
};
const poses=meta.vertexPoseSections.map(values),normals=values('normals'),original=values('corners');
const ports=[
  {name:'左根',indices:[0,9,18,27,36],side:-1,reverse:true},
  {name:'右根',indices:[8,17,26,35,44],side:1,reverse:false},
  {name:'前根',indices:[2,3,4,5,6],side:0,reverse:false},
];
const splits=[];
for(const port of ports) {
  port.boundary=[];
  for(let edge=0;edge<4;edge++) {
    const a=port.indices[edge],b=port.indices[edge+1],index=poses[0].length/3;
    for(const pose of poses) for(let axis=0;axis<3;axis++) pose.push((pose[a*3+axis]+pose[b*3+axis])/2);
    for(let axis=0;axis<3;axis++) normals.push((normals[a*3+axis]+normals[b*3+axis])/2);
    splits.push({a,b,middle:index});port.boundary.push(a,index);
  }
  port.boundary.push(port.indices[4]);
}
const faces=[],domains=meta.materialDomains.map(d=>({...d,faceCount:0}));
for(let number=0;number<meta.triangleCount;number++) {
  const face=[0,3,6].map(k=>original[number*9+k]);
  const domain=meta.materialDomains.findIndex(d=>number>=d.faceStart && number<d.faceStart+d.faceCount);
  const split=splits.find(s=>face.includes(s.a)&&face.includes(s.b));
  if(split) {
    const other=face.find(i=>i!==split.a&&i!==split.b),ai=face.indexOf(split.a);
    const chain=face[(ai+1)%3]===split.b ? [split.a,split.middle,split.b] : [split.b,split.middle,split.a];
    faces.push([other,chain[0],chain[1]],[other,chain[1],chain[2]]);domains[domain].faceCount+=2;
  } else {faces.push(face);domains[domain].faceCount++;}
}
let faceStart=0;
for(const domain of domains) {domain.faceStart=faceStart;faceStart+=domain.faceCount;}
for(const port of ports) {
  const first=poses[0].length/3;
  domains.push({name:port.name,faceStart:faces.length,faceCount:384,parent:0,boundary:port.boundary});
  for(const [frame,pose] of poses.entries()) {
    const age=meta.poseFrames[frame].age;
    const base=port.boundary.map(i=>pose.slice(i*3,i*3+3));
    const center=[0,1,2].map(axis=>base.reduce((s,p)=>s+p[axis],0)/9);
    const dx=base[8][0]-base[0][0],dz=base[8][2]-base[0][2],span=Math.hypot(dx,dz),tx=dx/span,tz=dz/span;
    const toe=port.side ? [port.side*(.17+1.23*age),-.02-.13*age] : [center[0],-.045-.19*age];
    const controls=[center.slice(),port.side ? [center[0]+port.side*(.05+.28*age),center[1],center[2]*.72] : [center[0],center[1]-.04-.22*age,center[2]-.01],
      [toe[0]-port.side*(.05+.12*age),center[1]-.04-.24*age,toe[1]+.025],
      [toe[0],center[1]-.06-.32*age,toe[1]]];
    const point=t=>[0,1,2].map(axis=>(1-t)**3*controls[0][axis]+3*(1-t)**2*t*controls[1][axis]
      +3*(1-t)*t*t*controls[2][axis]+t**3*controls[3][axis]);
    for(let row=1;row<=24;row++) {
      const t=row/24,p=point(t),a=point(Math.max(0,t-.001)),b=point(Math.min(1,t+.001));
      const length=Math.hypot(b[0]-a[0],b[2]-a[2]),vx=(b[0]-a[0])/length,vz=(b[2]-a[2])/length;
      let crossX=-vz,crossZ=vx;
      if(crossX*tx+crossZ*tz<0) {crossX=-crossX;crossZ=-crossZ;}
      const radius=span*.5*(.16+.84*(1-t)**.8),smooth=Math.min(1,t*5)**2*(3-2*Math.min(1,t*5));
      const turn=t*t*(3-2*t);
      crossX=crossX*turn+tx*(1-turn);crossZ=crossZ*turn+tz*(1-turn);
      const crossLength=Math.hypot(crossX,crossZ);crossX/=crossLength;crossZ/=crossLength;
      for(let col=0;col<9;col++) {
        const u=col/4-1,round=Math.sqrt(Math.max(0,1-u*u));
        pose.push(p[0]+crossX*radius*u+(base[col][0]-center[0]-tx*span*.5*u)*(1-smooth),
          p[1]-radius*round*smooth,
          p[2]+crossZ*radius*u+(base[col][2]-center[2]-tz*span*.5*u)*(1-smooth));
        if(frame===poses.length-1) normals.push(crossX*u,-round,crossZ*u);
      }
    }
  }
  for(let row=0;row<24;row++) {
    const previous=row===0 ? port.boundary : Array.from({length:9},(_,i)=>first+(row-1)*9+i);
    const current=Array.from({length:9},(_,i)=>first+row*9+i);
    for(let col=0;col<8;col++) for(const face of [[previous[col],current[col],current[col+1]],[previous[col],current[col+1],previous[col+1]]]) {
      faces.push(port.reverse ? face.reverse() : face);
    }
  }
  // 圆趾单独接在末截面上，避免同时收窄截面并向前鼓起造成参数线折返。
  const capStart=poses[0].length/3,last=Array.from({length:9},(_,i)=>first+23*9+i);
  for(const [frame,pose] of poses.entries()) {
    const middle=last[4],previous=first+22*9+4;
    const dx=pose[middle*3]-pose[previous*3],dz=pose[middle*3+2]-pose[previous*3+2],length=Math.hypot(dx,dz);
    const radius=Math.hypot(pose[last[8]*3]-pose[last[0]*3],pose[last[8]*3+2]-pose[last[0]*3+2])/2;
    for(let col=1;col<8;col++) {
      const u=col/4-1,reach=radius*.6*Math.sqrt(1-u*u),index=last[col];
      pose.push(pose[index*3]+dx/length*reach,pose[index*3+1],pose[index*3+2]+dz/length*reach);
      if(frame===poses.length-1) normals.push(...normals.slice(index*3,index*3+3));
    }
  }
  const arc=[last[0],...Array.from({length:7},(_,i)=>capStart+i),last[8]];
  for(let col=0;col<8;col++) for(const face of [[last[col],arc[col],arc[col+1]],[last[col],arc[col+1],last[col+1]]]) {
    if(new Set(face).size<3) continue;
    faces.push(port.reverse ? face.reverse() : face);domains.at(-1).faceCount++;
  }
  port.toeVertex=capStart+3;
  port.contact={tip:port.toeVertex,width:[last[0],last[8]]};
}
const rest=poses.at(-1),corners=faces.flatMap(face=>face.flatMap(i=>[i,(rest[i*3]+1.5)/6,(6.9-rest[i*3+2])/7.2]));
const arrays={normals,corners,...Object.fromEntries(poses.map((p,i)=>[`positions${i}`,p]))},sections={},payload=[];
for(const [name,values] of Object.entries(arrays)) {sections[name]={offset:payload.length*4,length:values.length};payload.push(...values);}
const bytes=Buffer.alloc(payload.length*4);payload.forEach((v,i)=>bytes.writeFloatLE(v,i*4));
const metadata={...meta,format:'共享根颈及两级枝材质验证-v1',sections,byteLength:bytes.length,
  vertexCount:poses[0].length/3,triangleCount:faces.length,materialDomains:domains,rootToeVertices:ports.map(p=>p.toeVertex),rootContacts:ports.map(p=>p.contact),
  scope:'共享根颈及两级枝材质；不含冠层木牌，不是完整A2样件',
  samples:poses.map((p,frame)=>({age:meta.poseFrames[frame].age,vertices:Array.from({length:p.length/3},(_,i)=>({index:i,position:p.slice(i*3,i*3+3)}))}))};
await writeFile(`${output}/mesh.bin`,bytes);await writeFile(`${output}/mesh.json`,JSON.stringify(metadata));
console.log(JSON.stringify({vertices:metadata.vertexCount,triangles:metadata.triangleCount,roots:ports.map(p=>({name:p.name,boundary:p.boundary}))}));
