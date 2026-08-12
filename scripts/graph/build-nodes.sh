#!/usr/bin/env bash
# build-nodes — Layer 1 节点提取协调器（v2.1 双维度架构）
# 用法: bash scripts/graph/build-nodes.sh <service-name> <repo-path> [nodes-dir] [--ai-dir <dir>]
#
# 双轨调度:
#   - 无 AI 产出（未传 --ai-dir 且 output/nodes-ai/<svc>/ 不存在）→ 单轨（脚本直写最终目录，向后兼容）
#   - 有 AI 产出 → 双轨:
#       脚本维度 → $NODES_DIR-script/<svc>/  （bash extractors 机械基线）
#       AI 维度  → $AI_DIR/<svc>/            （AI 语义产出）
#       合并      → $NODES_DIR/<svc>/         （calibrate-dual 置信度分级 + 去重）
#
# 置信度分级（ai-analysis-harness.md §7，Q-Final=A）:
#   节点级起点: bash∩AI=high / 单方=medium / 矛盾=low
#   协议级加权: profile high→+1 / none→-1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXTRACTORS_DIR="$ROOT_DIR/.harness/extractors"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
NODES_DIR="${3:-output/nodes}"
AI_DIR=""
if [ "${4:-}" = "--ai-dir" ]; then
    AI_DIR="${5:-}"
fi

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [nodes-dir] [--ai-dir <dir>]" >&2
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "[ERROR] Repo path not found: $REPO_PATH" >&2
    exit 1
fi

# 自动探测 AI 产出（未显式传 --ai-dir 时）
if [ -z "$AI_DIR" ] && [ -d "$ROOT_DIR/output/nodes-ai/$SERVICE_NAME" ]; then
    AI_DIR="$ROOT_DIR/output/nodes-ai"
fi

SVC_NODE_DIR="$NODES_DIR/$SERVICE_NAME"
mkdir -p "$SVC_NODE_DIR"

echo "[NODES] Extracting $SERVICE_NAME ($REPO_PATH)..."
[ -n "$AI_DIR" ] && echo "[NODES] Dual-dimension mode: bash × AI"

# ── D1: 提取计划（G-E2.5 三级回退）──
PROFILE_FILE="$ROOT_DIR/output/analysis/$SERVICE_NAME-profile.yaml"
SELECTED=""   # 空格包裹的提取器名单；空 = 全量
in_plan() { [ -z "$SELECTED" ] && return 0; case "$SELECTED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

if [ -f "$PROFILE_FILE" ]; then
    GE25_EXIT=0
    bash "$ROOT_DIR/scripts/gates/GE2.5-framework-analysis.sh" "$PROFILE_FILE" \
        "$ROOT_DIR/output/analysis/$SERVICE_NAME-profile-review.md" >/dev/null 2>&1 || GE25_EXIT=$?
    if [ "$GE25_EXIT" -eq 0 ]; then
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
            echo "[NODES] D1 extraction_plan 生效: $PLAN_ITEMS"
        else
            echo "[WARN] extraction_plan.extractors 为空 — 回退全部提取器"
        fi
    elif [ "$GE25_EXIT" -eq 2 ]; then
        echo "[WARN] G-E2.5 部分失败 — 回退全部提取器"
    else
        echo "[INFO] G-E2.5 未通过 — 回退全部提取器"
    fi
fi

# ── 单轨/双轨目标目录 ──
# 注意: extract-*.sh 内部会追加 $SERVICE_NAME 子目录（OUTPUT_DIR/$SERVICE_NAME/...），
#       故此处传父目录；SVC_NODE_DIR 仅用于双轨合并的最终落地。
SCRIPT_PARENT_DIR="$NODES_DIR"        # 单轨: extractor 写到 $NODES_DIR/$SERVICE_NAME/
SCRIPT_SVC_DIR="$SVC_NODE_DIR"        # 单轨: 实际输出目录
if [ -n "$AI_DIR" ]; then
    SCRIPT_PARENT_DIR="$NODES_DIR-script"
    SCRIPT_SVC_DIR="$NODES_DIR-script/$SERVICE_NAME"
    mkdir -p "$SCRIPT_SVC_DIR"
fi

# ── Phase A: 脚本维度提取（并行）──
pids=()
for ext in "$EXTRACTORS_DIR"/*/extract.sh; do
    [ -f "$ext" ] || continue
    proto=$(basename "$(dirname "$ext")")
    [ "$proto" = "tags" ] && continue
    if ! in_plan "$proto"; then
        echo "  [SKIP] ${proto} (not in extraction_plan)"
        continue
    fi
    bash "$ext" "$SERVICE_NAME" "$REPO_PATH" "$SCRIPT_PARENT_DIR" &
    pids+=($!)
done

FAILURES=0
for pid in ${pids[@]+"${pids[@]}"}; do
    if ! wait "$pid"; then
        FAILURES=$((FAILURES + 1))
    fi
done

# ── Phase B: Tags ──
if [ -f "$EXTRACTORS_DIR/tags/extract.sh" ] && in_plan "tags"; then
    bash "$EXTRACTORS_DIR/tags/extract.sh" "$SERVICE_NAME" "$REPO_PATH" "$SCRIPT_PARENT_DIR"
fi

# ── Phase C: Unknown pattern 检测（脚本维度）──
if [ -f "$SCRIPT_SVC_DIR/nonstandard-custom.json" ]; then
    UNKNOWN_COUNT=$(grep -c "unknown-pattern" "$SCRIPT_SVC_DIR/nonstandard-custom.json" 2>/dev/null || true)
    [ "$UNKNOWN_COUNT" -gt 0 ] && echo "  [AI-REQUIRED] $UNKNOWN_COUNT unknown pattern(s) → use templates/analyze-pattern.md"
fi

# ── Phase D: 双维度合并（仅双轨模式）──
if [ -n "$AI_DIR" ]; then
    AI_SVC_DIR="$AI_DIR/$SERVICE_NAME"
    if [ -d "$AI_SVC_DIR" ]; then
        bash "$SCRIPT_DIR/../base/merge-dual.sh" "$SERVICE_NAME" "$SCRIPT_SVC_DIR" "$AI_SVC_DIR" "$SVC_NODE_DIR" \
            "${PROFILE_FILE:-}" || { echo "[WARN] merge-dual 部分失败" >&2; }
    else
        echo "[WARN] --ai-dir 指定但 $AI_SVC_DIR 不存在 — 回退单轨（脚本直写）"
    fi
fi

echo "[NODES] $SERVICE_NAME: $FAILURES extractors failed"
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
