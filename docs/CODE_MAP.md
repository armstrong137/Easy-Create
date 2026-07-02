# 代码地图（CODE MAP）

> ⚠️ 本文件由 `scripts/update_code_map.sh` 自动生成，请勿手工编辑。
> 生成时间：2026-07-02 18:24:51　对应提交：fc9754a 之后的工作区状态

## 一、索引状态

```

CodeGraph Status

Project: /home/claude/project

Index Statistics:
  Files:     4
  Nodes:     98
  Edges:     236
  DB Size:   0.49 MB
  Backend:   node:sqlite - built-in (full WAL)
  Journal:   wal

Nodes by Kind:
  function        55
  constant        30
  variable        7
  file            4
  import          2

Files by Language:
  javascript      3
  typescript      1

[OK] Index is up to date

```

## 二、项目文件结构（含符号统计）

```

Project Structure (4 files):

`-- .claude
    `-- skills
        |-- brainstorming
        |   `-- scripts
        |       |-- helper.js (javascript, 9 symbols)
        |       `-- server.cjs (javascript, 75 symbols)
        |-- systematic-debugging
        |   `-- condition-based-waiting-example.ts (typescript, 6 symbols)
        `-- writing-skills
            `-- render-graphs.js (javascript, 8 symbols)

```

## 三、使用说明（给接力开发的智能体）

- 查看某符号的定义与调用链：`codegraph node <符号名>`
- 探索某功能区域：`codegraph explore "<自然语言描述>"`
- 修改前评估影响面：`codegraph impact <符号名>`
- 查找调用方 / 被调用方：`codegraph callers <符号名>` / `codegraph callees <符号名>`

详细工作流规则见 `.claude/skills/codegraph-map/SKILL.md`。
