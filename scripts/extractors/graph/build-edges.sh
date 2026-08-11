#!/usr/bin/env bash
set -euo pipefail

US=$'\37'

# Layer 2: Edge Building
# Reads Layer 1 InterfaceNodes → provider_pool → consumer matching → edges + unresolved

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../base/json-writer.sh"

NODES_DIR="${1:-output/nodes}"
EDGES_DIR="${2:-output/edges}"

if [ ! -d "$NODES_DIR" ]; then
    echo "[ERROR] Nodes directory not found: $NODES_DIR" >&2
    exit 1
fi

mkdir -p "$EDGES_DIR"

RPC_EDGES_FILE="$EDGES_DIR/rpc-edges.json"
NS_EDGES_FILE="$EDGES_DIR/nonstandard-edges.json"
UNRESOLVED_FILE="$EDGES_DIR/unresolved-consumers.json"
STATS_FILE="$EDGES_DIR/edge-stats.json"

PROVIDER_POOL=$(mktemp)
trap 'rm -f "$PROVIDER_POOL"' EXIT

TOTAL_CONSUMERS=0
MATCHED_COUNT=0
UNRESOLVED_COUNT=0
NS_EDGE_COUNT=0

echo "[EDGES] Building edges from $NODES_DIR ..."

json_array_init "$RPC_EDGES_FILE"
json_array_init "$NS_EDGES_FILE"
json_array_init "$UNRESOLVED_FILE"

# ── Phase A: Build Provider Pool ──
echo "  [Phase A] Building provider pool..."

while IFS= read -r provider_file; do
    [ -f "$provider_file" ] || continue
    service_name=$(echo "$provider_file" | sed 's|.*/nodes/||' | cut -d/ -f1)
    protocol=$(basename "$provider_file" | sed 's/-provider.json//')

    jq -r --arg svc "$service_name" --arg proto "$protocol" '
        .[] | [.id, .className, .name, $svc, $proto, .signature] | @tsv
    ' "$provider_file" 2>/dev/null | while IFS=$'\t' read -r node_id class_name method_name svc proto signature; do
        [ -z "$class_name" ] && continue
        [ "$class_name" = "null" ] && continue
        echo "${class_name}${US}${node_id}${US}${svc}${US}${proto}${US}${method_name}${US}${signature}"
    done
done < <(find "$NODES_DIR" -name "*-provider.json" -type f 2>/dev/null || true) > "$PROVIDER_POOL"

PROVIDER_COUNT=$(wc -l < "$PROVIDER_POOL" | tr -d ' ')
echo "    Provider pool: $PROVIDER_COUNT entries"

# ── Phase B: Consumer Matching ──
echo "  [Phase B] Matching consumers..."

FIRST_EDGE=true
FIRST_UNRESOLVED=true

for consumer_file in $(find "$NODES_DIR" -name "*-consumer.json" -type f 2>/dev/null || true); do
    [ -f "$consumer_file" ] || continue
    consumer_svc=$(echo "$consumer_file" | sed 's|.*/nodes/||' | cut -d/ -f1)
    c_protocol=$(basename "$consumer_file" | sed 's/-consumer.json//')

    while IFS= read -r consumer_obj; do
        [ -z "$consumer_obj" ] && continue
        c_id=$(echo "$consumer_obj" | jq -r '.id // empty' 2>/dev/null)
        c_class=$(echo "$consumer_obj" | jq -r '.className // empty' 2>/dev/null)
        c_method=$(echo "$consumer_obj" | jq -r '.name // empty' 2>/dev/null)
        c_path=$(echo "$consumer_obj" | jq -r '.path // empty' 2>/dev/null)

        [ -z "$c_id" ] && continue
        [ "$c_class" = "null" ] && c_class=""
        TOTAL_CONSUMERS=$((TOTAL_CONSUMERS + 1))

        matched=false

        if [ -n "$c_class" ]; then
            while IFS="$US" read -r p_class p_id p_svc p_proto p_method p_sig; do
                # Exact match
                if [ "$p_class" = "$c_class" ]; then
                    if [ "$consumer_svc" != "$p_svc" ]; then
                        edge=$(edge_rpc_json "$c_id" "$p_id" "$c_protocol" "$consumer_svc" "$p_svc" "$c_path")
                        json_array_add "$RPC_EDGES_FILE" "$edge" false
                        MATCHED_COUNT=$((MATCHED_COUNT + 1))
                        matched=true
                        break
                    fi
                fi
            done < "$PROVIDER_POOL"

            # Partial match: className contains
            if [ "$matched" = false ]; then
                while IFS="$US" read -r p_class p_id p_svc p_proto p_method p_sig; do
                    if echo "$p_class" | grep -qF "$c_class" 2>/dev/null; then
                        if [ "$consumer_svc" != "$p_svc" ]; then
                            edge=$(edge_rpc_json "$c_id" "$p_id" "$c_protocol" "$consumer_svc" "$p_svc" "$c_path")
                            json_array_add "$RPC_EDGES_FILE" "$edge" false
                            MATCHED_COUNT=$((MATCHED_COUNT + 1))
                            matched=true
                            break
                        fi
                    fi
                done < "$PROVIDER_POOL"
            fi
        fi

        if [ "$matched" = false ]; then
            unresolved_obj=$(cat <<UNR
{"consumer_node_id": $(json_escape "$c_id"), "class_name": $(json_escape "$c_class"), "from_service": $(json_escape "$consumer_svc"), "source_path": $(json_escape "$c_path"), "reason": "provider_not_found"}
UNR
)
            json_array_add "$UNRESOLVED_FILE" "$unresolved_obj" false
            UNRESOLVED_COUNT=$((UNRESOLVED_COUNT + 1))
        fi
    done < <(jq -c '.[]' "$consumer_file" 2>/dev/null || true)
