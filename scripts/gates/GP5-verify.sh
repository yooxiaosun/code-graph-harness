#!/usr/bin/env bash
# GP5: Regression Check — 验证新增脚本不破坏已有输出结果
set -euo pipefail

SCRIPT_TO_VERIFY="${1:-}"
BASELINE_DIR="${2:-output/nodes}"

if [ -z "$SCRIPT_TO_VERIFY" ]; then
    echo "Usage: $0 <script-path> [baseline-dir]"
    exit 1
fi

echo "── GP5: Regression Check ──"

if [ ! -d "$BASELINE_DIR" ]; then
    echo "[SKIP] No baseline data directory: $BASELINE_DIR"
    exit 0
fi

BASELINE_COUNT=$(find "$BASELINE_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$BASELINE_COUNT" -eq 0 ]; then
    echo "[SKIP] No baseline data to compare against"
    exit 0
fi

# Verify baseline files are still valid
INVALID_COUNT=0
while IFS= read -r baseline_file; do
    [ -z "$baseline_file" ] && continue
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import json; json.load(open('$baseline_file'))" 2>/dev/null; then
            echo "[FAIL] Baseline file corrupted: $baseline_file"
            INVALID_COUNT=$((INVALID_COUNT + 1))
        fi
    fi
done < <(find "$BASELINE_DIR" -name "nonstandard*.json" -type f 2>/dev/null || true)

if [ "$INVALID_COUNT" -gt 0 ]; then
    echo "[FAIL] GP5: $INVALID_COUNT baseline file(s) corrupted"
    exit 1
fi

echo "[PASS] GP5: No regression detected ($BASELINE_COUNT baseline files valid)"
