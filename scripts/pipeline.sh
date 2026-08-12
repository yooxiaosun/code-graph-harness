#!/usr/bin/env bash
# Code Graph — Knowledge Extraction Pipeline
# 8-phase execution: 0→Deps, 1→Repos, 2→Nodes (L1 双维度), 2.5→Dual Calibration, 3→Edges (L2), 4→Stats (L3), 5→Assemble, 6→Merge, 7→Summary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPH_SCRIPTS="$SCRIPT_DIR/graph"
REPO_CONFIG="${1:-repos.yaml}"
NODES_DIR="output/nodes"
EDGES_DIR="output/edges"
CALIBRATION_DIR="output/calibration"
GRAPH_DIR="output/knowledge-graph"
AI_NODES_DIR="output/nodes-ai"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "==== Code Graph Knowledge Extraction Pipeline ===="
echo "  Started: $TIMESTAMP"
echo "  Config: $REPO_CONFIG"
echo "  Architecture: D1分析→Nodes双维度(L1)→Edges(L2)→Stats(L3)→Assemble"
echo ""

run_phase() { echo "══ Phase $1 — $2 ══"; }

# 工具 → 受影响阶段映射（缺失时精确阻断原因；gate-criteria.md §G-E1 将依赖工具齐全列为 MUST）
tool_phase() {
    case "$1" in
        git)   echo "Phase 1 Repository Preparation" ;;
        bash)  echo "全部阶段 (script interpreter)" ;;
        jq)    echo "Phase 2-4 Nodes/Edges/Stats (JSON processing)" ;;
        node)  echo "Phase 2-3 Nodes/Edges (extractors)" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────
# Phase 0: Dependency Check
# ─────────────────────────────────────────────────────────────────────
run_phase "0" "Dependency Check"
MISSING=0
MISSING_LIST=""
for tool in git bash jq node; do
    if ! command -v "$tool" &>/dev/null; then
        PHASES=$(tool_phase "$tool")
        echo "  [WARN] Missing: $tool (impact: $PHASES)"
        MISSING=$((MISSING + 1))
        MISSING_LIST="$MISSING_LIST $tool"
    fi
done
if [ "$MISSING" -gt 0 ]; then
    echo "  [FAIL] 关键依赖缺失（gate-criteria.md §G-E1 MUST）：$MISSING_LIST"
    echo "  [FAIL] 请安装缺失工具后重试；缺失依赖将使后续阶段以无关报错形式失败"
    exit 1
fi
[ "${BASH_VERSINFO[0]:-0}" -lt 4 ] && echo "  [WARN] Bash >=4 recommended (current: $BASH_VERSION)"
mkdir -p "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR" "$GRAPH_DIR"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 1: Repository Preparation
# ─────────────────────────────────────────────────────────────────────
run_phase "1" "Repository Preparation"
if [ -f "$REPO_CONFIG" ]; then
    source "$SCRIPT_DIR/base/repo-manager.sh"
    WORK_DIR="output/repos"
    REPO_COUNT=$(get_repo_count "$REPO_CONFIG")
    echo "  Repos configured: $REPO_COUNT"

    if [ "$REPO_COUNT" -gt 0 ]; then
        while IFS= read -r repo_url; do
            [ -z "$repo_url" ] && continue
            BRANCH=$(get_repo_branch "$REPO_CONFIG" "$repo_url")
            [ -z "$BRANCH" ] && BRANCH="master"
            clone_or_update "$repo_url" "$BRANCH" "$WORK_DIR" 1 || echo "  [WARN] Failed: $repo_url"
        done < <(get_repo_urls "$REPO_CONFIG")
    else
        echo "  [SKIP] No repos in repos.yaml — add repos to enable extraction"
    fi
else
    echo "  [SKIP] repos.yaml not found"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 2: Node Extraction (Layer 1, 双维度)
# 脚本维度(bash extractors) + AI 维度(output/nodes-ai/) 自动探测合并
# ─────────────────────────────────────────────────────────────────────
run_phase "2" "Node Extraction (Layer 1: dual-dimension bash × AI)"

