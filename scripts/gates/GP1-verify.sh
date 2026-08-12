#!/usr/bin/env bash
# GP1: Syntax Check — 验证脚本语法正确
set -euo pipefail

SCRIPT_TO_VERIFY="${1:-}"

if [ -z "$SCRIPT_TO_VERIFY" ]; then
    echo "Usage: $0 <script-path>"
    exit 1
fi

echo "── GP1: Syntax Check ──"

if [ ! -f "$SCRIPT_TO_VERIFY" ]; then
    echo "[FAIL] $SCRIPT_TO_VERIFY not found"
    exit 1
fi

ERROR_LOG=$(mktemp)
trap 'rm -f "$ERROR_LOG"' EXIT

if ! bash -n "$SCRIPT_TO_VERIFY" 2>"$ERROR_LOG"; then
    echo "[FAIL] Syntax errors in $SCRIPT_TO_VERIFY:"
    cat "$ERROR_LOG"
    exit 1
fi

if ! head -1 "$SCRIPT_TO_VERIFY" | grep -q "bash"; then
    echo "[FAIL] Missing shebang line"
    exit 1
fi

if ! grep -q "set -euo pipefail" "$SCRIPT_TO_VERIFY"; then
    echo "[WARN] Missing 'set -euo pipefail' safeguard"
fi

echo "[PASS] GP1: Script syntax is valid"
