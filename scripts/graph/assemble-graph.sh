#!/usr/bin/env bash
set -euo pipefail

# Assemble: Take Layer 1 nodes + Layer 2 edges + Layer 3 calibration → final graph

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../base/json-writer.sh"

NODES_DIR="${1:-output/nodes}"
EDGES_DIR="${2:-output/edges}"
CALIBRATION_DIR="${3:-output/calibration}"
OUTPUT_FILE="${4:-output/knowledge-graph/latest.json}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[ASSEMBLE] Building final graph..."

if [ ! -d "$NODES_DIR" ]; then
    echo "[ERROR] Nodes directory not found: $NODES_DIR" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

TMP_NODES=$(mktemp)
TMP_EDGES=$(mktemp)
trap 'rm -f "$TMP_NODES" "$TMP_EDGES"' EXIT

json_array_init "$TMP_NODES"
json_array_init "$TMP_EDGES"

NODE_FIRST=true
EDGE_FIRST=true
TOTAL_SERVICES=0
TOTAL_INTERFACES=0
TOTAL_EDGES=0
DUBBO_COUNT=0
SOFA_COUNT=0
GRPC_COUNT=0
REST_COUNT=0
NS_COUNT=0

add_node() {
    if [ "$NODE_FIRST" = true ]; then NODE_FIRST=false; echo "  $1" >> "$TMP_NODES"
    else echo "  ,$1" >> "$TMP_NODES"; fi
}

add_edge() {
    if [ "$EDGE_FIRST" = true ]; then EDGE_FIRST=false; echo "  $1" >> "$TMP_EDGES"
    else echo "  ,$1" >> "$TMP_EDGES"; fi
}

# ── Service Nodes + Interface Nodes ──
used_service_ids=()
for service_dir in "$NODES_DIR"/*/; do
    [ -d "$service_dir" ] || continue
    SERVICE_NAME=$(basename "$service_dir")
    TAGS_JSON="[]"
    [ -f "$service_dir/tags.json" ] && TAGS_JSON=$(cat "$service_dir/tags.json" 2>/dev/null || echo "[]")

    SV_NODE=$(node_service_json "$SERVICE_NAME" "$SERVICE_NAME" "" "" "maven" "$TAGS_JSON")
    add_node "$SV_NODE"
    used_service_ids+=("$SERVICE_NAME")
    TOTAL_SERVICES=$((TOTAL_SERVICES + 1))

    # All interface nodes
    for json_file in "$service_dir"/*.json; do
        [ -f "$json_file" ] || continue
        [ "$(basename "$json_file")" = "tags.json" ] && continue

        proto=""
        case "$(basename "$json_file")" in
            dubbo-*)  proto="dubbo";  ;;
            sofarpc-*) proto="sofarpc"; ;;
            grpc-*)   proto="grpc";   ;;
            rest-*)   proto="rest";   ;;
            nonstandard-http*) proto="http"; ;;
            nonstandard-mq*)   proto="mq";   ;;
            nonstandard-custom*) proto="custom"; ;;
            *) proto="unknown" ;;
        esac

        while IFS= read -r node; do
            [ -z "$node" ] && continue
            add_node "$node"
            TOTAL_INTERFACES=$((TOTAL_INTERFACES + 1))
            case "$proto" in
                dubbo) DUBBO_COUNT=$((DUBBO_COUNT + 1)) ;;
                sofarpc) SOFA_COUNT=$((SOFA_COUNT + 1)) ;;
                grpc) GRPC_COUNT=$((GRPC_COUNT + 1)) ;;
                rest) REST_COUNT=$((REST_COUNT + 1)) ;;
                http|mq|custom) NS_COUNT=$((NS_COUNT + 1)) ;;
            esac
        done < <(jq -c '.[]' "$json_file" 2>/dev/null || true)
    done
done

# ── RPC Edges ──
if [ -f "$EDGES_DIR/rpc-edges.json" ]; then
    while IFS= read -r edge; do
        [ -z "$edge" ] && continue
        add_edge "$edge"
        TOTAL_EDGES=$((TOTAL_EDGES + 1))
    done < <(jq -c '.[]' "$EDGES_DIR/rpc-edges.json" 2>/dev/null || true)
fi

# ── Nonstandard Edges ──
if [ -f "$EDGES_DIR/nonstandard-edges.json" ]; then
    while IFS= read -r edge; do
        [ -z "$edge" ] && continue
        add_edge "$edge"
        TOTAL_EDGES=$((TOTAL_EDGES + 1))
    done < <(jq -c '.[]' "$EDGES_DIR/nonstandard-edges.json" 2>/dev/null || true)
fi

# Close arrays
echo "]" >> "$TMP_NODES"
echo "]" >> "$TMP_EDGES"

# ── Calibration Score ──
CAL_SCORE=0
CAL_RATING="UNKNOWN"
if [ -f "$CALIBRATION_DIR/calibration-report.json" ]; then
    CAL_SCORE=$(jq -r '.overallScore // 0' "$CALIBRATION_DIR/calibration-report.json" 2>/dev/null || echo "0")
    CAL_RATING=$(jq -r '.rating // "UNKNOWN"' "$CALIBRATION_DIR/calibration-report.json" 2>/dev/null || echo "UNKNOWN")
fi

# ── Stats ──
STATS=$(write_stats_json "" "$TOTAL_SERVICES" "$TOTAL_INTERFACES" "$TOTAL_EDGES" "$DUBBO_COUNT" "$SOFA_COUNT" "$GRPC_COUNT" "$REST_COUNT" "$NS_COUNT")

# ── Assemble ──
cat > "$OUTPUT_FILE" <<GRAPH
{
  "version": "1.0",
  "generatedAt": "$TIMESTAMP",
  "calibrationScore": $CAL_SCORE,
  "calibrationRating": "$CAL_RATING",
  "stats": $STATS,
  "nodes": $(cat "$TMP_NODES"),
  "edges": $(cat "$TMP_EDGES")
}
GRAPH

echo "[ASSEMBLE] Graph written: $OUTPUT_FILE"
echo "  Services: $TOTAL_SERVICES, Interfaces: $TOTAL_INTERFACES, Edges: $TOTAL_EDGES"
echo "  Dubbo: $DUBBO_COUNT, SOFA: $SOFA_COUNT, gRPC: $GRPC_COUNT, REST: $REST_COUNT, NS: $NS_COUNT"
echo "  Calibration: $CAL_SCORE ($CAL_RATING)"
