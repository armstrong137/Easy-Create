import * as THREE from 'three';
import { MarchingCubes } from 'three/addons/objects/MarchingCubes.js';

// 只用于离线美术样件：以距离场合并主枝与分叉，避免圆管穿插接缝。
export function createBranchStudySurface(material, resolution = 180) {
  const half = 2.2;
  const branches = [
    { points: [[1.8,-.55,0],[1.15,-.45,0],[.45,-.45,0],[-.3,-.1,0],[-1.2,.25,0],[-1.8,.65,0]], radius: .14 },
    { points: [[-.2,-.13,0],[-.5,.28,.02],[-.8,.6,0],[-1,.95,0]], radius: .055 },
    { points: [[.75,-.46,0],[.6,-.12,.03],[.4,.12,0]], radius: .045 },
  ];
  const combined = new Float32Array(resolution ** 3).fill(1);
  for (const branch of branches) {
    const field = new Float32Array(combined.length).fill(1);
    const curve = new THREE.CatmullRomCurve3(branch.points.map(p => new THREE.Vector3(...p)));
    const points = curve.getSpacedPoints(48);
    for (let i = 0; i < 48; i++) {
      const a = points[i], b = points[i+1], ab = b.clone().sub(a), length2 = ab.lengthSq();
      const ra = branch.radius * (1-i/48) ** .7 + .008;
      const rb = branch.radius * (1-(i+1)/48) ** .7 + .008;
      const padding = ra + .08;
      const lower = ['x','y','z'].map(k => Math.max(1, Math.floor((Math.min(a[k],b[k])-padding+half)/(2*half)*resolution)));
      const upper = ['x','y','z'].map(k => Math.min(resolution-2, Math.ceil((Math.max(a[k],b[k])+padding+half)/(2*half)*resolution)));
      for(let z=lower[2];z<=upper[2];z++) for(let y=lower[1];y<=upper[1];y++) for(let x=lower[0];x<=upper[0];x++) {
        const px=x/resolution*2*half-half-a.x, py=y/resolution*2*half-half-a.y, pz=z/resolution*2*half-half-a.z;
        const t=Math.max(0,Math.min(1,(px*ab.x+py*ab.y+pz*ab.z)/length2));
        const distance=Math.hypot(px-t*ab.x,py-t*ab.y,pz-t*ab.z)-(ra+(rb-ra)*t);
        const index=x+resolution*(y+resolution*z);
        field[index]=Math.min(field[index],distance);
      }
    }
    // 同一枝内部取并集，不沿曲线累积膨胀；只在不同分叉之间平滑根颈。
    for(let i=0;i<combined.length;i++) {
      const a=combined[i], b=field[i], k=.06;
      const h=Math.max(k-Math.abs(a-b),0)/k;
      combined[i]=Math.min(a,b)-h*h*k*.25;
    }
  }
  const surface=new MarchingCubes(resolution,material,false,false,180000);
  surface.isolation=0;
  for(let i=0;i<combined.length;i++) surface.field[i]=-combined[i];
  surface.update();surface.scale.setScalar(half);
  const positions=surface.geometry.getAttribute('position');
  const uv=new Float32Array(positions.count*2);
  for(let i=0;i<positions.count;i++) {
    // 世界尺度投影保持树皮纹理大小，分叉处不切换到另一张纹理。
    uv[i*2]=(positions.getY(i)*half+1)*.6;
    uv[i*2+1]=(positions.getX(i)*half+2)*.6;
  }
  surface.geometry.setAttribute('uv',new THREE.BufferAttribute(uv,2));
  return surface;
}
