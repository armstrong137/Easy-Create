# 参考表皮枝牌接合

参考表皮接入两个木框及其开孔纸面。框和纸面均随源网格挂点移动。浏览器初态零牌、成熟两牌，近景文字可读，框端与木体重叠，但深色木框与主干的纹理过渡仍明显。四个插值区间通过翻面审计。冠簇、完整树苗与实际命中仍待验证。

[近景](junction-close.png) · [连续实渲](growth.webm)

先用 Blender 执行 development_tree_proof.py -- --round2 生成木框来源，再运行 build-reference-wood-skin.mjs 和 capture-volume-2d.mjs --reference-wood-skin。
