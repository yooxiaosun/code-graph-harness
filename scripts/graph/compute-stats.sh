#!/usr/bin/env bash
set -euo pipefail

# Layer 3: Compute Stats（v2 拆分自 calibrate.sh）
# Bash 只算数：5 checks 的确定性数值统计 → calibration-report.json
# 质量评级（GOOD/FAIR/POOR）与分流判定由 D2 AI 决策点完成（calibration-analyzer），
# bash 层不再硬编码评级。blockers 保留：provider 冲突是确定性数据事实，非判断。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# jq PATH 引导（内网无系统 jq 时启用 tools/jq）
source "$SCRIPT_DIR/../base/jq-bootstrap.sh"
source "$SCRIPT_DIR/../base/json-writer.sh"

NODES_DIR="${1:-output/nodes}"
EDGES_DIR="${2:-output/edges}"
CALIBRATION_DIR="${3:-output/calibration}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$CALIBRATION_DIR"
REPORT_FILE="$CALIBRATION_DIR/calibration-report.json"

echo "[COMPUTE-STATS] Running 5 checks (numbers only, no rating)..."
BLOCKERS=()
WARNINGS=()

# ── Check A: Orphan Consumers ──
echo "  [A] Orphan consumers..."
UNRESOLVED_FILE="$EDGES_DIR/unresolved-consumers.json"
A_COUNT=0
A_DETAILS="[]"
A_PASS=true

if [ -f "$UNRESOLVED_FILE" ]; then
    A_COUNT=$(jq '. | length' "$UNRESOLVED_FILE" 2>/dev/null || echo "0")
    if [ "$A_COUNT" -gt 0 ] 2>/dev/null; then
        A_PASS=false
        WARNINGS+=("$A_COUNT consumers have no matching provider (external service or extraction gap)")
        A_DETAILS=$(jq '[.[].class_name] | group_by(.) | map({class: .[0], count: length})' "$UNRESOLVED_FILE" 2>/dev/null || echo "[]")
    fi
fi
echo "    orphan_consumers: $A_COUNT"

# ── Check B: Provider Conflicts ──
echo "  [B] Provider conflicts..."
B_COUNT=0
B_PASS=true

