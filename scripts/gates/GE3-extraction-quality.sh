#!/usr/bin/env bash
# G-E3 Extraction Quality Gate（v2.1 双维度）
# 校验提取质量: 脚本维(确定性) + AI 维(实质验收) + 综合判定
# 数据源: output/edges/edge-stats.json + output/calibration/calibration-report.json + output/nodes/**
# 用法: bash scripts/gates/GE3-extraction-quality.sh [match_rate阈值, 默认 0.70]
#
# 双维度语义（Q-Final=A, ai-analysis-harness.md §7）:
#   脚本维: schema 合法性 + evidence 链完整性 + stats 确定性
#   AI 维:  图谱实质验收（每个节点有源码证据 + 双维度一致性可解释）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# jq PATH 引导（内网无系统 jq 时启用 tools/jq）
source "$SCRIPT_DIR/../base/jq-bootstrap.sh"
THRESHOLD="${1:-0.70}"
EDGE_STATS="output/edges/edge-stats.json"
CALIBRATION="output/calibration/calibration-report.json"
NODES_DIR="output/nodes"
FAILURES=0

fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  [PASS] $1"; }

echo "[GE3] Extraction Quality Gate (v2.1 dual-dimension, threshold: $THRESHOLD)"

# ── 前置: 依赖工具 ──
if ! command -v jq &>/dev/null; then
    echo "[ABORT] jq not available"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# 维度一: 脚本维（确定性，bash 可复现）
# ═══════════════════════════════════════════════════════════════════
echo "── [脚本维] Deterministic checks ──"

# 前置: 数据文件存在
[ -f "$EDGE_STATS" ] || { echo "[ABORT] Missing: $EDGE_STATS"; exit 1; }
[ -f "$CALIBRATION" ] || { echo "[ABORT] Missing: $CALIBRATION"; exit 1; }
pass "数据文件存在: edge-stats.json + calibration-report.json"

# 检查 1: match_rate 达标
MATCH_RATE=$(jq -r '.match_rate // 0' "$EDGE_STATS")
if awk -v mr="$MATCH_RATE" -v th="$THRESHOLD" 'BEGIN { exit !(mr >= th) }'; then
    pass "match_rate = $MATCH_RATE (>= $THRESHOLD)"
else
    fail "match_rate = $MATCH_RATE (< $THRESHOLD) — 需进入 E4 自适应或 User 豁免"
fi

# 检查 2: blocker 为空
BLOCKER_COUNT=$(jq '.blockers | length' "$CALIBRATION" 2>/dev/null || echo "-1")
if [ "$BLOCKER_COUNT" = "0" ]; then
    pass "blockers 为空"
elif [ "$BLOCKER_COUNT" = "-1" ]; then
    fail "calibration-report.json 中无 blockers 字段或 JSON 损坏"
else
    jq -r '.blockers[]' "$CALIBRATION" | sed 's/^/    blocker: /'
    fail "blockers 非空 (count=$BLOCKER_COUNT) — 需升级 User 决策"
fi

# 检查 3: unresolved 数据可读
UNRESOLVED_COUNT=$(jq -r '.unresolved // 0' "$EDGE_STATS")
TOTAL_COUNT=$(jq -r '.total_consumers // 0' "$EDGE_STATS")
if [ "$TOTAL_COUNT" -eq 0 ] 2>/dev/null; then
    echo "  [WARN] total_consumers = 0 — 无消费引用数据 (repos.yaml 未配置仓库?)"
else
    pass "消费者统计: total=$TOTAL_COUNT unresolved=$UNRESOLVED_COUNT"
fi

# 检查 4: 完整性分数记录（评级由 D2 AI 决策）
SCORE=$(jq -r '.overallScore // 0' "$CALIBRATION")
echo "  [INFO] completeness score=$SCORE — 评级（GOOD/FAIR/POOR）与分流由 D2 AI 决策"

# ═══════════════════════════════════════════════════════════════════
# 维度二: AI 维（实质验收，v2.1 新增）
# 1. 节点 schema 合规 + 证据链完整 (C-E1)
# 2. 双维度一致性可解释（若存在 output/nodes-ai/ 对比）
# ═══════════════════════════════════════════════════════════════════
echo "── [AI维] Substantive checks ──"

# 检查 5: 节点 schema + 证据链（C-E1 证据底线）
if [ -d "$NODES_DIR" ] && [ -n "$(ls "$NODES_DIR" 2>/dev/null)" ]; then
    SCHEMA_OK=0
    SCHEMA_BAD=0
    for svc_dir in "$NODES_DIR"/*/; do
        [ -d "$svc_dir" ] || continue
        for node_file in "$svc_dir"/*.json; do
            [ -f "$node_file" ] || continue
            # 跳过 tags.json（纯字符串数组, 非对象节点）
            if echo "$node_file" | grep -q "tags.json"; then
                continue
            fi
            if bash "$SCRIPT_DIR/../base/validate-schema.sh" "$node_file" node >/dev/null 2>&1; then
                SCHEMA_OK=$((SCHEMA_OK + 1))
            else
                SCHEMA_BAD=$((SCHEMA_BAD + 1))
                echo "  [WARN] schema 不合规: $node_file"
            fi
        done
    done
    if [ "$SCHEMA_BAD" -eq 0 ]; then
        pass "节点 schema + 证据链合规 (C-E1): $SCHEMA_OK 个文件通过"
    else
        fail "节点 schema 违规: $SCHEMA_BAD 个文件 (需修复或进入 E4)"
    fi
else
    echo "  [WARN] 无节点产出 — 图谱为空 (repos.yaml 未配置仓库?)"
fi

# 检查 6: 双维度一致性可解释（存在 AI 维度时）
if [ -d "output/nodes-ai" ] && [ -n "$(ls output/nodes-ai 2>/dev/null)" ]; then
    DUAL_OK=0
    for svc_dir in "$NODES_DIR"/*/; do
        [ -d "$svc_dir" ] || continue
        svc=$(basename "$svc_dir")
        [ -d "output/nodes-ai/$svc" ] || continue
        # 检查合并后节点的 dual_dimension_consistency 是否可解释（应无 contradiction 未处理）
        CONTRADICTIONS=$(find "$svc_dir" -name '*.json' -exec jq '[.[]? | select(.metadata.dual_dimension_consistency == "contradiction")] | length' {} + 2>/dev/null | jq -s 'add // 0')
        if [ "${CONTRADICTIONS:-0}" -eq 0 ]; then
            DUAL_OK=$((DUAL_OK + 1))
        else
            echo "  [WARN] $svc 有 $CONTRADICTIONS 个 contradiction 节点 — 需 AI 二轮校准归因"
        fi
    done
    pass "双维度一致性已检查 ($DUAL_OK 个服务无 contradiction)"
else
    echo "  [INFO] 单轨模式 — 无双维度一致性检查 (无 AI 产出)"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "[GE3] RESULT: FAIL ($FAILURES check(s) failed)"
    exit 1
fi
echo "[GE3] RESULT: PASS"
exit 0
