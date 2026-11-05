// 独立样件的枝架：各枝的长度、粗度和出生时序分别计算。
export function continuousTreeCurves(age) {
  const point = (p,t) => [0,1].map(axis => (1-t)**3*p[0][axis]
    +3*(1-t)**2*t*p[1][axis]+3*(1-t)*t*t*p[2][axis]+t**3*p[3][axis]);
  const trunk = {p:[[280,620],[280-20*age,590-110*age],[280+5*age,540-240*age],[280-2*age,510-370*age]],
    r:[8+38*age,2.8+11.2*age],kind:'trunk'};
  const curves=[trunk];
  for(const [side,reach,depth] of [[-1,1,0],[1,.85,4],[-1,.35,13]]) {
    const end=[280+side*(12+105*age)*reach,628+22*age+depth*age];
    curves.push({p:[[280,620],[280+side*(6+22*age),622],[end[0]-side*15*age,end[1]-2],end],
      r:[5+19*age,1.2+3*age],kind:'root'});
  }
  for(const [side,level,length,rise,birth] of [
    [-1,.36,177,86,0],[1,.47,180,96,.05],[-1,.66,157,89,.15],
    [1,.77,142,70,.24],[-1,.91,73,70,.32],[1,.91,66,61,.39],
  ]) {
    const growth=Math.max(0,Math.min(1,(age-birth)/(1-birth)));
    const base=point(trunk.p,level),reach=8+(length-8)*growth;
    const end=[base[0]+side*reach,base[1]-(5+(rise-5)*growth)];
    curves.push({p:[base,[base[0]+side*reach*.32,base[1]-growth*10],
      [end[0]-side*reach*.25,end[1]+rise*.23*growth],end],
      r:[2.5+(20*(1-level)+2.5)*growth,.7+2.55*growth],kind:'branch',growth});
  }
  const support=curves[5],anchor=point(support.p,.8);
  const frameGrowth=Math.max(0,Math.min(1,(age-.55)/.45));
  const half=.3+17*frameGrowth,high=.6+53*frameGrowth;
  const foot=[anchor[0],anchor[1]-support.r[1]];
  for(const side of [-1,1]) curves.push({
    p:[foot,[foot[0]+side*half*1.4,foot[1]-high*.05],
      [foot[0]+side*half*1.4,foot[1]-high*1.13],[foot[0],foot[1]-high]],
    r:[.2+4.8*frameGrowth,.2+3.8*frameGrowth],kind:'frame',growth:frameGrowth,
  });
  return curves;
}
