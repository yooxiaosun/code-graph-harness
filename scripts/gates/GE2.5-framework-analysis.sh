#!/usr/bin/env bash
# G-E2.5 Framework Analysis Quality Gate（v2 新增）
# 校验 D1 框架分析产出：profile.yaml 格式 + evidence 完整性 + unknown 标记
# 用法: bash scripts/gates/GE2.5-framework-analysis.sh <profile.yaml> [review.md]
# 退出码（与 gate-criteria.md §G-E2.5 / DESIGN-V2 §10.2 一致）:
#   0 = 通过（按 extraction_plan 精准提取）
#   2 = 部分失败（evidence 缺失 / review 未产出 → 警告 + 回退全部提取器）
#   1 = 完全失败（profile 不存在 / YAML 无法解析 / 必填字段缺失 → 静默回退全部提取器）
set -uo pipefail

PROFILE="${1:-}"
REVIEW="${2:-}"

if [ -z "$PROFILE" ]; then
    echo "Usage: $0 <profile.yaml> [review.md]"
    exit 1
fi

echo "[GE2.5] Framework Analysis Quality Gate"

fail_complete() { echo "  [FAIL-COMPLETE] $1"; echo "[GE2.5] RESULT: COMPLETE FAILURE（静默回退全部提取器）"; exit 1; }
fail_partial()  { echo "  [WARN-PARTIAL] $1"; PARTIAL=1; }
pass()          { echo "  [PASS] $1"; }

PARTIAL=0

# ── 完全失败类：profile 存在性 ──
[ -f "$PROFILE" ] || fail_complete "profile 不存在: $PROFILE"
pass "profile 存在: $PROFILE"

# ── 完全失败类：YAML 可解析（python3+yaml 可用时做真解析，否则结构检查兜底）──
PARSE_OK=true
if command -v python3 &>/dev/null && python3 -c "import yaml" &>/dev/null; then
    if ! python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$PROFILE" 2>/dev/null; then
        PARSE_OK=false
    fi
else
    # 兜底：制表符开头行视为非法 YAML 结构（不依赖 grep -P）
    if grep -q "^$(printf '\t')" "$PROFILE" 2>/dev/null; then
        PARSE_OK=false
    fi
fi
[ "$PARSE_OK" = true ] || fail_complete "YAML 无法解析: $PROFILE"
pass "YAML 可解析"

# ── 完全失败类：必填字段 ──
for field in service framework_signals extraction_plan unknowns; do
    grep -q "^${field}:" "$PROFILE" || fail_complete "必填字段缺失: $field"
done
pass "必填字段齐全（service/framework_signals/extraction_plan/unknowns）"

grep -q 'extractors:' "$PROFILE" || fail_complete "extraction_plan.extractors 缺失"

# ── 完全失败类：confidence 枚举合法性 ──
BAD_CONF=$(grep -E '^[[:space:]]*confidence:' "$PROFILE" | grep -vcE '^[[:space:]]*confidence:[[:space:]]*(high|medium|low|none)[[:space:]]*$' || true)
if [ "${BAD_CONF:-0}" -gt 0 ]; then
    fail_complete "$BAD_CONF 个 confidence 值非法（须为 high/medium/low/none）"
fi

# ── 部分失败类：medium+ 信号必须附 ≥1 条 review_basis ──
SIGNAL_COUNT=$(grep -cE '^[[:space:]]*-[[:space:]]+protocol:' "$PROFILE" || true)
MEDIUM_PLUS=$(grep -cE '^[[:space:]]*confidence:[[:space:]]*(high|medium)' "$PROFILE" || true)
BASIS_COUNT=$(grep -cE '^[[:space:]]*review_basis:' "$PROFILE" || true)
echo "  [INFO] signals=${SIGNAL_COUNT:-0}, medium+=${MEDIUM_PLUS:-0}, review_basis 块=${BASIS_COUNT:-0}"
if [ "${MEDIUM_PLUS:-0}" -gt "${BASIS_COUNT:-0}" ]; then
    fail_partial "evidence 缺失：$((MEDIUM_PLUS - BASIS_COUNT)) 个 medium+ 信号无 review_basis"
else
    pass "medium+ 信号均有 review_basis"
fi

# ── 部分失败类：skip_reason 记录 ──
if ! grep -q 'skip_reason:' "$PROFILE"; then
    fail_partial "skip_reason 缺失（无法追溯跳过理由）"
fi

# ── 部分失败类：自审报告产出 ──
if [ -n "$REVIEW" ]; then
    if [ -f "$REVIEW" ]; then
        pass "自审报告存在: $REVIEW"
    else
        fail_partial "自审报告未产出: $REVIEW"
    fi
fi

echo ""
if [ "$PARTIAL" -gt 0 ]; then
    echo "[GE2.5] RESULT: PARTIAL FAILURE（警告 + 回退全部提取器）"
    exit 2
fi
echo "[GE2.5] RESULT: PASS（可按 extraction_plan 精准提取）"
exit 0
