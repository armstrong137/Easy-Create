# 代码地图（CODE MAP）

> ⚠️ 本文件由 `scripts/update_code_map.sh` 自动生成，请勿手工编辑。
> 生成时间：2026-07-18 14:35:07　对应提交：1e4f78b 之后的工作区状态

## 一、索引状态

```

CodeGraph Status

Project: C:\Users\yunhao.zhou1\Desktop\Easy Create

Index Statistics:
  Files:     106
  Nodes:     4,043
  Edges:     19,034
  DB Size:   20.38 MB
  Backend:   node:sqlite - built-in (full WAL)
  Journal:   wal

Nodes by Kind:
  method          1,555
  function        1,372
  class           470
  import          324
  constant        193
  file            98
  variable        14
  type_alias      12
  enum_member     2
  namespace       2
  enum            1

Files by Language:
  dart            68
  javascript      10
  kotlin          8
  xml             6
  properties      4
  yaml            4
  swift           3
  typescript      2
  c               1

[OK] Index is up to date

```

## 二、项目文件结构（含符号统计）

```

Project Structure (106 files):

|-- .agents
|   `-- skills
|       |-- brainstorming
|       |   `-- scripts
|       |       |-- helper.js (javascript, 9 symbols)
|       |       `-- server.cjs (javascript, 75 symbols)
|       |-- systematic-debugging
|       |   `-- condition-based-waiting-example.ts (typescript, 6 symbols)
|       `-- writing-skills
|           `-- render-graphs.js (javascript, 8 symbols)
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
|-- assets
|   `-- planet_scene
|       `-- three.min.js (javascript, 1680 symbols)
|-- experiments
|   `-- planet_3d_demo
|       |-- android
|       |   |-- app
|       |   |   |-- src
|       |   |   |   |-- debug
|       |   |   |   |   `-- AndroidManifest.xml (xml, 1 symbols)
|       |   |   |   |-- main
|       |   |   |   |   |-- kotlin
|       |   |   |   |   |   `-- com
|       |   |   |   |   |       `-- example
|       |   |   |   |   |           `-- planet_3d_demo
|       |   |   |   |   |               `-- MainActivity.kt (kotlin, 4 symbols)
|       |   |   |   |   `-- AndroidManifest.xml (xml, 1 symbols)
|       |   |   |   `-- profile
|       |   |   |       `-- AndroidManifest.xml (xml, 1 symbols)
|       |   |   `-- build.gradle.kts (kotlin, 1 symbols)
|       |   |-- gradle
|       |   |   `-- wrapper
|       |   |       `-- gradle-wrapper.properties (properties, 0 symbols)
|       |   |-- build.gradle.kts (kotlin, 2 symbols)
|       |   |-- gradle.properties (properties, 0 symbols)
|       |   `-- settings.gradle.kts (kotlin, 1 symbols)
|       |-- assets
|       |   `-- web
|       |       |-- OrbitControls.js (javascript, 48 symbols)
|       |       `-- three.min.js (javascript, 1680 symbols)
|       |-- lib
|       |   `-- main.dart (dart, 19 symbols)
|       |-- analysis_options.yaml (yaml, 0 symbols)
|       `-- pubspec.yaml (yaml, 0 symbols)
|-- ios
|   |-- Runner
|   |   |-- AppDelegate.swift (swift, 6 symbols)
|   |   |-- Runner-Bridging-Header.h (c, 1 symbols)
|   |   `-- SceneDelegate.swift (swift, 4 symbols)
|   `-- RunnerTests
|       `-- RunnerTests.swift (swift, 6 symbols)
|-- lib
|   |-- core
|   |   |-- app_keys.dart (dart, 4 symbols)
|   |   |-- carpet_constants.dart (dart, 10 symbols)
|   |   |-- chinese_numbers.dart (dart, 5 symbols)
|   |   |-- creative_energy.dart (dart, 15 symbols)
|   |   |-- inspiration_font.dart (dart, 5 symbols)
|   |   `-- spin_inertia.dart (dart, 9 symbols)
|   |-- data
|   |   |-- database
|   |   |   |-- app_database.dart (dart, 9 symbols)
|   |   |   |-- app_database.g.dart (dart, 247 symbols)
|   |   |   `-- tables.dart (dart, 26 symbols)
|   |   |-- repositories
|   |   |   |-- inspiration_repository.dart (dart, 15 symbols)
|   |   |   `-- novel_repository.dart (dart, 24 symbols)
|   |   `-- providers.dart (dart, 8 symbols)
|   |-- domain
|   |   `-- entities
|   |       `-- outline_chapter.dart (dart, 3 symbols)
|   |-- presentation
|   |   |-- home
|   |   |   |-- planet_scene
|   |   |   |   |-- planet_scene_io.dart (dart, 14 symbols)
|   |   |   |   |-- planet_scene_web.dart (dart, 15 symbols)
|   |   |   |   |-- planet_scene.dart (dart, 6 symbols)
|   |   |   |   `-- scene_server.dart (dart, 11 symbols)
|   |   |   |-- home_page.dart (dart, 92 symbols)
|   |   |   |-- orbiting_inspirations.dart (dart, 20 symbols)
|   |   |   |-- planet_view.dart (dart, 19 symbols)
|   |   |   |-- saturn_rings_painter.dart (dart, 12 symbols)
|   |   |   |-- starfield_motion.dart (dart, 7 symbols)
|   |   |   `-- starfield.dart (dart, 31 symbols)
|   |   |-- outline
|   |   |   |-- label_layout.dart (dart, 12 symbols)
|   |   |   |-- magic_carpet.dart (dart, 67 symbols)
|   |   |   |-- magic_tree_model.dart (dart, 46 symbols)
|   |   |   |-- outline_page.dart (dart, 60 symbols)
|   |   |   `-- scroll_carpet.dart (dart, 38 symbols)
|   |   |-- section
|   |   |   |-- card_deck_sheet.dart (dart, 19 symbols)
|   |   |   |-- card_editor_page.dart (dart, 15 symbols)
|   |   |   |-- inspiration_card.dart (dart, 11 symbols)
|   |   |   `-- section_page.dart (dart, 28 symbols)
|   |   |-- settings
|   |   |   `-- settings_page.dart (dart, 14 symbols)
|   |   `-- shared
|   |       |-- quick_capture
|   |       |   |-- capture_button_prefs.dart (dart, 9 symbols)
|   |       |   |-- capture_sheet_style.dart (dart, 12 symbols)
|   |       |   |-- quick_capture_layer.dart (dart, 27 symbols)
|   |       |   |-- speech_service.dart (dart, 9 symbols)
|   |       |   |-- text_capture_sheet.dart (dart, 12 symbols)
|   |       |   `-- voice_capture_sheet.dart (dart, 16 symbols)
|   |       `-- soft_toast.dart (dart, 11 symbols)
|   `-- main.dart (dart, 14 symbols)
|-- scripts
|   |-- e2e_probe.dart (dart, 12 symbols)
|   `-- serve_web.dart (dart, 4 symbols)
|-- test
|   |-- core
|   |   |-- chinese_numbers_test.dart (dart, 4 symbols)
|   |   |-- creative_energy_test.dart (dart, 4 symbols)
|   |   |-- inspiration_font_test.dart (dart, 4 symbols)
|   |   `-- spin_inertia_test.dart (dart, 7 symbols)
|   |-- data
|   |   |-- app_database_config_test.dart (dart, 4 symbols)
|   |   `-- repositories_test.dart (dart, 9 symbols)
|   |-- presentation
|   |   |-- home_loading_regression_test.dart (dart, 4 symbols)
|   |   |-- home_page_test.dart (dart, 20 symbols)
|   |   |-- magic_carpet_test.dart (dart, 18 symbols)
|   |   |-- magic_tree_model_test.dart (dart, 15 symbols)
|   |   |-- orbiting_inspirations_test.dart (dart, 11 symbols)
|   |   |-- outline_page_test.dart (dart, 26 symbols)
|   |   |-- planet_scene_touch_config_test.dart (dart, 5 symbols)
|   |   |-- quick_capture_test.dart (dart, 16 symbols)
|   |   |-- section_page_test.dart (dart, 24 symbols)
|   |   |-- starfield_motion_test.dart (dart, 6 symbols)
|   |   |-- starfield_test.dart (dart, 7 symbols)
|   |   `-- voice_capture_test.dart (dart, 22 symbols)
|   `-- tools
|       `-- web_serve_test.dart (dart, 6 symbols)
|-- tool
|   |-- crop_sprite.dart (dart, 4 symbols)
|   |-- knockout_bg.dart (dart, 4 symbols)
|   |-- planet_texture_gen.dart (dart, 18 symbols)
|   |-- probe_alpha.dart (dart, 4 symbols)
|   `-- stage_convert.dart (dart, 4 symbols)
|-- web
|   `-- drift_worker.js (javascript, 666 symbols)
|-- analysis_options.yaml (yaml, 0 symbols)
`-- pubspec.yaml (yaml, 0 symbols)

```

## 三、使用说明（给接力开发的智能体）

- 查看某符号的定义与调用链：`codegraph node <符号名>`
- 探索某功能区域：`codegraph explore "<自然语言描述>"`
- 修改前评估影响面：`codegraph impact <符号名>`
- 查找调用方 / 被调用方：`codegraph callers <符号名>` / `codegraph callees <符号名>`

详细工作流规则见 `.claude/skills/codegraph-map/SKILL.md`。
