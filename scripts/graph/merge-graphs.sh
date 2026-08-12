#!/usr/bin/env bash
set -euo pipefail

# Incremental Merge: detect changed services → snapshot → full rebuild
# Operates on the Layer model: checks nodes/ for changes, edges/ and calibration/ rebuild as needed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../base/json-writer.sh"
source "$SCRIPT_DIR/../base/repo-manager.sh"

NODES_DIR="${1:-output/nodes}"
GRAPH_DIR="${2:-output/knowledge-graph}"
EDGES_DIR="output/edges"
CALIBRATION_DIR="output/calibration"
LATEST_GRAPH="${GRAPH_DIR}/latest.json"

echo "[MERGE] Incremental merge check..."

if [ ! -f "$LATEST_GRAPH" ]; then
    echo "  No existing graph — performing full build"
    bash "$SCRIPT_DIR/assemble-graph.sh" "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR" "$LATEST_GRAPH"
    exit $?
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERSION_TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
SNAPSHOT_FILE="${GRAPH_DIR}/v1.0.0-${VERSION_TIMESTAMP}.json"

# Detect changed services: any node file newer than latest graph
CHANGED_SERVICES=()
for service_dir in "$NODES_DIR"/*/; do
    [ -d "$service_dir" ] || continue
    SERVICE_NAME=$(basename "$service_dir")
    if find "$service_dir" -name "*.json" -newer "$LATEST_GRAPH" 2>/dev/null | grep -q .; then
        CHANGED_SERVICES+=("$SERVICE_NAME")
    fi
done

# Also check if repos have changed
if [ -d "output/repos" ]; then
    for repo_path in output/repos/*/; do
        [ -d "$repo_path" ] || continue
        if detect_changes "$repo_path" 2>/dev/null; then
            REPO_NAME=$(basename "$repo_path")
            if ! printf '%s\n' "${CHANGED_SERVICES[@]}" | grep -qxF "$REPO_NAME" 2>/dev/null; then
                echo "  [NOTE] $REPO_NAME has uncommitted changes or changed since last extraction"
            fi
        fi
    done
fi

if [ ${#CHANGED_SERVICES[@]} -eq 0 ]; then
    echo "  No services changed, graph is up to date"
    exit 0
fi

echo "  Changed services: ${CHANGED_SERVICES[*]}"

# Save snapshot before rebuild
cp "$LATEST_GRAPH" "$SNAPSHOT_FILE" 2>/dev/null || true

# Rebuild edges and calibration (edges may cross services → must rebuild)
if [ -d "$NODES_DIR" ] && [ "$(ls -A "$NODES_DIR" 2>/dev/null)" ]; then
    bash "$SCRIPT_DIR/build-edges.sh" "$NODES_DIR" "$EDGES_DIR" 2>/dev/null || true
    bash "$SCRIPT_DIR/compute-stats.sh" "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR" 2>/dev/null || true
fi

bash "$SCRIPT_DIR/assemble-graph.sh" "$NODES_DIR" "$EDGES_DIR" "$CALIBRATION_DIR" "$LATEST_GRAPH"

SNAPSHOT_COUNT=$(find "$GRAPH_DIR" -name "v1.0.0-*.json" 2>/dev/null | wc -l | tr -d ' ')

echo "[MERGE] Graph updated: $LATEST_GRAPH"
echo "  Snapshot: $SNAPSHOT_FILE"
echo "  Total snapshots: $SNAPSHOT_COUNT"
