#!/usr/bin/env bash
# Code Graph — Knowledge Extraction Pipeline
# 8-phase: 0→Deps, 1→Repos, 2→Nodes(脚本维), 2.5→双维度校准(AI后驱占位), 3→Edges, 4→Stats, 5→Assemble, 6→Merge, 7→Summary
# md-first: 本工具只做机械编排；策略判断（--plan/合并/校准）由 AI 读 templates/*.md 后决策
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPH_SCRIPTS="$SCRIPT_DIR/graph"
REPO_CONFIG="${1:-repos.yaml}"
# 项目实例的固化产物位置（AI/编排器注入；不硬编码、不自动探测）
EXTRACTORS_DIR="${EXTRACTORS_DIR:-/Users/johnsmith/WorkBench/code-graph/project/extractors}"
NODES_DIR="output/nodes"
EDGES_DIR="output/edges"
CALIBRATION_DIR="output/calibration"
GRAPH_DIR="output/knowledge-graph"

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

# 工具 → 安装命令（Linux/WSL 各发行版 + macOS）
tool_install_hint() {
    case "$1" in
        jq)   echo "sudo apt-get install -y jq    # Debian/Ubuntu/WSL  |  sudo yum install -y jq (RHEL)  |  sudo dnf install -y jq (Fedora)  |  brew install jq (macOS)" ;;
        node) echo "sudo apt-get install -y nodejs    # 或用 nvm: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" ;;
        git)  echo "sudo apt-get install -y git    # Debian/Ubuntu/WSL  |  brew install git (macOS)" ;;
        *)    echo "请按发行版包管理器安装 $1" ;;
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
        echo "  [HINT] $(tool_install_hint "$tool")"
        MISSING=$((MISSING + 1))
        MISSING_LIST="$MISSING_LIST $tool"
    fi
done
if [ "$MISSING" -gt 0 ]; then
    echo "  [FAIL] 关键依赖缺失（gate-criteria.md §G-E1 MUST）：$MISSING_LIST"
    echo "  [FAIL] 完整安装指引见 docs/SETUP.md；缺失依赖将使后续阶段以无关报错形式失败"
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
# Phase 2: Node Extraction (Layer 1)
# 脚本维度(bash extractors) 机械执行；--plan 选择由 AI 决策后显式传入
# ─────────────────────────────────────────────────────────────────────
run_phase "2" "Node Extraction (Layer 1: script dimension)"

if [ -f "$REPO_CONFIG" ] && [ "$(get_repo_count "$REPO_CONFIG")" -gt 0 ] 2>/dev/null; then
    while IFS= read -r repo_url; do
        [ -z "$repo_url" ] && continue
        REPO_NAME=$(basename "$repo_url" .git)
        REPO_PATH="$WORK_DIR/$REPO_NAME"

        [ ! -d "$REPO_PATH" ] && echo "  [SKIP] $REPO_NAME: not cloned" && continue

        # 脚本维度提取：遍历 project 提取器（排除 tags，后置串行）
        # --plan 由 AI 按 templates/build-nodes-scheduling.md 决策；无则全量（向后兼容）
        PLAN="${EXTRACTION_PLAN:-}"
        pids=()
        for ext in "$EXTRACTORS_DIR"/*/extract.sh; do
            [ -f "$ext" ] || continue
            proto=$(basename "$(dirname "$ext")")
            [ "$proto" = "tags" ] && continue
            if [ -n "$PLAN" ] && ! case " $PLAN " in *" $proto "*) ;; *) false ;; esac; then
                echo "  [SKIP] ${proto} (not in EXTRACTION_PLAN)"
                continue
            fi
            bash "$ext" "$REPO_NAME" "$REPO_PATH" "$NODES_DIR" &
            pids+=($!)
        done
        for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || true; done

        # tags 串行
        if [ -f "$EXTRACTORS_DIR/tags/extract.sh" ]; then
            bash "$EXTRACTORS_DIR/tags/extract.sh" "$REPO_NAME" "$REPO_PATH" "$NODES_DIR"
        fi
    done < <(get_repo_urls "$REPO_CONFIG")
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# Phase 2.5: 双维度校准（占位，AI 后驱）
# 由 graph-orchestrator 在 pipeline 退出后 spawn calibration-analyzer 完成：
#   - 双维度合并:   templates/dual-dimension-merge.md（AI 自主）
#   - 校准汇总:     templates/calibration-summary.md（AI 自主）
#   - 人工确认包:   templates/generate-human-review.md（AI 自主）
# 本工具不含任何汇总/统计判断（md-first 哲学）
# ─────────────────────────────────────────────────────────────────────
run_phase "2.5" "Dual Calibration (AI responsibility, placeholder)"
echo "  [Phase 2.5 placeholder] 由 calibration-analyzer 在 pipeline 退出后执行"
echo "  模板: templates/dual-dimension-merge.md + templates/calibration-summary.md"
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
echo "  Phase 2.5: 双维度校准由 calibration-analyzer 后驱（templates/dual-dimension-merge.md）"
