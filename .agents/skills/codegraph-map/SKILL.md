---
name: codegraph-map
description: "代码地图维护 skill。每次代码修改完成后、执行 git commit 之前，必须调用本 skill 更新代码地图，保证 docs/CODE_MAP.md 与最新代码一致。任何智能体接手项目时，应先阅读 docs/CODE_MAP.md 了解代码全貌，而不是重新遍历审查所有源码。"
---

# 代码地图维护（CodeGraph Map）

## 目的

本项目使用 [CodeGraph](https://github.com/colbymchenry/codegraph) 生成"代码地图"，
让任何智能体接力开发时，无需重新逐文件审查代码，即可掌握：

- 项目有哪些模块 / 文件 / 符号（函数、类）
- 符号之间的调用关系与依赖关系
- 每次变更影响了哪些部分

代码地图有两层：

1. **机器可查询层**：`.codegraph/codegraph.db`（SQLite 知识图谱，由 tree-sitter 解析生成）
2. **人类/智能体可读层**：`docs/CODE_MAP.md`（从图谱导出的中文摘要文档，纳入 git 版本管理）

## 强制工作流：commit 前更新地图

每次修改代码后，在 `git commit` 之前，**必须**依次执行：

```bash
# 第 1 步：同步索引（增量更新知识图谱）
codegraph sync   # 若命令不存在 sync 子命令，则用 codegraph init 重建

# 第 2 步：重新生成人类可读的代码地图
bash scripts/update_code_map.sh

# 第 3 步：把地图文件一并纳入本次提交
git add docs/CODE_MAP.md
git commit -m "..."
```

`scripts/update_code_map.sh` 会调用 `codegraph` 的查询能力，导出以下内容到 `docs/CODE_MAP.md`：

- 项目文件清单与统计（节点数 / 边数）
- 各文件包含的主要符号（函数、类、方法）
- 模块间依赖关系概览
- 最后更新时间与对应的 git 提交

## 查询代码地图（开发过程中随时可用）

```bash
codegraph query "<自然语言或符号名>"   # 搜索符号、查看调用关系
codegraph explore <符号名>             # 探索某符号的上下游
```

修改代码前，先用查询确认影响范围，再动手。

## 红线规则

- ❌ 禁止在未更新代码地图的情况下 commit 代码变更
- ❌ 禁止手工编辑 docs/CODE_MAP.md（它是生成产物，手改会被覆盖）
- ✅ 纯文档类改动（不涉及源码）可以跳过第 1、2 步
