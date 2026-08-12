#!/usr/bin/env bash
# build-nodes — Layer 1 节点提取执行器（纯参数化机械工具，v2.2 md-first）
# 用法: bash scripts/graph/build-nodes.sh <service-name> <repo-path> <nodes-parent-dir> [--plan "dubbo rest mq"] [--no-tags]
#
# md-first 哲学（DEVELOPMENT_STANDARD.md §1）:
#   - 本工具不包含任何策略判断（选哪些提取器/单轨双轨/回退）——那是 AI 读
#     templates/build-nodes-scheduling.md 后决策的，通过 --plan 显式传入
#   - 双维度合并由 AI 按 templates/dual-dimension-merge.md 完成（不在本工具内）
#   - 本工具只做: 运行给定提取器 → 收集结果 → 报告失败/unknown
#
# 输出: <nodes-parent-dir>/<service-name>/*.json （extractor 内部会追加 service 子目录）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXTRACTORS_DIR="$ROOT_DIR/.harness/extractors"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
NODES_PARENT_DIR="${3:-output/nodes}"
PLAN=""
RUN_TAGS=true

# 解析可选参数
shift 3 || true
while [ $# -gt 0 ]; do
    case "$1" in
        --plan)
            PLAN="${2:-}"
            shift 2
            ;;
        --no-tags)
            RUN_TAGS=false
            shift
            ;;
        *)
            echo "[WARN] unknown arg: $1" >&2
            shift
            ;;
    esac
done

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> <nodes-parent-dir> [--plan \"a b c\"] [--no-tags]" >&2
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "[ERROR] Repo path not found: $REPO_PATH" >&2
    exit 1
fi

mkdir -p "$NODES_PARENT_DIR"
echo "[NODES] Extracting $SERVICE_NAME ($REPO_PATH) → $NODES_PARENT_DIR"

# --plan 决定执行集；空 = 全量（AI 未指定时向后兼容全跑）
in_plan() {
    if [ -z "$PLAN" ]; then
        return 0
    fi
    case " $PLAN " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Phase A: 脚本维度提取（并行）──
pids=()
for ext in "$EXTRACTORS_DIR"/*/extract.sh; do
    [ -f "$ext" ] || continue
    proto=$(basename "$(dirname "$ext")")
    [ "$proto" = "tags" ] && continue
    if ! in_plan "$proto"; then
        echo "  [SKIP] ${proto} (not in --plan)"
        continue
    fi
    bash "$ext" "$SERVICE_NAME" "$REPO_PATH" "$NODES_PARENT_DIR" &
    pids+=($!)
done

FAILURES=0
for pid in ${pids[@]+"${pids[@]}"}; do
    if ! wait "$pid"; then
        FAILURES=$((FAILURES + 1))
    fi
done

# ── Phase B: Tags（默认执行，--no-tags 关闭）──
if [ "$RUN_TAGS" = true ] && [ -f "$EXTRACTORS_DIR/tags/extract.sh" ] && in_plan "tags"; then
    bash "$EXTRACTORS_DIR/tags/extract.sh" "$SERVICE_NAME" "$REPO_PATH" "$NODES_PARENT_DIR"
fi

# ── Phase C: Unknown pattern 检测（信息性报告，交 AI 决策）──
SVC_DIR="$NODES_PARENT_DIR/$SERVICE_NAME"
if [ -f "$SVC_DIR/nonstandard-custom.json" ]; then
    UNKNOWN_COUNT=$(grep -c "unknown-pattern" "$SVC_DIR/nonstandard-custom.json" 2>/dev/null || true)
    [ "$UNKNOWN_COUNT" -gt 0 ] && echo "  [INFO] $UNKNOWN_COUNT unknown pattern(s) → AI 决策 (templates/analyze-pattern.md)"
fi

echo "[NODES] $SERVICE_NAME: $FAILURES extractors failed"
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
