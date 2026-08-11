#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# promote-extractor — E4 交付包晋级闸门（staging → scripts/extractors/nonstandard/）
# 用法: bash scripts/promote-extractor.sh <pattern>
#   前置: .harness/staging/<pattern>/ 交付包存在且 e4-verify-bundle.sh 全绿
# 这是唯一允许将提取器写入正式目录的通道（防线 3）。
# 规则见 .harness/staging/README.md 与 nightly-mode.md §7。
# ─────────────────────────────────────────────────────────────────────
set -uo pipefail

PATTERN="${1:-}"
if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <pattern>"
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

NOW=$(date +"%Y-%m-%d %H:%M")
STAGING_DIR=".harness/staging"
BUNDLE_DIR="$STAGING_DIR/$PATTERN"
ARCHIVE_DIR="$STAGING_DIR/archived"
FORMAL_DIR="scripts/extractors/nonstandard"
FIXTURES_DIR="$FORMAL_DIR/fixtures"
SCRIPT_FILE="$FORMAL_DIR/extract-$PATTERN.sh"

# ── 0. 前置检查 ─────────────────────────────────────────────────────
if [ ! -d "$BUNDLE_DIR" ]; then
    echo "[FATAL] 交付包不存在：$BUNDLE_DIR"
    exit 1
fi

# 目标冲突：正式目录已存在同名提取器 → 拒绝（防覆盖既有）
if [ -f "$SCRIPT_FILE" ] || [ -d "$FIXTURES_DIR/sample-$PATTERN" ]; then
    echo "[FATAL] 正式目录已存在 $PATTERN 提取器或 fixtures — 拒绝覆盖"
    echo "  如需修复既有提取器，走交互式 E4 交接流程（非晋级通道）"
    exit 1
fi

# ── 1. 自证（再次全量验证，失败不动任何文件）─────────────────────────
echo "── 晋级前自证 ──"
if ! bash "$ROOT_DIR/scripts/e4-verify-bundle.sh" "$PATTERN"; then
    echo "[FATAL] e4-verify-bundle.sh 未全绿 — 交付包留在 staging"
    exit 1
fi

# ── 2. 晋级（脚本 + fixtures 三件套）─────────────────────────────────
mkdir -p "$FIXTURES_DIR/expected"
mkdir -p "$ARCHIVE_DIR"

cp "$BUNDLE_DIR/extract-$PATTERN.sh" "$SCRIPT_FILE"
chmod +x "$SCRIPT_FILE"
cp -R "$BUNDLE_DIR/fixtures/sample-$PATTERN" "$FIXTURES_DIR/"
cp "$BUNDLE_DIR/fixtures/expected/$PATTERN.json" "$FIXTURES_DIR/expected/"

# ── 3. 记录 + 归档 ───────────────────────────────────────────────────
echo "- [$NOW] [E4] [promoted] ${PATTERN} 晋级 → ${SCRIPT_FILE}（e4-verify-bundle 全绿）" >> docs/status/progress.md

mv "$BUNDLE_DIR" "$ARCHIVE_DIR/$PATTERN-$(date +%Y-%m-%d)"

echo ""
echo "==== Promote Complete ===="
echo "  提取器: $SCRIPT_FILE"
echo "  fixtures: $FIXTURES_DIR/sample-$PATTERN/ + expected/$PATTERN.json"
echo "  已归档: $ARCHIVE_DIR/$PATTERN-$(date +%Y-%m-%d)"
echo "  后续（人工/交互）: repos.yaml scanners 注册 + build-nodes.sh 接入"
