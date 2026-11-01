import assert from 'node:assert/strict';
import test from 'node:test';
import { repairCanvasKitPathFillType } from '../../../web/canvaskit_path_compat.mjs';

function fakeKit(mode) {
  const live = new Set();
  let next = 0;
  class PathBuilder {
    constructor() { this.id = ++next; live.add(this.id); }
    isAliasOf(other) { return this.id === other.id; }
    delete() { assert.ok(live.delete(this.id), '不能重复删除原生路径'); }
    setFillType(value) {
      assert.ok(live.has(this.id));
      this.fill = value;
      if (mode === 'copy') {
        const copy = new PathBuilder();
        copy.fill = value;
        return copy;
      }
      if (mode === 'alias') return { isAliasOf: other => other.id === this.id,
        delete() { assert.fail('不能删除指向原路径的同源句柄'); } };
      return mode === 'void' ? undefined : this;
    }
  }
  return { PathBuilder, FillType: { Winding: 0 }, live };
}

test('旧复制实现逐次回收副本，原路径与填充规则保持有效', () => {
  const kit = fakeKit('copy');
  assert.equal(repairCanvasKitPathFillType(kit), true);
  assert.equal(kit.live.size, 0, '探测也必须释放临时路径');
  const path = new kit.PathBuilder();
  for (let index = 0; index < 100; index++) {
    assert.equal(path.setFillType(index % 2), path);
    assert.equal(path.fill, index % 2);
    assert.equal(kit.live.size, 1);
  }
  assert.equal(repairCanvasKitPathFillType(kit), false, '重复加载不能再次包裹');
  path.delete();
  assert.equal(kit.live.size, 0);
});
for (const mode of ['reference', 'alias', 'void']) {
  test('已修复或无副本实现保留原方法：' + mode, () => {
    const kit = fakeKit(mode);
    const original = kit.PathBuilder.prototype.setFillType;
    assert.equal(repairCanvasKitPathFillType(kit), false);
    assert.equal(kit.PathBuilder.prototype.setFillType, original);
    assert.equal(kit.live.size, 0);
  });
}
test('没有CanvasKit时不影响其他渲染器', () => {
  assert.equal(repairCanvasKitPathFillType(undefined), false);
});
