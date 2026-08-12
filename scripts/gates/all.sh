#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
# Harness Gate Runner — 工程门禁 G0/G4/G5（v2 精简后唯一默认集）
# 流程门禁见 gate-criteria.md（G-E1 至 G-E5）；自适应门禁见 GP1-GP5
# ═══════════════════════════════════════════════════════════
#
# Usage:
#   bash scripts/gates/all.sh                            # 默认：G0 G4 G5
#   bash scripts/gates/all.sh --dry-run                  # check which scripts exist, don't run
#   bash scripts/gates/all.sh --gate G4                  # run a single gate
#   bash scripts/gates/all.sh --gates G0,G5              # run a subset of gates
#   bash scripts/gates/all.sh --allow-skip               # exit 0 even when gates are skipped

DRY_RUN=0
SINGLE_GATE=""
SUBSET=""
ALLOW_SKIP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)     DRY_RUN=1; shift ;;
    --profile)
      if [ "${2:-}" != "fast-lane" ]; then
        echo "[FAIL] v2 已移除门禁 profile 体系，仅保留默认集 G0 G4 G5" >&2
        exit 2
      fi
      shift 2 ;;
    --gate)        SINGLE_GATE="$2"; shift 2 ;;
    --gates)       SUBSET="$2"; shift 2 ;;
    --allow-skip)  ALLOW_SKIP=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]
  --gate <id>        run a single gate (e.g. G4)
  --gates <ids>      comma-separated subset (e.g. G0,G5)
  --allow-skip       exit 0 when gates are skipped (default: exit 2)
  --dry-run          check scripts exist, don't run
  -h, --help         show this help
EOF
      exit 0 ;;
    *) echo "[FAIL] unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Resolve gates to run ────────────────────────────────────────────────
if [ -n "$SINGLE_GATE" ]; then
  GATES=("$SINGLE_GATE")
elif [ -n "$SUBSET" ]; then
  IFS=',' read -ra GATES <<< "$SUBSET"
else
  GATES=(G0 G4 G5)
fi

echo "=== Harness Gate Runner (gates=${GATES[*]}) ==="
echo ""

failures=0
skipped=0
passed=0

for gate in "${GATES[@]}"; do
  script="scripts/gates/${gate}-verify.sh"
  if [ ! -f "$script" ]; then
    echo "[SKIP] $gate: missing $script"
    skipped=$((skipped + 1))
    continue
  fi
  if [ ! -x "$script" ]; then
    # Some generated scripts may not be chmod +x'd on Windows; bash doesn't actually
    # require +x for explicit 'bash script.sh' invocation, so this is a soft check.
    chmod +x "$script" 2>/dev/null || true
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] $gate: $script schedulable"
    continue
  fi
  echo "── $gate ────────────────────────────────────────"
  if bash "$script"; then
    passed=$((passed + 1))
  else
    echo "[FAIL] $gate returned non-zero"
    failures=$((failures + 1))
  fi
  echo ""
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[OK] dry-run complete — ${#GATES[@]} gate(s) checked"
  exit 0
fi

echo "=== Summary ==="
echo "  passed:  $passed"
echo "  skipped: $skipped (missing scripts)"
echo "  failed:  $failures"
echo ""

if [ "$failures" -gt 0 ]; then
  echo "[FAIL] $failures gate(s) failed"
  exit 1
fi

if [ "$skipped" -gt 0 ]; then
  echo "[WARN] $skipped gate(s) skipped — skipped gates are not verified; use --allow-skip to suppress this warning"
  if [ "$ALLOW_SKIP" -eq 1 ]; then
    exit 0
  fi
  exit 2
fi

echo "[OK] all gates passed"
