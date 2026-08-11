#!/usr/bin/env bash
# GP4: Recall Verification — 对比预期输出，验证召回率
set -euo pipefail

SCRIPT_TO_VERIFY="${1:-}"
FIXTURES_DIR="${2:-scripts/extractors/nonstandard/fixtures}"

if [ -z "$SCRIPT_TO_VERIFY" ]; then
    echo "Usage: $0 <script-path> [fixtures-dir]"
    exit 1
fi

echo "── GP4: Recall Verification ──"

EXPECTED_DIR="$FIXTURES_DIR/expected"
if [ ! -d "$EXPECTED_DIR" ]; then
    echo "[SKIP] No expected output directory: $EXPECTED_DIR"
    exit 0
fi

SCRIPT_NAME=$(basename "$SCRIPT_TO_VERIFY" .sh)
EXPECTED_FILE=""

case "$SCRIPT_NAME" in
    extract-http-client|*http*)   EXPECTED_FILE="$EXPECTED_DIR/http-client.json"; SAMPLE_DIR="$FIXTURES_DIR/sample-http-client" ;;
    extract-mq|*mq*)              EXPECTED_FILE="$EXPECTED_DIR/mq.json"; SAMPLE_DIR="$FIXTURES_DIR/sample-mq" ;;
    extract-custom|*socket*|*custom*) EXPECTED_FILE="$EXPECTED_DIR/socket.json"; SAMPLE_DIR="$FIXTURES_DIR/sample-socket" ;;
    *) echo "[SKIP] Unknown script type: $SCRIPT_NAME"; exit 0 ;;
esac

if [ ! -f "$EXPECTED_FILE" ]; then
    echo "[SKIP] No expected file: $EXPECTED_FILE"
    exit 0
fi

if [ ! -d "$SAMPLE_DIR" ]; then
    echo "[SKIP] No sample directory: $SAMPLE_DIR"
    exit 0
fi

TMP_OUTPUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUTPUT"' EXIT

bash "$SCRIPT_TO_VERIFY" "test-service" "$SAMPLE_DIR" "$TMP_OUTPUT" 2>/dev/null || {
    echo "[FAIL] Script execution failed"
    exit 1
}

ACTUAL_FILE=$(find "$TMP_OUTPUT" -name "*.json" -type f | head -1)
if [ -z "$ACTUAL_FILE" ]; then
    echo "[FAIL] No output generated"
    exit 1
fi

EXPECTED_COUNT=$(jq 'length' "$EXPECTED_FILE" 2>/dev/null || echo "0")
ACTUAL_COUNT=$(jq 'length' "$ACTUAL_FILE" 2>/dev/null || echo "0")

echo "  Expected items: $EXPECTED_COUNT, Actual items: $ACTUAL_COUNT"

if [ "$ACTUAL_COUNT" -ge "$EXPECTED_COUNT" ] 2>/dev/null; then
    echo "[PASS] GP4: Output count meets expectation ($ACTUAL_COUNT >= $EXPECTED_COUNT)"
else
    echo "[WARN] GP4: Output count below expectation ($ACTUAL_COUNT < $EXPECTED_COUNT)"
    echo "[WARN] This may indicate incomplete pattern coverage — AI re-analysis recommended"
    exit 1
fi
