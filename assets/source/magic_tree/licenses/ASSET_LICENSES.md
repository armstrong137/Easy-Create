# 实时 3D 魔树资产授权清单

## 项目生成资产

本目录下的正式母版、候选效果图、叶片图集、树皮源图和土壤源图均由本项目在 2026-08-10 使用 OpenAI 图像生成工具生成或基于这些生成结果进行本地去色键处理，没有直接复制第三方图片素材。

适用文件：

- `references/*.png`
- `textures_source/*.png`

本地派生处理：

- `textures_source/leaf_atlas_rgba.png` 由 `leaf_atlas_chroma.png` 使用 Codex imagegen skill 附带的 `remove_chroma_key.py` 去除 `#FF00FF` 背景生成。

## 使用约束

- 仅用于 Easy Create 项目的设计、建模、纹理制作、测试和产品发布。
- 不将生成图声明为现实摄影、扫描或第三方艺术家的原作。
- 最终发布仍应遵守生成工具账号对应的服务条款和项目所在地法规。
- 后续引入任何第三方 HDRI、字体、模型、纹理或插件资产时，必须在本文件追加来源、作者、许可、下载日期和产品内用途；未登记的第三方资产不得进入发布包。

## 当前第三方资产

无。

## 2026-11-02连续木体与横展冠层

textures_source/continuous_wood_core_v1.png及canopy_boughs_v1.png使用imagegen技能、内置image_gen生成，批准的项目树形参考仅用于风格/解剖输入，没有直接复制第三方资产。保留源透明通道、旧版本与实际提示词；各同名.md和.prompt.txt登记哈希、范围及约束。前者是无叶的一体根颈/主肩枝局部，后者是四件局部枝叶，不能当整树阶段播放。当前仅独立候选，未进入正式应用。

## 2026-11-02统一局部构件与左章牌

textures_source/illustrated_components_v1.png及illustrated_frame_left_v1.png使用imagegen技能及内置image_gen生成，原透明通道保留，源提示词与范围见各自同名.md。前者是六件局部图集，后者为原光向左牌，没有整树阶段图。实际图集区域由透明连通分析供网格选区，未修改源PNG像素；两图均未进入正式运行包。

## 2026-11-02局部木质构件搭接边

textures_source/fork_component_lap_v2.png通过imagegen技能及内置image_gen编辑已有项目资产，原透明通道保留，旧版本不覆盖；提示词、原始输出、实际改动范围及哈希见同名.md。仅用于局部骨骼网格对接验证，不是整树阶段图。

## 2026-11-02局部木质分叉源

textures_source/fork_component_source_v1.png由imagegen技能及内置image_gen生成，原透明通道保留；提示词、哈希与使用范围见同名.md。仅作为新的局部骨骼网格实验源，不是整树阶段图，也没有进入正式运行包。

## 2026-11-01第二轮局部叶材质

textures_source/leaf_matte_atlas_v2.png由Codex内置image_gen按imagegen技能生成，透明背景保留，四种局部单叶用于独立连续网格样件；提示词与用途见同名.md。未引入第三方模型或图库，不覆盖旧资产，也不代表整树视觉验收通过。
