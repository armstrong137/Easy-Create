# 代码地图（CODE MAP）

> ⚠️ 本文件由 `scripts/update_code_map.sh` 自动生成，请勿手工编辑。
> 生成时间：2026-10-30 21:54:29　对应提交：08703dd 之后的工作区状态

## 一、索引状态

```

CodeGraph Status

Project: C:\Users\Armstrong\Desktop\Easy Create

Index Statistics:
  Files:     199
  Nodes:     5,323
  Edges:     22,426
  DB Size:   26.00 MB
  Backend:   node:sqlite - built-in (full WAL)
  Journal:   wal

Nodes by Kind:
  method          1,827
  function        1,572
  import          692
  class           522
  constant        326
  file            191
  variable        144
  enum_member     25
  type_alias      16
  enum            6
  namespace       2

Files by Language:
  dart            111
  javascript      45
  python          15
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

Project Structure (199 files):

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
|-- 电脑迁移包
|   `-- 收集迁移资料.py (python, 38 symbols)
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
|   |   |-- content_font.dart (dart, 9 symbols)
|   |   |-- creative_energy.dart (dart, 15 symbols)
|   |   |-- planet_constants.dart (dart, 4 symbols)
|   |   |-- spin_inertia.dart (dart, 9 symbols)
|   |   `-- startup_focus_binding.dart (dart, 7 symbols)
|   |-- data
|   |   |-- database
|   |   |   |-- app_database.dart (dart, 9 symbols)
|   |   |   |-- app_database.g.dart (dart, 247 symbols)
|   |   |   `-- tables.dart (dart, 26 symbols)
|   |   |-- repositories
|   |   |   |-- inspiration_repository.dart (dart, 15 symbols)
|   |   |   `-- novel_repository.dart (dart, 26 symbols)
|   |   `-- providers.dart (dart, 8 symbols)
|   |-- domain
|   |   `-- entities
|   |       `-- outline_chapter.dart (dart, 3 symbols)
|   |-- presentation
|   |   |-- home
|   |   |   |-- planet_scene
|   |   |   |   |-- planet_scene_io.dart (dart, 17 symbols)
|   |   |   |   |-- planet_scene_web.dart (dart, 19 symbols)
|   |   |   |   |-- planet_scene.dart (dart, 6 symbols)
|   |   |   |   `-- scene_server.dart (dart, 11 symbols)
|   |   |   |-- home_page.dart (dart, 98 symbols)
|   |   |   |-- orbiting_inspirations.dart (dart, 20 symbols)
|   |   |   |-- planet_view.dart (dart, 19 symbols)
|   |   |   |-- saturn_rings_painter.dart (dart, 12 symbols)
|   |   |   |-- starfield_motion.dart (dart, 7 symbols)
|   |   |   `-- starfield.dart (dart, 31 symbols)
|   |   |-- outline
|   |   |   |-- tree_scene
|   |   |   |   |-- illustrated_tree_camera_layout.dart (dart, 15 symbols)
|   |   |   |   |-- illustrated_tree_growth.dart (dart, 7 symbols)
|   |   |   |   |-- illustrated_tree_scene.dart (dart, 27 symbols)
|   |   |   |   |-- illustrated_tree_trunk.dart (dart, 10 symbols)
|   |   |   |   |-- illustrated_tree_viewport.dart (dart, 7 symbols)
|   |   |   |   |-- organic_bark.dart (dart, 3 symbols)
|   |   |   |   |-- organic_branch.dart (dart, 23 symbols)
|   |   |   |   |-- organic_tree_camera_layout.dart (dart, 14 symbols)
|   |   |   |   |-- organic_tree_projection.dart (dart, 6 symbols)
|   |   |   |   |-- organic_tree_study.dart (dart, 29 symbols)
|   |   |   |   |-- organic_tree.dart (dart, 13 symbols)
|   |   |   |   |-- sapling_plaque.dart (dart, 5 symbols)
|   |   |   |   |-- tree_scene_controller.dart (dart, 51 symbols)
|   |   |   |   |-- tree_scene_gestures.dart (dart, 17 symbols)
|   |   |   |   |-- tree_scene_io.dart (dart, 18 symbols)
|   |   |   |   |-- tree_scene_protocol.dart (dart, 12 symbols)
|   |   |   |   |-- tree_scene_snapshot.dart (dart, 25 symbols)
|   |   |   |   |-- tree_scene_web.dart (dart, 19 symbols)
|   |   |   |   |-- tree_scene.dart (dart, 2 symbols)
|   |   |   |   `-- tree_standin.dart (dart, 7 symbols)
|   |   |   |-- label_layout.dart (dart, 2 symbols)
|   |   |   |-- magic_carpet.dart (dart, 67 symbols)
|   |   |   |-- outline_controller.dart (dart, 34 symbols)
|   |   |   |-- outline_page.dart (dart, 79 symbols)
|   |   |   `-- scroll_carpet.dart (dart, 38 symbols)
|   |   |-- section
|   |   |   |-- card_deck_sheet.dart (dart, 19 symbols)
|   |   |   |-- card_editor_page.dart (dart, 19 symbols)
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
|   `-- main.dart (dart, 16 symbols)
|-- scripts
|   |-- tests
|   |   `-- test_validate_magic_tree_art_package.py (python, 16 symbols)
|   |-- build_magic_tree_art_asset.py (python, 37 symbols)
|   |-- build_magic_tree_blender.py (python, 47 symbols)
|   |-- capture_standins.py (python, 11 symbols)
|   |-- e2e_probe.dart (dart, 12 symbols)
|   |-- export_magic_tree.py (python, 14 symbols)
|   |-- generate_magic_tree_pbr.py (python, 12 symbols)
|   |-- optimize_magic_tree_glb.py (python, 16 symbols)
|   |-- refine_magic_tree_blend.py (python, 23 symbols)
|   |-- render_magic_tree_art_previews.py (python, 19 symbols)
|   |-- serve_web.dart (dart, 4 symbols)
|   |-- square_standins.py (python, 11 symbols)
|   |-- validate_magic_tree_3d.py (python, 17 symbols)
|   |-- validate_magic_tree_art_package.py (python, 16 symbols)
|   |-- validate_magic_tree_visuals.py (python, 34 symbols)
|   `-- verify_illustrated_tree_growth.dart (dart, 5 symbols)
|-- test
|   |-- core
|   |   |-- chinese_numbers_test.dart (dart, 4 symbols)
|   |   |-- content_font_test.dart (dart, 5 symbols)
|   |   |-- creative_energy_test.dart (dart, 4 symbols)
|   |   |-- spin_inertia_test.dart (dart, 7 symbols)
|   |   `-- startup_focus_binding_test.dart (dart, 9 symbols)
|   |-- data
|   |   |-- app_database_config_test.dart (dart, 4 symbols)
|   |   `-- repositories_test.dart (dart, 9 symbols)
|   |-- presentation
|   |   |-- home_loading_regression_test.dart (dart, 4 symbols)
|   |   |-- home_page_test.dart (dart, 21 symbols)
|   |   |-- illustrated_tree_camera_layout_test.dart (dart, 5 symbols)
|   |   |-- illustrated_tree_trunk_test.dart (dart, 12 symbols)
|   |   |-- illustrated_tree_viewport_test.dart (dart, 16 symbols)
|   |   |-- magic_carpet_test.dart (dart, 18 symbols)
|   |   |-- orbiting_inspirations_test.dart (dart, 11 symbols)
|   |   |-- organic_branch_test.dart (dart, 8 symbols)
|   |   |-- organic_tree_camera_layout_test.dart (dart, 6 symbols)
|   |   |-- organic_tree_projection_test.dart (dart, 6 symbols)
|   |   |-- organic_tree_study_test.dart (dart, 9 symbols)
|   |   |-- organic_tree_test.dart (dart, 19 symbols)
|   |   |-- outline_controller_test.dart (dart, 10 symbols)
|   |   |-- outline_page_test.dart (dart, 36 symbols)
|   |   |-- planet_scene_touch_config_test.dart (dart, 8 symbols)
|   |   |-- quick_capture_test.dart (dart, 16 symbols)
|   |   |-- realtime_tree_single_path_test.dart (dart, 4 symbols)
|   |   |-- sapling_plaque_test.dart (dart, 5 symbols)
|   |   |-- section_page_test.dart (dart, 24 symbols)
|   |   |-- starfield_motion_test.dart (dart, 6 symbols)
|   |   |-- starfield_test.dart (dart, 7 symbols)
|   |   |-- tree_scene_asset_test.dart (dart, 8 symbols)
|   |   |-- tree_scene_browser_test.dart (dart, 5 symbols)
|   |   |-- tree_scene_controller_test.dart (dart, 6 symbols)
|   |   |-- tree_scene_gestures_test.dart (dart, 4 symbols)
|   |   |-- tree_scene_protocol_test.dart (dart, 5 symbols)
|   |   |-- tree_scene_snapshot_test.dart (dart, 8 symbols)
|   |   |-- tree_scene_web_fallback_test.dart (dart, 4 symbols)
|   |   |-- tree_standin_test.dart (dart, 7 symbols)
|   |   `-- voice_capture_test.dart (dart, 22 symbols)
|   |-- tools
|   |   `-- web_serve_test.dart (dart, 6 symbols)
|   `-- test_validate_magic_tree_visuals.py (python, 20 symbols)
|-- tool
|   |-- crop_sprite.dart (dart, 4 symbols)
|   |-- knockout_bg.dart (dart, 4 symbols)
|   |-- planet_texture_gen.dart (dart, 18 symbols)
|   |-- probe_alpha.dart (dart, 4 symbols)
|   `-- stage_convert.dart (dart, 4 symbols)
|-- tools
|   `-- tree_scene
|       |-- scripts
|       |   |-- build.mjs (javascript, 10 symbols)
|       |   |-- capture-state.mjs (javascript, 14 symbols)
|       |   |-- check-browser.mjs (javascript, 22 symbols)
|       |   |-- check-illustrated-outline.mjs (javascript, 39 symbols)
|       |   |-- check-organic-tree.mjs (javascript, 15 symbols)
|       |   |-- check-startup.mjs (javascript, 23 symbols)
|       |   |-- render-branch-study.mjs (javascript, 21 symbols)
|       |   |-- summarize-tree-cpu.mjs (javascript, 19 symbols)
|       |   |-- validate-gltf.mjs (javascript, 7 symbols)
|       |   `-- verify-workbench.mjs (javascript, 8 symbols)
|       |-- src
|       |   |-- BranchStudySurface.js (javascript, 4 symbols)
|       |   |-- BranchSystem.js (javascript, 28 symbols)
|       |   |-- CameraSystem.js (javascript, 13 symbols)
|       |   |-- GrowthProfile.js (javascript, 7 symbols)
|       |   |-- InteractionSystem.js (javascript, 10 symbols)
|       |   |-- LabelSystem.js (javascript, 17 symbols)
|       |   |-- LeafSystem.js (javascript, 14 symbols)
|       |   |-- MagicTreeScene.js (javascript, 38 symbols)
|       |   |-- main.js (javascript, 34 symbols)
|       |   |-- MutationPlayer.js (javascript, 2 symbols)
|       |   |-- protocol.js (javascript, 6 symbols)
|       |   |-- QualityManager.js (javascript, 13 symbols)
|       |   |-- SceneTimeline.js (javascript, 6 symbols)
|       |   |-- StartupDiagnostics.js (javascript, 4 symbols)
|       |   `-- TreeGrowthSystem.js (javascript, 14 symbols)
|       |-- test
|       |   |-- branch-study-surface.test.js (javascript, 5 symbols)
|       |   |-- branch-system.test.js (javascript, 9 symbols)
|       |   |-- camera-label.test.js (javascript, 8 symbols)
|       |   |-- ground-integration.test.js (javascript, 4 symbols)
|       |   |-- leaf-system.test.js (javascript, 6 symbols)
|       |   |-- mutation-player.test.js (javascript, 5 symbols)
|       |   |-- protocol.test.js (javascript, 4 symbols)
|       |   |-- quality-manager.test.js (javascript, 4 symbols)
|       |   |-- startup-diagnostics.test.js (javascript, 4 symbols)
|       |   `-- tree-growth.test.js (javascript, 5 symbols)
|       `-- organic_tree_preview.dart (dart, 12 symbols)
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
