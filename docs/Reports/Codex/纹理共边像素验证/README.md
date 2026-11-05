# 纹理共边像素验证

纹理三角采用统一像素中心覆盖规则，正反两种面绕序的方形共边验证均无透明像素。侧枝近景的三角细缝消失，但低分辨率软件取样在放大时明显像素化。旧样件仅用作绘制回归，整树候选轮次不变，A2 未通过。见 docs/Reports/Codex/纹理共边像素验证。

运行 node tools/tree_scene/scripts/probe-root-collar-asset.mjs --assembly --capture --round-two --raster 复现。后续需在实际目标分辨率取样并使用插值滤波，绘制修正不能解决枝干几何接合与材质风格问题。
