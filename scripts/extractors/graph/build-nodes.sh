#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTORS_DIR="$SCRIPT_DIR/.."

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
NODES_DIR="${3:-output/nodes}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [nodes-dir]"
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "[ERROR] Repo path not found: $REPO_PATH" >&2
    exit 1
fi

SVC_NODE_DIR="$NODES_DIR/$SERVICE_NAME"
mkdir -p "$SVC_NODE_DIR"

echo "[NODES] Extracting $SERVICE_NAME ($REPO_PATH)..."

# Phase A: Run all extractors in parallel
pids=()

for std in extract-dubbo extract-sofarpc extract-grpc extract-rest; do
    bash "$EXTRACTORS_DIR/standard/${std}.sh" "$SERVICE_NAME" "$REPO_PATH" "$NODES_DIR" &
    pids+=($!)
done

for ns in extract-http-client extract-mq extract-custom; do
    bash "$EXTRACTORS_DIR/nonstandard/${ns}.sh" "$SERVICE_NAME" "$REPO_PATH" "$NODES_DIR" &
    pids+=($!)
done

# Wait for all extractors and track failures
FAILURES=0
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        FAILURES=$((FAILURES + 1))
    fi
done

# Phase B: Tags (serial, after all extractors)
bash "$EXTRACTORS_DIR/tags/extract-tags.sh" "$SERVICE_NAME" "$REPO_PATH" "$NODES_DIR"

# Phase C: Check for unknown patterns
if [ -f "$SVC_NODE_DIR/nonstandard-custom.json" ]; then
    UNKNOWN_COUNT=$(grep -c "unknown-pattern" "$SVC_NODE_DIR/nonstandard-custom.json" 2>/dev/null || echo "0")
    if [ "$UNKNOWN_COUNT" -gt 0 ]; then
        echo "  [AI-REQUIRED] $UNKNOWN_COUNT unknown pattern(s) detected → use templates/analyze-pattern.md"
    fi
fi

echo "[NODES] $SERVICE_NAME: $FAILURES extractors failed"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
