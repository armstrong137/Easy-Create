# 代码地图（CODE MAP）

> ⚠️ 本文件由 `scripts/update_code_map.sh` 自动生成，请勿手工编辑。
> 生成时间：2026-07-02 13:42:06　对应提交：67cf5e3 之后的工作区状态

## 一、索引状态

```

CodeGraph Status

Project: C:\Users\yunhao.zhou1\Desktop\Easy Create

Index Statistics:
  Files:     21
  Nodes:     136
  Edges:     268
  DB Size:   0.54 MB
  Backend:   node:sqlite - built-in (full WAL)
  Journal:   wal

Nodes by Kind:
  function        57
  constant        31
  file            17
  import          14
  variable        7
  class           5
  method          4
  namespace       1

Files by Language:
  kotlin          4
  javascript      3
  swift           3
  xml             3
  dart            2
  properties      2
  yaml            2
  c               1
  typescript      1

[OK] Index is up to date

```

## 二、项目文件结构（含符号统计）

```

Project Structure (21 files):

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
