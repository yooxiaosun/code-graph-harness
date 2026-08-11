#!/usr/bin/env bash
# G-E3 Extraction Quality Gate
# 校验提取质量: match_rate 阈值 + blocker 为空 + unresolved 数据可读
# 数据源: output/edges/edge-stats.json + output/calibration/calibration-report.json
# 用法: bash scripts/gates/GE3-extraction-quality.sh [match_rate阈值, 默认 0.70]
set -euo pipefail

THRESHOLD="${1:-0.70}"
EDGE_STATS="output/edges/edge-stats.json"
CALIBRATION="output/calibration/calibration-report.json"
FAILURES=0

fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  [PASS] $1"; }

echo "[GE3] Extraction Quality Gate (threshold: $THRESHOLD)"

# 前置: 依赖工具
if ! command -v jq &>/dev/null; then
    echo "[ABORT] jq not available"
    exit 1
fi

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

# 检查 3: unresolved 数据可读且已归因
UNRESOLVED_COUNT=$(jq -r '.unresolved // 0' "$EDGE_STATS")
TOTAL_COUNT=$(jq -r '.total_consumers // 0' "$EDGE_STATS")
MATCHED_COUNT=$(jq -r '.matched // 0' "$EDGE_STATS")
if [ "$TOTAL_COUNT" -eq 0 ] 2>/dev/null; then
    echo "  [WARN] total_consumers = 0 — 无消费引用数据 (repos.yaml 未配置仓库?)"
else
    pass "消费者统计: total=$TOTAL_COUNT matched=$MATCHED_COUNT unresolved=$UNRESOLVED_COUNT"
fi

# 检查 4: 校准评级记录
RATING=$(jq -r '.rating // "UNKNOWN"' "$CALIBRATION")
SCORE=$(jq -r '.overallScore // 0' "$CALIBRATION")
echo "  [INFO] calibration rating=$RATING score=$SCORE"
if [ "$RATING" = "POOR" ]; then
    fail "rating = POOR — 完整性不足, 需进入 E4 或由 User 显式降级接受"
else
    pass "rating = $RATING"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "[GE3] RESULT: FAIL ($FAILURES check(s) failed)"
    exit 1
fi
echo "[GE3] RESULT: PASS"
exit 0
