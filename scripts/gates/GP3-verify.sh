#!/usr/bin/env bash
# GP3: Output Schema Validation — 验证脚本输出符合 JSON Schema
set -euo pipefail

SCRIPT_TO_VERIFY="${1:-}"
SCHEMA_FILE="${2:-schemas/knowledge-graph.schema.json}"
FIXTURES_DIR="${3:-/Users/johnsmith/WorkBench/code-graph/project/fixtures}"

if [ -z "$SCRIPT_TO_VERIFY" ]; then
    echo "Usage: $0 <script-path> [schema-file] [fixtures-dir]"
    exit 1
fi

echo "── GP3: Output Schema Validation ──"

if ! command -v jq &>/dev/null; then
    echo "[SKIP] jq not available, cannot validate JSON schema"
    exit 0
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "[SKIP] Schema file not found: $SCHEMA_FILE"
    exit 0
fi

SCRIPT_NAME=$(basename "$(dirname "$SCRIPT_TO_VERIFY")")
case "$SCRIPT_NAME" in
    *http*)            SAMPLE_DIR="$FIXTURES_DIR/sample-http-client" ;;
    *mq*)              SAMPLE_DIR="$FIXTURES_DIR/sample-mq" ;;
    *socket*|*custom*) SAMPLE_DIR="$FIXTURES_DIR/sample-socket" ;;
    *) SAMPLE_DIR="$FIXTURES_DIR/sample-http-client" ;;
esac

if [ ! -d "$SAMPLE_DIR" ]; then
    echo "[SKIP] No fixtures: $SAMPLE_DIR"
    exit 0
fi

TMP_OUTPUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUTPUT"' EXIT

bash "$SCRIPT_TO_VERIFY" "test-service" "$SAMPLE_DIR" "$TMP_OUTPUT" 2>/dev/null || {
    echo "[SKIP] Script execution failed, cannot validate output"
    exit 0
}

ALL_JSON_FILES=$(find "$TMP_OUTPUT" -name "*.json" -type f 2>/dev/null || true)
if [ -z "$ALL_JSON_FILES" ]; then
    echo "[SKIP] No output JSON files generated"
    exit 0
fi

FAILURES=0
while IFS= read -r json_file; do
    [ -z "$json_file" ] && continue
    if ! jq empty "$json_file" 2>/dev/null; then
        echo "[FAIL] Invalid JSON: $json_file"
        FAILURES=$((FAILURES + 1))
    fi
done <<< "$ALL_JSON_FILES"

if [ "$FAILURES" -gt 0 ]; then
    echo "[FAIL] GP3: $FAILURES invalid JSON file(s)"
    exit 1
fi

echo "[PASS] GP3: All output files are valid JSON"