if command -v jq &>/dev/null; then
    CONFLICTS=$(mktemp)
    CALIBPROV=$(mktemp)
    trap 'rm -f "$CONFLICTS" "$CALIBPROV"' EXIT

    for provider_file in $(find "$NODES_DIR" -name "*-provider.json" -type f 2>/dev/null || true); do
        [ -f "$provider_file" ] || continue
        p_svc=$(echo "$provider_file" | sed 's|.*/nodes/||' | cut -d/ -f1)
        p_proto=$(basename "$provider_file" | sed 's/-provider.json//')

        jq -r --arg svc "$p_svc" --arg proto "$p_proto" '
            .[] | [.className, $svc, $proto, .id] | @tsv
        ' "$provider_file" 2>/dev/null || true
    done | sort -t$'\t' -k1 > "$CALIBPROV"

    B_COUNT=$(awk -F'\t' '
        { seen[$1]++; services[$1] = services[$1] "," $2; }
        END { for (k in seen) if (seen[k] > 1) print k, services[k] }
    ' "$CALIBPROV" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$B_COUNT" -gt 0 ] 2>/dev/null; then
        B_PASS=false
        BLOCKERS+=("$B_COUNT provider conflicts detected (same interface class registered in multiple services)")
    fi
fi
echo "    provider_conflicts: $B_COUNT"

# ── Check C: Orphan Providers ──
echo "  [C] Orphan providers..."
C_COUNT=0
C_PASS=true

if [ -f "$EDGES_DIR/rpc-edges.json" ]; then
    ALL_PROVIDER_IDS=$(mktemp)
    ALL_EDGE_TOS=$(mktemp)

    for pf in $(find "$NODES_DIR" -name "*-provider.json" -type f 2>/dev/null || true); do
        jq -r '.[].id' "$pf" 2>/dev/null || true
    done | sort -u > "$ALL_PROVIDER_IDS"

    jq -r '.[].to' "$EDGES_DIR/rpc-edges.json" 2>/dev/null | sort -u > "$ALL_EDGE_TOS"

    C_COUNT=$(comm -23 "$ALL_PROVIDER_IDS" "$ALL_EDGE_TOS" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$C_COUNT" -gt 0 ] 2>/dev/null; then
        C_PASS=false
        WARNINGS+=("$C_COUNT providers have no consumer (external consumers or dead code)")
    fi
fi
echo "    orphan_providers: $C_COUNT"

# ── Check D: Nonstandard Confidence Review ──
echo "  [D] Nonstandard confidence..."
D_NEEDS_REVIEW=0
D_LOW_CONF=0
D_ACCEPTED=0

if [ -f "$EDGES_DIR/nonstandard-edges.json" ]; then
    D_NEEDS_REVIEW=$(jq '[.[] | select(.confidence < 0.5)] | length' "$EDGES_DIR/nonstandard-edges.json" 2>/dev/null || echo "0")
    D_LOW_CONF=$(jq '[.[] | select(.confidence >= 0.5 and .confidence < 0.7)] | length' "$EDGES_DIR/nonstandard-edges.json" 2>/dev/null || echo "0")
    D_ACCEPTED=$(jq '[.[] | select(.confidence >= 0.7)] | length' "$EDGES_DIR/nonstandard-edges.json" 2>/dev/null || echo "0")

    if [ "$D_NEEDS_REVIEW" -gt 0 ] 2>/dev/null; then
        WARNINGS+=("$D_NEEDS_REVIEW nonstandard edges need manual review (confidence < 0.5)")
    fi
fi
echo "    needs_review: $D_NEEDS_REVIEW, low: $D_LOW_CONF, accepted: $D_ACCEPTED"

# ── Check E: Completeness Score（只算数，评级交由 D2 AI）──
echo "  [E] Completeness score..."
E_SCORE="0"
E_MATCHED="0"
E_TOTAL="0"

if [ -f "$EDGES_DIR/edge-stats.json" ]; then
    E_SCORE=$(jq -r '.match_rate' "$EDGES_DIR/edge-stats.json" 2>/dev/null || echo "0")
    E_MATCHED=$(jq -r '.matched' "$EDGES_DIR/edge-stats.json" 2>/dev/null || echo "0")
    E_TOTAL=$(jq -r '.total_consumers' "$EDGES_DIR/edge-stats.json" 2>/dev/null || echo "0")
fi
echo "    score: $E_SCORE (rating deferred to D2 AI decision)"

# ── Compile Report ──
# 空数组时直接输出 []，避免 "${arr[@]:-}" 传入单个空字符串参数
if [ "${#BLOCKERS[@]}" -gt 0 ]; then
    BLOCKERS_JSON=$(json_tags_from_list "${BLOCKERS[@]}")
else
    BLOCKERS_JSON="[]"
fi
if [ "${#WARNINGS[@]}" -gt 0 ]; then
    WARNINGS_JSON=$(json_tags_from_list "${WARNINGS[@]}")
else
    WARNINGS_JSON="[]"
fi

cat > "$REPORT_FILE" <<REPORT
{
  "generatedAt": "$TIMESTAMP",
  "overallScore": $E_SCORE,
  "checks": {
    "A_orphanConsumers": {"count": $A_COUNT, "pass": $A_PASS, "details": $A_DETAILS},
    "B_providerConflicts": {"count": $B_COUNT, "pass": $B_PASS},
    "C_orphanProviders": {"count": $C_COUNT, "pass": $C_PASS},
    "D_nonstandardConfidence": {"needsReview": $D_NEEDS_REVIEW, "lowConfidence": $D_LOW_CONF, "accepted": $D_ACCEPTED},
    "E_completenessScore": {"score": $E_SCORE, "matched": $E_MATCHED, "total": $E_TOTAL}
  },
  "blockers": $BLOCKERS_JSON,
  "warnings": $WARNINGS_JSON
}
REPORT

echo ""
echo "[COMPUTE-STATS] Report: $REPORT_FILE"
echo "  Score: $E_SCORE"
echo "  Blockers: ${#BLOCKERS[@]}"
echo "  Warnings: ${#WARNINGS[@]}"

if [ "${#BLOCKERS[@]}" -gt 0 ]; then
    echo "[COMPUTE-STATS] BLOCKED — ${#BLOCKERS[@]} blocker(s) found"
    exit 1
fi

echo "[COMPUTE-STATS] PASS — no blockers"
