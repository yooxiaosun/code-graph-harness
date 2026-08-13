#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目实例的固化产物位置（AI/编排器注入）
PROJECT_DIR="${PROJECT_DIR:-/Users/johnsmith/WorkBench/code-graph/project}"
EXTRACTORS_DIR="${EXTRACTORS_DIR:-$PROJECT_DIR/extractors}"
FIXTURES_DIR="${FIXTURES_DIR:-$PROJECT_DIR/fixtures}"

failures=0
for file in .agent/project.json .agent/report.json; do
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$file" || failures=$((failures + 1))
done

if [ ! -x scripts/validate-config.sh ] || [ ! -x scripts/gates/all.sh ] || [ ! -x scripts/workflow/verify.sh ]; then
  echo "[FAIL] expected generated scripts to be executable"
  failures=$((failures + 1))
fi

# ── GP1-GP5 fixture verification: gate-criteria.md MUST ──
GATES_DIR="scripts/gates"
for proto in http-client mq custom; do
    extractor="$EXTRACTORS_DIR/$proto/extract.sh"
    [ -f "$extractor" ] || continue
    echo ""
    echo "── Fixture verification: $proto ($extractor) ──"
    for gp in GP1 GP2 GP3 GP4 GP5; do
        gp_script="$GATES_DIR/${gp}-verify.sh"
        if [ ! -f "$gp_script" ]; then
            echo "[SKIP] $gp: missing $gp_script"
            failures=$((failures + 1))
            continue
        fi
        if bash "$gp_script" "$extractor"; then
            echo "[PASS] $gp"
        else
            echo "[FAIL] $gp returned non-zero"
            failures=$((failures + 1))
        fi
    done
done

# ── Graph Pipeline Smoke: extractors → build-edges (最小聚焦检查) ──
GRAPH_SMOKE_DIR="scripts/tests/.graph-smoke"
GRAPH_NODES_DIR="$GRAPH_SMOKE_DIR/nodes"
GRAPH_EDGES_DIR="$GRAPH_SMOKE_DIR/edges"
GRAPH_FIXTURE="$FIXTURES_DIR/sample-http-client"
GRAPH_SVC="smoke-svc"

echo ""
echo "── Graph Pipeline Smoke (extractors → build-edges) ──"
rm -rf "$GRAPH_SMOKE_DIR"
mkdir -p "$GRAPH_NODES_DIR" "$GRAPH_EDGES_DIR"

# 内联执行 http-client 提取器（替代已删除的 build-nodes.sh）
HTTP_EXT="$EXTRACTORS_DIR/http-client/extract.sh"
if [ -f "$HTTP_EXT" ] && bash "$HTTP_EXT" "$GRAPH_SVC" "$GRAPH_FIXTURE" "$GRAPH_NODES_DIR" >/dev/null 2>&1; then
    echo "[PASS] http-client extractor ran on fixture"
else
    echo "[FAIL] http-client extractor returned non-zero (or missing)"
    failures=$((failures + 1))
fi

if node -e "const a=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); if(!Array.isArray(a)||a.length===0) process.exit(1); const n=a[0]; if(!n.id||!n.role||!n.protocol) process.exit(1);" "$GRAPH_NODES_DIR/$GRAPH_SVC/nonstandard-http.json" 2>/dev/null; then
    echo "[PASS] Graph nodes: nonstandard-http.json is a non-empty JSON array with id/role/protocol fields"
else
    echo "[FAIL] Graph nodes: nonstandard-http.json missing or structurally invalid"
    failures=$((failures + 1))
fi

if bash scripts/graph/build-edges.sh "$GRAPH_NODES_DIR" "$GRAPH_EDGES_DIR" >/dev/null 2>&1; then
    echo "[PASS] build-edges.sh ran on smoke nodes"
else
    echo "[FAIL] build-edges.sh returned non-zero"
    failures=$((failures + 1))
fi

if node -e "const s=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')); for(const k of ['total_consumers','matched','unresolved','match_rate','nonstandard_edges']) if(!(k in s)) process.exit(1); if(s.nonstandard_edges<1) process.exit(1);" "$GRAPH_EDGES_DIR/edge-stats.json" 2>/dev/null; then
    echo "[PASS] Graph edges: edge-stats.json has expected fields and nonstandard edges"
else
    echo "[FAIL] Graph edges: edge-stats.json missing or incomplete"
    failures=$((failures + 1))
fi

rm -rf "$GRAPH_SMOKE_DIR"

echo ""
echo "$failures 失败"
[ "$failures" -eq 0 ]