if [ -f "$REPO_CONFIG" ] && [ "$(get_repo_count "$REPO_CONFIG")" -gt 0 ] 2>/dev/null; then
    while IFS= read -r repo_url; do
        [ -z "$repo_url" ] && continue
        REPO_NAME=$(basename "$repo_url" .git)
        REPO_PATH="$WORK_DIR/$REPO_NAME"

        [ ! -d "$REPO_PATH" ] && echo "  [SKIP] $REPO_NAME: not cloned" && continue

        # build-nodes.sh 自动探测 output/nodes-ai/<svc>/：存在则双轨合并，否则单轨直写
        bash "$GRAPH_SCRIPTS/build-nodes.sh" "$REPO_NAME" "$REPO_PATH" "$NODES_DIR"
    done < <(get_repo_urls "$REPO_CONFIG")
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 2.5: 双维度校准摘要
# AI 二轮校准 + 人工确认包由 AI Agent 执行（templates/dual-pass-review.md），
# 此处仅汇总状态供 E3 与 human review 使用
# ─────────────────────────────────────────────────────────────────────
run_phase "2.5" "Dual Calibration Status"
if [ -d "$AI_NODES_DIR" ] && [ -n "$(ls "$AI_NODES_DIR" 2>/dev/null)" ]; then
    AI_SVCS=$(ls "$AI_NODES_DIR" | wc -l | tr -d ' ')
    echo "  AI 维度服务数: $AI_SVCS"
    echo "  提示: 低置信度/bail-out 项由 calibration-analyzer 收集 → output/reviews/human-review-<date>.md"
    echo "  规范: templates/ai-analysis-harness.md + templates/dual-pass-review.md"
else
    echo "  [SKIP] 无 AI 维度产出 — 单轨模式（脚本维度直写）"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 3: Edge Building (Layer 2)
# ─────────────────────────────────────────────────────────────────────
run_phase "3" "Edge Building (Layer 2: provider pool → consumer matching)"
bash "$GRAPH_SCRIPTS/build-edges.sh" "$NODES_DIR" "$EDGES_DIR"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 4: Compute Stats (Layer 3)
# ─────────────────────────────────────────────────────────────────────
run_phase "4" "Compute Stats (Layer 3: 5 checks, numbers only)"
if bash "$GRAPH_SCRIPTS/compute-stats.sh" "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR"; then
    echo ""
else
    echo "[ABORT] Stats computation blocked — check output/calibration/calibration-report.json"
    exit 1
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 5: Graph Assembly
# ─────────────────────────────────────────────────────────────────────
run_phase "5" "Graph Assembly"
bash "$GRAPH_SCRIPTS/assemble-graph.sh" "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR" "$GRAPH_DIR/latest.json"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 6: Incremental Merge
# ─────────────────────────────────────────────────────────────────────
run_phase "6" "Incremental Merge"
bash "$GRAPH_SCRIPTS/merge-graphs.sh" "$NODES_DIR" "$GRAPH_DIR"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 7: Summary
# ─────────────────────────────────────────────────────────────────────
run_phase "7" "Summary"
END_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "  Completed: $END_TIMESTAMP"
if [ -f "$GRAPH_DIR/latest.json" ] && command -v jq &>/dev/null; then
    echo "  Stats:"
    jq '.stats' "$GRAPH_DIR/latest.json" 2>/dev/null || echo "  [no stats]"
    echo "  Calibration:"
    jq '{score: .calibrationScore, rating: .calibrationRating}' "$GRAPH_DIR/latest.json" 2>/dev/null || true
fi
echo ""
echo "==== Pipeline Complete ===="
echo "  Graph:  $GRAPH_DIR/latest.json"
echo "  Edges:  $EDGES_DIR/"
echo "  Report: $CALIBRATION_DIR/calibration-report.json"
echo "  Mode:   $([ -d "$AI_NODES_DIR" ] && [ -n "$(ls "$AI_NODES_DIR" 2>/dev/null)" ] && echo "dual-dimension (bash × AI)" || echo "single-track (bash only)")"
