// 旧CanvasKit的setFillType返回独立副本；调用方忽略返回值时副本不会自动释放。
// 上游0.42.0已修复：https://github.com/google/skia/blob/main/modules/canvaskit/CHANGELOG.md
export function repairCanvasKitPathFillType(kit) {
  const prototype = kit?.PathBuilder?.prototype;
  if (typeof prototype?.setFillType !== 'function' ||
      typeof prototype.isAliasOf !== 'function' || kit?.FillType?.Winding === undefined) return false;
  const original = prototype.setFillType;
  const probe = new kit.PathBuilder();
  let result;
  let copied;
  try {
    result = original.call(probe, kit.FillType.Winding);
    copied = result && result !== probe && !result.isAliasOf(probe);
  } finally {
    if (result && result !== probe && !result.isAliasOf(probe)) result.delete();
    probe.delete();
  }
  if (!copied) return false;
  prototype.setFillType = function(...args) {
    const copy = original.apply(this, args);
    if (copy && copy !== this && !copy.isAliasOf(this)) copy.delete();
    return this;
  };
  return true;
}
