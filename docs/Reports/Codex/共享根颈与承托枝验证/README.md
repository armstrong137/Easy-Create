# 共享根颈与承托枝验证

复用母子枝的开放前表面，在母干底部左右各扩展一条粗根。两条根和一条侧枝的基排直接使用母干顶点索引。实际二进制共检查 24 条共享边，整个前表面连通且无孔。2176 个三角形在三个插值区间均未发现翻面。旧单枝数据仍通过原有拓扑审计。

固定相机近景可读出主干与粗根的连接，但底边仍平切，根像左右两翼，材质方向在根枝接合处仍有变化。当前没有牌框与纸面，需要沿共享枝条补一个真实承托样件，随后与完整根系及冠层一并复审。此局部证据不计入完整 A2 轮次。

通过 Python 运行 branch_development_proof.py --root-collar，随后对 build/qa/shared-root-collar-proof 运行 audit-branch-development.mjs 与 audit-cage-intervals.mjs，再用 capture-volume-2d.mjs --root-collar 采集独立浏览器。使用普通 Python 可直接生成浏览器证据所需网格，Blender 可额外导出可编辑网格。
