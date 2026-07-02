#!/usr/bin/env bash
# ==============================================================
# 代码地图更新脚本
# 用途：从 CodeGraph 索引导出人类/智能体可读的代码地图
# 调用时机：每次代码修改完成后、git commit 之前（见 codegraph-map skill）
# ==============================================================
set -euo pipefail

# 项目根目录（脚本所在目录的上一级）
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="docs/CODE_MAP.md"
mkdir -p docs

echo "==> 第 1 步：同步 CodeGraph 索引 ..."
codegraph sync . || codegraph index .   # sync 失败时回退到全量重建

echo "==> 第 2 步：导出代码地图到 $OUT ..."

# 获取当前 git 提交信息（若尚无提交则显示占位符）
GIT_HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "（尚无提交）")

{
  echo "# 代码地图（CODE MAP）"
  echo ""
  echo "> ⚠️ 本文件由 \`scripts/update_code_map.sh\` 自动生成，请勿手工编辑。"
  echo "> 生成时间：$(date '+%Y-%m-%d %H:%M:%S')　对应提交：${GIT_HEAD} 之后的工作区状态"
  echo ""
  echo "## 一、索引状态"
  echo ""
  echo '```'
  codegraph status . 2>/dev/null | sed -e "s/\\x1b\\[[0-9;]*m//g" || echo "（索引状态获取失败）"
  echo '```'
  echo ""
  echo "## 二、项目文件结构（含符号统计）"
  echo ""
  echo '```'
  codegraph files 2>/dev/null | sed -e "s/\\x1b\\[[0-9;]*m//g" || echo "（文件结构获取失败）"
  echo '```'
  echo ""
  echo "## 三、使用说明（给接力开发的智能体）"
  echo ""
  echo "- 查看某符号的定义与调用链：\`codegraph node <符号名>\`"
  echo "- 探索某功能区域：\`codegraph explore \"<自然语言描述>\"\`"
  echo "- 修改前评估影响面：\`codegraph impact <符号名>\`"
  echo "- 查找调用方 / 被调用方：\`codegraph callers <符号名>\` / \`codegraph callees <符号名>\`"
  echo ""
  echo "详细工作流规则见 \`.claude/skills/codegraph-map/SKILL.md\`。"
} > "$OUT"

echo "==> 完成：$OUT 已更新"
