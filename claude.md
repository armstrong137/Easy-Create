# claude.md — 项目设计目标与开发架构

> 维护规则（用户规定）：软件开发架构或设计目标出现变化时，必须同步维护本文件，
> 保证描述与最新代码一致。所有对话与代码注释使用中文。

## 一、软件设计目标

为**小说家**打造的手机 App（iOS + Android，Flutter 一套代码），核心价值：

1. **小说大纲整理**：以"黑白铅笔树"可视化组织 章 → 节 两级大纲
2. **灵感随时记录**：任何界面双按钮（语音/文字）速记，灵感进入全局共享池
3. **写作无上限**：小节内灵感卡片字数不限，可直接写完整小说
4. **创作能量可视化**：首页真实 3D 星球（一球一书），灵感越多星球转得越快、星光越亮

约束：纯本地存储（SQLite），无账号无后端；语音识别用系统本地引擎。

完整交互规格见 `docs/superpowers/specs/2026-07-02-novel-app-design.md`（定稿，唯一权威）。

## 二、软件开发架构

### 技术栈
- 框架：Flutter（Impeller 渲染）
- 状态管理：Riverpod
- 数据库：SQLite via drift（类型安全）
- 语音：speech_to_text 插件（双端系统本地引擎）
- **UI 表现层（改造中，见下）**：
  - 现状（旧实现，仅作过渡与低端机回退，不代表最终目标）：
    FragmentShader 球面贴图星球、静态图星空、2D 卷须枝、
    Container+阴影卡片；魔毯已升级为整条卷轴相框（2026-07-16 方案二整体化定稿：
    参考图抠像成透明中空 scroll_full.png 整体直用，相框覆最上层、挖空处透出
    真羊皮纸+活墨迹文字+活标题牌，整条卷轴悬浮真实地球之上、窗口内滚动，
    见 presentation/outline/scroll_carpet.dart:ScrollFrame）
  - **大纲页魔树：过渡期停画**（2026-08-01 用户定稿，开关
    `magic_tree_model.dart:kMagicTreeArtEnabled = false`）。
    现有 28 帧是"一株成熟大树自下而上揭开"，早期帧只有下半截、没有树冠，
    与目标"完整小树苗长成完整大树"不符（验证器 `not_reveal_sequence`
    实测重叠差 0.826，阈值 20）。停画期间**布局几何照常**：枝丫锚点、章带、
    点击热区、标签全部不受影响，只是不画底图。
    素材路线已定：`scripts/magic_tree_img2img_pipeline.py` 走 img2img 链式
    低重绘生成 28 帧（配方见 docs/Reports/Codex/2026-08-01-*），
    验收用 `scripts/validate_magic_tree_frames.py`（硬防线 `not_reveal_sequence`）。
    新素材到位后把开关改回 true，其余无改动；若各帧内容尺寸变化大，
    需重跑逐帧茎干几何表（脚本量测）。
  - 目标（2026-07-08 用户定稿）：**Flutter 应用壳 + 实时 3D/高级动画表现层**，
    首页星球/星空粒子/魔树/魔毯/卡堆/转场全部升级为真实 3D 或多层伪 3D 场景。
    主清单与执行顺序见 `docs/ui_review/2026-07-08-UI改造第一版清单.md`，
    技术选型结论见 `docs/ui_review/3D架构验证报告.md`

### 数据模型（4 张表）
```
novels        星球=小说   id, title, planet, sort_order, created_at
chapters      章          id, novel_id, title, sort_order
sections      节          id, chapter_id, title, sort_order
inspirations  灵感真身    id, content, created_at, updated_at,
                          section_id(NULL=在魔毯/非空=挂在小节), card_order
```
灵感生命周期由 `section_id` 单字段表达：入池 NULL → 拖入小节写 id → 删卡置回 NULL → 魔毯删除才 DELETE。

### 分层结构
```
lib/
├── core/            主题、常量（转速曲线、魔毯尺寸上下限）
├── data/            drift 数据库、仓库实现
├── domain/          实体 + 用例（业务规则唯一出口）
├── presentation/
│   ├── home/        星空、星球 Shader、环绕灵感轨道、星球切换
│   ├── outline/     铅笔树、玻璃＋号、灵感魔毯
│   ├── section/     信用卡卡堆、卡片包、全文编辑器
│   └── shared/      全局双速记按钮、灵感输入弹层
└── main.dart
```
依赖方向：presentation → domain → data（严禁反向）。

## 三、项目协作规约（摘要，全文见 PROJECT_RULES.md）

1. 对话、思考、代码注释、文档一律中文
2. 本文件在架构/目标变化时必须同步更新
3. 开发进度记录在 `DevelopmentPlan.md`，每完成一步立即更新
4. git 版本管理；**每次 commit 前必须执行 `bash scripts/update_code_map.sh` 更新代码地图**（详见 `.claude/skills/codegraph-map/SKILL.md`）
5. 接手项目先读：PROJECT_RULES.md → 本文件 → DevelopmentPlan.md → docs/CODE_MAP.md
