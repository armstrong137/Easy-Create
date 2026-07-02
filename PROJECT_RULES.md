# 项目协作约定（所有智能体必读）

本文件记录本项目的开发协作规则。**任何智能体接手本项目前必须先阅读本文件。**

## 一、语言约定

1. 与用户的所有对话使用**中文**（包括思考过程）
2. 所有**代码注释使用中文**
3. 所有项目文档（claude.md、DevelopmentPlan.md、CODE_MAP.md 等）使用中文

## 二、文档维护约定

| 文件 | 建立时机 | 内容 | 维护规则 |
|------|---------|------|---------|
| `claude.md` | 软件架构设计**确定后**建立 | 软件设计目标 + 开发架构 | 架构或目标变化时必须同步更新，保证与最新代码一致 |
| `DevelopmentPlan.md` | 开发计划**确定后**建立 | 开发共分几个阶段、每阶段几步、当前进行到第几步 | **每完成一步立即更新**，方便其他智能体接力 |
| `docs/CODE_MAP.md` | 已建立（自动生成） | 代码地图：文件结构、符号、依赖关系 | 每次 commit 前由脚本自动重新生成，**禁止手工编辑** |

> 当前状态：软件需求尚未确定，claude.md 与 DevelopmentPlan.md 尚未建立。
> 下一步：使用 brainstorming skill 与用户理清需求边界 → 确定架构 → 建立上述两个文件。

## 三、版本管理约定

- 使用 **git** 进行版本管理，主分支为 `main`
- 每完成一个有意义的改动单元即 commit，提交信息使用中文

## 四、Skills 使用约定

项目级 skills 位于 `.claude/skills/`，包含两套：

### 1. Superpowers（来源：obra/superpowers）
- **brainstorming**：⭐ 开始任何开发前，先用它与用户对话理清需求边界，产出设计文档并获用户确认
- writing-plans：设计确认后，拆解为细粒度实现计划
- test-driven-development / systematic-debugging / code-review 等：开发阶段按需触发
- 详见各 skill 目录下的 SKILL.md

### 2. codegraph-map（自建，包装 CodeGraph 工具）
- **每次修改代码后、`git commit` 之前，必须执行：**
  ```bash
  bash scripts/update_code_map.sh   # 同步索引 + 重新生成 docs/CODE_MAP.md
  git add docs/CODE_MAP.md          # 地图随代码一起提交
  ```
- 接手项目时先读 `docs/CODE_MAP.md` 了解代码全貌，不要盲目遍历源码
- 开发中可用 `codegraph query / explore / impact / callers / callees` 查询代码关系
- 完整规则见 `.claude/skills/codegraph-map/SKILL.md`

## 五、标准工作流（总览）

```
需求模糊 → brainstorming skill 理清边界 → 用户确认设计
        → 建立 claude.md（架构）+ DevelopmentPlan.md（计划）
        → 按计划逐步开发（每步：写代码 → 更新代码地图 → commit → 更新 DevelopmentPlan.md）
        → 架构变化时同步维护 claude.md
```
