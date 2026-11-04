export function createRootSurface(age, top = Infinity, thickerRoots = false) {
  const roots = [[-2.89, 1.31], [-2.16, 1.45], [-1.21, 1.28], [-.31, 1.54], [1.36, .75]];
  const extent = .58 + .42 * age;
  // 截面由中心宽度及定向根脊定义，根之间直接留出凹部。
  return function surface(x, y, z) {
    const height = Math.max(0, z);
    const centerX = .11 * Math.sin(height * 1.9);
    const px = x - centerX;
    const py = y * 1.10;
    const angle = Math.atan2(py, px);
    const radial = Math.hypot(px, py);
    let ridge = 0;
    for (const [direction, length] of roots) {
      const alignment = Math.max(0, Math.cos(angle - direction));
      ridge = Math.max(ridge, length * alignment ** 22);
    }
    const profile = (.35 + .20 * Math.exp(-height * 2.6)) * extent;
    const falloff = thickerRoots ? 2.35 : 3.2;
    const perimeter = profile + ridge * Math.exp(-height * falloff) * extent;
    // 入口随深度错开并收窄，两个空腔不共用同一拱高。
    const front = Math.max(0, -y);
    const leftCavity = Math.hypot((x + .46 * extent + .14 * y) / (.16 + .08 * front),
      (y + .68 * extent) / .49, (z - .015) / (.12 + .085 * front)) - 1;
    const rightCavity = Math.hypot((x - .51 * extent - .22 * y) / (.13 + .10 * front),
      (y + .56 * extent) / .43, (z - .025) / (.10 + .05 * front)) - 1;
    return Math.max(radial - perimeter, -z, z - top,
      -.23 * Math.min(leftCavity, rightCavity));
  };
}
