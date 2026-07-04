# AGENTS.md — 项目设计目标与开发架构

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
- 3D 星球：FragmentShader 球面贴图 + NASA 公有领域真实摄影纹理
- 复杂动效：Rive（灵感魔毯）+ CustomPainter（铅笔树）
- 语音：speech_to_text 插件（双端系统本地引擎）

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
4. git 版本管理；**每次 commit 前必须执行 `bash scripts/update_code_map.sh` 更新代码地图**（详见 `.Codex/skills/codegraph-map/SKILL.md`）
5. 接手项目先读：PROJECT_RULES.md → 本文件 → DevelopmentPlan.md → docs/CODE_MAP.md
