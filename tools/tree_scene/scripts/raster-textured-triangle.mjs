// 软件取样只用于独立验证，纹理三角共用像素中心规则。
export function rasterTexturedTriangle(target, texture, destination, source) {
  const [a, b, c] = destination;
  const edge = (p, q, x, y) => (q[0]-p[0])*(y-p[1])-(q[1]-p[1])*(x-p[0]);
  const area = edge(a,b,c[0],c[1]);
  if (Math.abs(area) < 1e-8) throw Error('纹理三角退化');
  const minX=Math.max(0,Math.floor(Math.min(a[0],b[0],c[0])));
  const maxX=Math.min(target.width-1,Math.ceil(Math.max(a[0],b[0],c[0])));
  const minY=Math.max(0,Math.floor(Math.min(a[1],b[1],c[1])));
  const maxY=Math.min(target.height-1,Math.ceil(Math.max(a[1],b[1],c[1])));
  for(let y=minY;y<=maxY;y++) for(let x=minX;x<=maxX;x++) {
    const u=edge(b,c,x+.5,y+.5)/area;
    const v=edge(c,a,x+.5,y+.5)/area;
    const w=1-u-v;
    if(Math.min(u,v,w)<-1e-10) continue;
    const sx=Math.max(0,Math.min(texture.width-1,u*source[0][0]+v*source[1][0]+w*source[2][0]-.5));
    const sy=Math.max(0,Math.min(texture.height-1,u*source[0][1]+v*source[1][1]+w*source[2][1]-.5));
    const x0=Math.floor(sx),y0=Math.floor(sy),tx=sx-x0,ty=sy-y0;
    const colors=[0,0,0];
    let alpha=0;
    for(let row=0;row<2;row++) for(let col=0;col<2;col++) {
      const weight=(col?tx:1-tx)*(row?ty:1-ty);
      const pixel=4*(Math.min(texture.height-1,y0+row)*texture.width+Math.min(texture.width-1,x0+col));
      const coverage=texture.data[pixel+3]*weight;
      alpha+=coverage;
      for(let channel=0;channel<3;channel++) colors[channel]+=texture.data[pixel+channel]*coverage;
    }
    const to=4*(y*target.width+x);
    for(let channel=0;channel<3;channel++) target.data[to+channel]=alpha?colors[channel]/alpha:0;
    target.data[to+3]=alpha;
  }
}
