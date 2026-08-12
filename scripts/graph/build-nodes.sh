#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXTRACTORS_DIR="$ROOT_DIR/.harness/extractors"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
NODES_DIR="${3:-output/nodes}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [nodes-dir]"
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "[ERROR] Repo path not found: $REPO_PATH" >&2
    exit 1
fi

SVC_NODE_DIR="$NODES_DIR/$SERVICE_NAME"
mkdir -p "$SVC_NODE_DIR"

echo "[NODES] Extracting $SERVICE_NAME ($REPO_PATH)..."

# ── D1: 提取计划（G-E2.5 三级回退，见 DESIGN-V2 §7.2 / §10.2）──
# 通过 → 按 extraction_plan 精准提取；部分失败 → 警告 + 回退全部；完全失败/无 profile → 静默回退全部
PROFILE_FILE="$ROOT_DIR/output/analysis/$SERVICE_NAME-profile.yaml"
SELECTED=""   # 空格包裹的提取器名单；空 = 全量
in_plan() { [ -z "$SELECTED" ] && return 0; case "$SELECTED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if [ -f "$PROFILE_FILE" ]; then
    GE25_EXIT=0
    bash "$ROOT_DIR/scripts/gates/GE2.5-framework-analysis.sh" "$PROFILE_FILE" \
        "$ROOT_DIR/output/analysis/$SERVICE_NAME-profile-review.md" >/dev/null 2>&1 || GE25_EXIT=$?
    if [ "$GE25_EXIT" -eq 0 ]; then
        # 解析 extraction_plan.extractors（兼容 flow 式 [a, b] 与 block 式 "- a"）
        PLAN_LINE=$(grep -m1 'extractors:' "$PROFILE_FILE" 2>/dev/null || true)
        PLAN_ITEMS=""
        if echo "$PLAN_LINE" | grep -q '\['; then
            PLAN_ITEMS=$(echo "$PLAN_LINE" | sed 's/.*\[\([^]]*\)\].*/\1/' | tr ',' ' ')
        else
            PLAN_ITEMS=$(sed -n '/extractors:/,/^[^[:space:]-]/p' "$PROFILE_FILE" \
                | grep -E '^[[:space:]]*-[[:space:]]*[a-zA-Z]' \
                | sed 's/^[[:space:]]*-[[:space:]]*//' || true)
        fi
        PLAN_ITEMS=$(echo "$PLAN_ITEMS" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
        if [ -n "$PLAN_ITEMS" ]; then
            SELECTED=" $PLAN_ITEMS "
            echo "[NODES] D1 extraction_plan 生效（$(echo $PLAN_ITEMS | wc -w | tr -d ' ') 个提取器）: $PLAN_ITEMS"
        else
            echo "[WARN] extraction_plan.extractors 为空 — 回退全部提取器"
        fi
    elif [ "$GE25_EXIT" -eq 2 ]; then
        echo "[WARN] G-E2.5 部分失败 — 回退全部提取器"
    else
        echo "[INFO] G-E2.5 未通过 — 回退全部提取器（当前行为）"
    fi
fi

# Phase A: Run all extractors in parallel (动态扫描 .harness/extractors/*/extract.sh，tags 除外)
pids=()

for ext in "$EXTRACTORS_DIR"/*/extract.sh; do
    [ -f "$ext" ] || continue
    proto=$(basename "$(dirname "$ext")")
    [ "$proto" = "tags" ] && continue
    if ! in_plan "$proto"; then
        echo "  [SKIP] ${proto} (not in extraction_plan)"
        continue
    fi
    bash "$ext" "$SERVICE_NAME" "$REPO_PATH" "$NODES_DIR" &
    pids+=($!)
done

# Wait for all extractors and track failures
FAILURES=0
for pid in ${pids[@]+"${pids[@]}"}; do
    if ! wait "$pid"; then
        FAILURES=$((FAILURES + 1))
    fi
done

# Phase B: Tags (serial, after all extractors)
if [ -f "$EXTRACTORS_DIR/tags/extract.sh" ] && in_plan "tags"; then
    bash "$EXTRACTORS_DIR/tags/extract.sh" "$SERVICE_NAME" "$REPO_PATH" "$NODES_DIR"
fi

# Phase C: Check for unknown patterns
if [ -f "$SVC_NODE_DIR/nonstandard-custom.json" ]; then
    UNKNOWN_COUNT=$(grep -c "unknown-pattern" "$SVC_NODE_DIR/nonstandard-custom.json" 2>/dev/null || true)
    if [ "$UNKNOWN_COUNT" -gt 0 ]; then
        echo "  [AI-REQUIRED] $UNKNOWN_COUNT unknown pattern(s) detected → use templates/analyze-pattern.md"
    fi
fi

echo "[NODES] $SERVICE_NAME: $FAILURES extractors failed"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
