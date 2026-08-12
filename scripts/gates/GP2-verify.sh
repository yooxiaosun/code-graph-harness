#!/usr/bin/env bash
# GP2: Sandbox Execution — 在沙箱样本上执行脚本，验证不报错
set -euo pipefail

SCRIPT_TO_VERIFY="${1:-}"
FIXTURES_DIR="${2:-.harness/fixtures}"

if [ -z "$SCRIPT_TO_VERIFY" ]; then
    echo "Usage: $0 <script-path> [fixtures-dir]"
    exit 1
fi

echo "── GP2: Sandbox Execution ──"

if [ ! -f "$SCRIPT_TO_VERIFY" ]; then
    echo "[FAIL] $SCRIPT_TO_VERIFY not found"
    exit 1
fi

# Determine which sample to use based on script path (提取器统一命名 extract.sh，按协议目录匹配)
SCRIPT_NAME=$(basename "$(dirname "$SCRIPT_TO_VERIFY")")
SAMPLE_DIR=""

case "$SCRIPT_NAME" in
    *http*)                       SAMPLE_DIR="$FIXTURES_DIR/sample-http-client" ;;
    *mq*)                         SAMPLE_DIR="$FIXTURES_DIR/sample-mq" ;;
    *socket*|*custom*)            SAMPLE_DIR="$FIXTURES_DIR/sample-socket" ;;
    *)                            SAMPLE_DIR="$FIXTURES_DIR/sample-http-client" ;;
esac

if [ ! -d "$SAMPLE_DIR" ]; then
    echo "[SKIP] No fixtures directory: $SAMPLE_DIR"
    exit 0
fi

TMP_OUTPUT=$(mktemp -d)
GP2_ERROR=$(mktemp)
trap 'rm -rf "$TMP_OUTPUT" "$GP2_ERROR"' EXIT

if bash "$SCRIPT_TO_VERIFY" "test-service" "$SAMPLE_DIR" "$TMP_OUTPUT" 2>"$GP2_ERROR"; then
    echo "[PASS] GP2: Script executed without errors"
    exit 0
else
    echo "[FAIL] GP2: Script execution failed:"
    cat "$GP2_ERROR"
    exit 1
fi
