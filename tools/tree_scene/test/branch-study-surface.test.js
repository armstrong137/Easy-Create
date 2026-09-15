import test from 'node:test';
import assert from 'node:assert/strict';
import { MeshStandardMaterial } from 'three';
import { createBranchStudySurface } from '../src/BranchStudySurface.js';

test('枝条样件为单一连续表面且不存在裸露边界', () => {
  const material=new MeshStandardMaterial();
  const mesh=createBranchStudySurface(material);
  const position=mesh.geometry.getAttribute('position');
  const count=mesh.geometry.drawRange.count;
  const links=new Map(),edges=new Map();
  const key=i=>[position.getX(i),position.getY(i),position.getZ(i)].map(v=>Math.round(v*1e6)).join(',');
  for(let i=0;i<count;i+=3) {
    const vertices=[key(i),key(i+1),key(i+2)];
    for(let j=0;j<3;j++) {
      const a=vertices[j],b=vertices[(j+1)%3];
      if(a===b)continue;
      if(!links.has(a))links.set(a,new Set());
      if(!links.has(b))links.set(b,new Set());
      links.get(a).add(b);links.get(b).add(a);
      const edge=[a,b].sort().join('|');edges.set(edge,(edges.get(edge)??0)+1);
    }
  }
  const pending=[links.keys().next().value],seen=new Set();
  while(pending.length) {
    const vertex=pending.pop();if(seen.has(vertex))continue;seen.add(vertex);
    for(const neighbour of links.get(vertex))if(!seen.has(neighbour))pending.push(neighbour);
  }
  assert.ok(count>1000);
  assert.equal(seen.size,links.size,'分枝必须与主枝连接，不能只是视觉穿插');
  assert.equal([...edges.values()].filter(n=>n===1).length,0,'曲面不得有开口');
  mesh.geometry.dispose();material.dispose();
});
