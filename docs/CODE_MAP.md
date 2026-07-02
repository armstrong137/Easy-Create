# 代码地图（CODE MAP）

> ⚠️ 本文件由 `scripts/update_code_map.sh` 自动生成，请勿手工编辑。
> 生成时间：2026-07-02 13:45:16　对应提交：ae3bb60 之后的工作区状态

## 一、索引状态

```

CodeGraph Status

Project: C:\Users\yunhao.zhou1\Desktop\Easy Create

Index Statistics:
  Files:     24
  Nodes:     407
  Edges:     700
  DB Size:   0.95 MB
  Backend:   node:sqlite - built-in (full WAL)
  Journal:   wal

Nodes by Kind:
  method          194
  function        57
  constant        54
  class           44
  file            20
  import          18
  type_alias      12
  variable        7
  namespace       1

Files by Language:
  dart            5
  kotlin          4
  javascript      3
  swift           3
  xml             3
  properties      2
  yaml            2
  c               1
  typescript      1

[OK] Index is up to date

```

## 二、项目文件结构（含符号统计）

```

Project Structure (24 files):

|-- .claude
|   `-- skills
|       |-- brainstorming
|       |   `-- scripts
|       |       |-- helper.js (javascript, 9 symbols)
|       |       `-- server.cjs (javascript, 75 symbols)
|       |-- systematic-debugging
|       |   `-- condition-based-waiting-example.ts (typescript, 6 symbols)
|       `-- writing-skills
|           `-- render-graphs.js (javascript, 8 symbols)
|-- android
|   |-- app
|   |   |-- src
|   |   |   |-- debug
|   |   |   |   `-- AndroidManifest.xml (xml, 1 symbols)
|   |   |   |-- main
|   |   |   |   |-- kotlin
|   |   |   |   |   `-- com
|   |   |   |   |       `-- easycreate
|   |   |   |   |           `-- novel_app
|   |   |   |   |               `-- MainActivity.kt (kotlin, 4 symbols)
|   |   |   |   `-- AndroidManifest.xml (xml, 1 symbols)
|   |   |   `-- profile
|   |   |       `-- AndroidManifest.xml (xml, 1 symbols)
|   |   `-- build.gradle.kts (kotlin, 1 symbols)
|   |-- gradle
|   |   `-- wrapper
|   |       `-- gradle-wrapper.properties (properties, 0 symbols)
|   |-- build.gradle.kts (kotlin, 2 symbols)
|   |-- gradle.properties (properties, 0 symbols)
|   `-- settings.gradle.kts (kotlin, 1 symbols)
|-- ios
|   |-- Runner
|   |   |-- AppDelegate.swift (swift, 6 symbols)
|   |   |-- Runner-Bridging-Header.h (c, 1 symbols)
|   |   `-- SceneDelegate.swift (swift, 4 symbols)
|   `-- RunnerTests
|       `-- RunnerTests.swift (swift, 6 symbols)
|-- lib
|   |-- data
|   |   `-- database
|   |       |-- app_database.dart (dart, 9 symbols)
|   |       |-- app_database.g.dart (dart, 237 symbols)
|   |       `-- tables.dart (dart, 25 symbols)
|   `-- main.dart (dart, 5 symbols)
|-- test
|   `-- widget_test.dart (dart, 5 symbols)
|-- analysis_options.yaml (yaml, 0 symbols)
`-- pubspec.yaml (yaml, 0 symbols)

```

## 三、使用说明（给接力开发的智能体）

- 查看某符号的定义与调用链：`codegraph node <符号名>`
- 探索某功能区域：`codegraph explore "<自然语言描述>"`
- 修改前评估影响面：`codegraph impact <符号名>`
- 查找调用方 / 被调用方：`codegraph callers <符号名>` / `codegraph callees <符号名>`

详细工作流规则见 `.claude/skills/codegraph-map/SKILL.md`。
