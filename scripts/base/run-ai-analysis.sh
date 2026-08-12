#!/usr/bin/env bash
# run-ai-analysis — AI 迭代分析的 bash 驱动（M2 基础设施）
# 读取 output/analysis/<service>/round-<N>.state.yaml，按 templates/ai-analysis-harness.md
# 的收敛判定（C-E1/C-E2/C-E3/C-E4）与场景最大轮数决定：
#   0 = 收束 (pass)   → 可进入下一步（人工确认包/图谱）
#   2 = 继续下一轮 (continue)
#   1 = bail-out → 加入人工确认包
# 用法: bash scripts/base/run-ai-analysis.sh <state-file> <max-rounds> <scenario>
set -uo pipefail

STATE_FILE="${1:-}"
MAX_ROUNDS="${2:-3}"
SCENARIO="${3:-dual_pass_review}"

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
    echo "Usage: $0 <state-file> <max-rounds> <scenario>" >&2
    echo "  state-file not found: $STATE_FILE" >&2
    exit 2
fi

if ! command -v python3 &>/dev/null; then
    echo "[ABORT] python3 not available (needed for YAML parse)"
    exit 1
fi

# 用 python3 解析 state.yaml 提取关键字段
# 参数: <yaml-key>，converged 子字段用 "c_<子键>" 形式
parse() {
    python3 -c "
import yaml,sys
d=yaml.safe_load(open('$STATE_FILE')) or {}
c=d.get('converged') or {}
key='$1'
if key.startswith('c_'):
    sub=key[2:]
    # 规范化: c_e1 → C_E1_evidence_floor, c_e2 → C_E2_stability, c_e3 → C_E3_diminishing, c_e4 → C_E4_no_jump
    if sub == 'e1': field='C_E1_evidence_floor'
    elif sub == 'e2': field='C_E2_stability'
    elif sub == 'e3': field='C_E3_diminishing'
    elif sub == 'e4': field='C_E4_no_jump'
    else: field=sub
    v=c.get(field, '')
else:
    v=d.get(key, '')
print(str(v).lower())
" 2>/dev/null || echo ""
}

ROUND=$(parse "round")
if [ -z "$ROUND" ]; then ROUND=1; fi
echo "[RUN-AI] state=$STATE_FILE round=$ROUND/$MAX_ROUNDS scenario=$SCENARIO"

# ── 读收敛判定 ──
c_e1=$(parse "c_e1")
c_e2=$(parse "c_e2")
c_e3=$(parse "c_e3")
c_e4=$(parse "c_e4")
overall=$(parse "overall_status")

# ── bail-out 判定 ──
if [ "$overall" = "bail-out" ]; then
    echo "[RUN-AI] RESULT: BAIL-OUT (state marked bail-out)"
    exit 1
fi

# 场景判定条数配置（Q-Conv=C 按场景分级）
case "$SCENARIO" in
    d1)                 CHECKS="c_e1 c_e2 c_e4" ;;   # D1: 3 条 (去 C-E3)
    dual_pass_review)   CHECKS="c_e1 c_e2 c_e3 c_e4" ;; # 双维度: 4 条
    low_conf_drill)     CHECKS="c_e1 c_e3" ;;         # 低置信度: 2 条
    e4)                 CHECKS="c_e1" ;;              # E4: 沿用既有（证据底线）
    *)                  CHECKS="c_e1 c_e2 c_e3 c_e4" ;;
esac

# 逐条评估（缺字段视为不满足 → continue）
all_pass=true
for c in $CHECKS; do
    val=""
    case "$c" in
        c_e1) val="$c_e1" ;;
        c_e2) val="$c_e2" ;;
        c_e3) val="$c_e3" ;;
        c_e4) val="$c_e4" ;;
    esac
    if [ "$val" = "true" ]; then
        echo "  [PASS] $c"
    else
        echo "  [FAIL] $c (=$val)"
        all_pass=false
    fi
done

if [ "$all_pass" = true ]; then
    echo "[RUN-AI] RESULT: PASS (all convergence checks satisfied)"
    exit 0
fi

# 未收束 → 判断是否达最大轮数
if [ "$ROUND" -ge "$MAX_ROUNDS" ]; then
    echo "[RUN-AI] RESULT: BAIL-OUT (max rounds $MAX_ROUNDS reached without convergence)"
    exit 1
fi

echo "[RUN-AI] RESULT: CONTINUE (round $ROUND < $MAX_ROUNDS, checks not all satisfied)"
exit 2
