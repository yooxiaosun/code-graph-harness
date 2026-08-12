#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# promote-sdk — E4 SDK 扩展晋级闸门（staging → scripts/base/）
# 用法: bash scripts/promote-sdk.sh <name>
#   前置: .harness/staging/sdk/<name>/ 交付包存在、test-<name>.sh 全绿
# 这是唯一允许将 SDK 扩展写入 scripts/base/ 的通道。
# ─────────────────────────────────────────────────────────────────────
set -uo pipefail

NAME="${1:-}"
if [ -z "$NAME" ]; then
    echo "Usage: $0 <name>"
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

NOW=$(date +"%Y-%m-%d %H:%M")
STAGING_DIR=".harness/staging"
BUNDLE_DIR="$STAGING_DIR/sdk/$NAME"
ARCHIVE_DIR="$STAGING_DIR/archived"
BASE_DIR="scripts/base"
LIB_FILE="$BASE_DIR/${NAME}.sh"
TEST_FILE="$BUNDLE_DIR/test-${NAME}.sh"

# ── 0. 前置检查 ─────────────────────────────────────────────────────
if [ ! -d "$BUNDLE_DIR" ]; then
    echo "[FATAL] SDK 交付包不存在: $BUNDLE_DIR"
    exit 1
fi

if [ ! -f "$BUNDLE_DIR/${NAME}.sh" ]; then
    echo "[FATAL] SDK 函数库缺失: $BUNDLE_DIR/${NAME}.sh"
    exit 1
fi

# 目标冲突
if [ -f "$LIB_FILE" ]; then
    echo "[FATAL] 正式目录已存在 $NAME.sh — 拒绝覆盖"
    echo "  如需修复既有 SDK，走交互式 E4 交接流程（非晋级通道）"
    exit 1
fi

# ── 1. 自证（测试脚本全绿，失败不动任何文件）─────────────────────────
if [ -f "$TEST_FILE" ]; then
    echo "── 晋级前自证（$TEST_FILE）──"
    if ! bash "$ROOT_DIR/$TEST_FILE"; then
        echo "[FATAL] $TEST_FILE 未全绿 — 交付包留在 staging"
        exit 1
    fi
else
    echo "[FATAL] 测试脚本缺失: $TEST_FILE"
    exit 1
fi

# 语法检查
echo "── 语法检查 ──"
if ! bash -n "$ROOT_DIR/$BUNDLE_DIR/${NAME}.sh"; then
    echo "[FATAL] ${NAME}.sh 语法错误 — 交付包留在 staging"
    exit 1
fi

# ── 2. 晋级 ──────────────────────────────────────────────────────────
cp "$ROOT_DIR/$BUNDLE_DIR/${NAME}.sh" "$LIB_FILE"
chmod 644 "$LIB_FILE"
echo "[OK] SDK 函数库: $LIB_FILE"

# ── 3. 记录 + 归档 ───────────────────────────────────────────────────
echo "- [$NOW] [E4] [promoted] SDK ${NAME} 晋级 → ${LIB_FILE}（test-${NAME}.sh 全绿）" >> docs/status/progress.md

mkdir -p "$ARCHIVE_DIR"
mv "$BUNDLE_DIR" "$ARCHIVE_DIR/sdk-$NAME-$(date +%Y-%m-%d)"

echo ""
echo "==== SDK Promote Complete ===="
echo "  函数库: $LIB_FILE"
echo "  已归档: $ARCHIVE_DIR/sdk-$NAME-$(date +%Y-%m-%d)"
echo "  后续: .harness/extractors/ 下提取器可通过 source 直接引用 $LIB_FILE"
