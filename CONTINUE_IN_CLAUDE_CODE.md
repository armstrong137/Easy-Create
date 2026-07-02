# 迁移到 Claude Code 接力指南

> 本项目此前在 claude.ai 沙箱中完成了需求梳理与设计定稿，现迁移到 Claude Code 继续开发。
> 按以下步骤操作后，任何 Claude Code 会话都能无缝接力。

## 一、解压与准备（在您的电脑上）

```bash
# 1. 解压项目到工作目录
tar -xzf novel-app-project.tar.gz
cd project

# 2. 确认 git 历史完整（应看到 2 次以上中文提交）
git log --oneline
```

## 二、安装两个 skill 依赖

### CodeGraph（代码地图）
```bash
npm install -g @colbymchenry/codegraph   # 安装 CLI
codegraph install                        # 将 MCP 服务器接入 Claude Code（自动检测）
codegraph init                           # 在项目根目录重建本机索引（.codegraph/ 不随包携带）
```

### Superpowers（brainstorming 等开发方法论）
项目内 `.claude/skills/` 已自带全套 skills，Claude Code 会自动发现项目级 skills，无需额外安装。
如需全局安装官方插件版（可选）：在 Claude Code 中执行
```
/plugin install superpowers@claude-plugins-official
```

## 三、环境要求

- Flutter SDK（stable 渠道，3.x 以上）：https://docs.flutter.dev/get-started/install
- 用于真机/模拟器调试的 Xcode（iOS）或 Android Studio（Android）

## 四、开工提示词（复制给 Claude Code 的第一句话）

```
请依次阅读 PROJECT_RULES.md、claude.md、DevelopmentPlan.md、docs/CODE_MAP.md，
严格遵守其中全部协作规则（中文对话与注释、维护 claude.md 与 DevelopmentPlan.md、
git 版本管理、每次 commit 前运行 bash scripts/update_code_map.sh 更新代码地图），
然后从 DevelopmentPlan.md 标记的当前进度开始接力开发。
需求疑问以 docs/superpowers/specs/2026-07-02-novel-app-design.md 为唯一权威。
```

## 五、当前进度快照（迁移时点）

- ✅ 需求梳理与三节设计已定稿（brainstorming 完成）
- ✅ claude.md / DevelopmentPlan.md / PROJECT_RULES.md / 代码地图体系已建立
- ☐ 下一步：**阶段一 · 第 1 步 —— 初始化 Flutter 工程骨架**（尚未开始，尚无任何 Flutter 代码）
