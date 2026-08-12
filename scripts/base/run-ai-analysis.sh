#!/usr/bin/env bash
# run-ai-analysis — 原子能力工具：提取 AI 迭代分析 state.yaml 的字段值（纯机械，不含判断）
# 用法: bash scripts/base/run-ai-analysis.sh <state.yaml> [field]
#   无 field 时输出全部关键字段（供 AI 读后按 ai-analysis-harness.md 自主判断）
#   有 field 时只输出单个字段值（供其他机械工具消费）
#
# 注意: 本工具不含任何 pass/continue/bail-out 判定。是否收束由 AI 读
#   templates/ai-analysis-harness.md 的收敛规则后自主判断（md-first 哲学）。
set -uo pipefail

STATE_FILE="${1:-}"
FIELD="${2:-}"

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
    echo "Usage: $0 <state.yaml> [field]" >&2
    exit 2
fi

if ! command -v python3 &>/dev/null; then
    echo "[ABORT] python3 not available (needed for YAML parse)" >&2
    exit 1
fi

dump_all() {
    python3 - "$STATE_FILE" <<'PY'
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
c = d.get('converged') or {}
# 顶层字段
for k in ['round', 'service', 'scenario', 'findings_count', 'delta_from_previous',
          'items_changed_class', 'items_evidence_missing', 'items_flip_flop',
          'overall_status', 'bail_outs']:
    if k in d:
        print(f"{k}={d[k]}")
# 收敛判定子字段
for k, v in c.items():
    print(f"{k}={str(v).lower()}")
# 分布统计
for dk in ['evidence_quality_distribution', 'confidence_distribution']:
    dist = d.get(dk)
    if isinstance(dist, dict):
        for k, v in dist.items():
            print(f"{dk}.{k}={v}")
PY
}

dump_field() {
    python3 - "$STATE_FILE" "$FIELD" <<'PY'
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
field = sys.argv[2]
if field in d:
    v = d[field]
    print(str(v).lower())
    sys.exit(0)
# converged 子字段
c = d.get('converged') or {}
if field in c:
    print(str(c[field]).lower())
    sys.exit(0)
sys.exit(1)
PY
}

if [ -n "$FIELD" ]; then
    dump_field
else
    dump_all
fi