done

json_array_close "$RPC_EDGES_FILE"
json_array_close "$UNRESOLVED_FILE"

echo "    Matched: $MATCHED_COUNT / $TOTAL_CONSUMERS"

# ── Phase C: Nonstandard Edges ──
echo "  [Phase C] Building nonstandard edges..."

for ns_file in $(find "$NODES_DIR" -name "nonstandard*.json" -type f 2>/dev/null || true); do
    [ -f "$ns_file" ] || continue
    ns_svc=$(echo "$ns_file" | sed 's|.*/nodes/||' | cut -d/ -f1)

    while IFS= read -r ns_node; do
        [ -z "$ns_node" ] && continue
        n_role=$(echo "$ns_node" | jq -r '.role // empty' 2>/dev/null)
        n_id=$(echo "$ns_node" | jq -r '.id // empty' 2>/dev/null)
        n_proto=$(echo "$ns_node" | jq -r '.protocol // empty' 2>/dev/null)
        n_path=$(echo "$ns_node" | jq -r '.path // empty' 2>/dev/null)
        n_http=$(echo "$ns_node" | jq -r '.httpPath // empty' 2>/dev/null)
        n_sig=$(echo "$ns_node" | jq -r '.signature // empty' 2>/dev/null)

        [ -z "$n_id" ] && continue

        if [ "$n_role" != "consumer" ] && [ "$n_role" != "producer" ]; then
            continue
        fi

        target="unknown"
        confidence=0.4
        pattern=""
        topic=""
        host_pattern=""

        if [ "$n_role" = "producer" ]; then
            if echo "$n_sig" | grep -qi "kafka"; then
                pattern="KafkaProducer"
                topic=$(echo "$n_sig" | grep -oE '"([^"]*topic[^"]*)"' | tr -d '"' || echo "")
                [ -z "$topic" ] && topic="unknown-topic"
                confidence=0.7
                target="kafka-broker"
            elif echo "$n_sig" | grep -qi "rabbit"; then
                pattern="RabbitTemplate"
                confidence=0.7
                target="rabbitmq-broker"
            elif echo "$n_sig" | grep -qi "rocket"; then
                pattern="RocketMQProducer"
                confidence=0.7
                target="rocketmq-broker"
            else
                pattern="mq-producer"
                target="mq-broker"
            fi
        fi

        if echo "$n_proto" | grep -qE "http|rest"; then
            if [ -n "$n_http" ] && [ "$n_http" != "null" ]; then
                host_pattern="$n_http"
                target=$(echo "$n_http" | sed 's|https\?://||' | cut -d/ -f1 | cut -d: -f1)
                confidence=0.85
            elif echo "$n_sig" | grep -qoE '"(https?://[^"]*)"' 2>/dev/null; then
                url=$(echo "$n_sig" | grep -oE '"(https?://[^"]*)"' | head -1 | tr -d '"')
                target=$(echo "$url" | sed 's|https\?://||' | cut -d/ -f1)
                confidence=0.8
            else
                target="unknown-http-target"
            fi
            pattern="http-client"
        elif echo "$n_proto" | grep -qE "mq"; then
            if [ -n "$topic" ] && [ "$topic" != "unknown-topic" ]; then
                confidence=$(( confidence + 0.1 ))
            fi
            pattern="mq-interaction"
        elif echo "$n_proto" | grep -qE "socket"; then
            confidence=0.6
            pattern="socket-call"
        elif echo "$n_proto" | grep -qE "custom"; then
            confidence=0.4
            pattern="custom-pattern"
        fi

        ns_edge=$(edge_nonstandard_json "$n_id" "$target" "$n_proto" "$confidence" "$ns_svc" "$target" "$pattern" "$n_path" "$topic" "$host_pattern")
        json_array_add "$NS_EDGES_FILE" "$ns_edge" false
        NS_EDGE_COUNT=$((NS_EDGE_COUNT + 1))
    done < <(jq -c '.[]' "$ns_file" 2>/dev/null || true)
done

json_array_close "$NS_EDGES_FILE"

echo "    Nonstandard edges: $NS_EDGE_COUNT"

# ── Phase D: Stats ──
MATCH_RATE="0"
if [ "$TOTAL_CONSUMERS" -gt 0 ]; then
    MATCH_RATE=$(echo "scale=4; $MATCHED_COUNT / $TOTAL_CONSUMERS" | bc 2>/dev/null || echo "0")
fi

cat > "$STATS_FILE" <<STATS
{
  "total_consumers": $TOTAL_CONSUMERS,
  "matched": $MATCHED_COUNT,
  "unresolved": $UNRESOLVED_COUNT,
  "match_rate": $MATCH_RATE,
  "nonstandard_edges": $NS_EDGE_COUNT
}
STATS

echo "[EDGES] Complete: $MATCHED_COUNT matched, $UNRESOLVED_COUNT unresolved, $NS_EDGE_COUNT nonstandard"
echo "  Match rate: $(echo "$MATCH_RATE * 100" | bc 2>/dev/null || echo "0")%"
