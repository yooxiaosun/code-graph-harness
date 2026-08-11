#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../base/java-parser.sh"
source "$SCRIPT_DIR/../base/json-writer.sh"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
OUTPUT_DIR="${3:-output/nodes}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [output-dir]"
    exit 1
fi

PROVIDER_FILE="$OUTPUT_DIR/$SERVICE_NAME/grpc-provider.json"
CONSUMER_FILE="$OUTPUT_DIR/$SERVICE_NAME/grpc-consumer.json"
mkdir -p "$(dirname "$PROVIDER_FILE")"

PROVIDER_COUNT=0
CONSUMER_COUNT=0

json_array_init "$PROVIDER_FILE"
json_array_init "$CONSUMER_FILE"

# Parse .proto files for provider definitions
while IFS= read -r proto_file; do
    [ -z "$proto_file" ] && continue
    REL_PATH="${proto_file#$REPO_PATH/}"

    PACKAGE=$(grep -m1 "^package " "$proto_file" | sed 's/package\s*//' | sed 's/;$//' | tr -d ' ' || echo "")
    CURRENT_SERVICE=""
    CURRENT_LN=0

    while IFS= read -r line; do
        LN=$(echo "$line" | cut -d: -f1)
        CONTENT=$(echo "$line" | cut -d: -f2-)

        if echo "$CONTENT" | grep -qE "^\s*service\s+\w+"; then
            CURRENT_SERVICE=$(echo "$CONTENT" | sed 's/^\s*service\s*//' | sed 's/\s*{.*//' | sed 's/\s*$//')
            CURRENT_LN=$LN
        fi

        if [ -n "$CURRENT_SERVICE" ] && echo "$CONTENT" | grep -qE "^\s*rpc\s+\w+"; then
            RPC_NAME=$(echo "$CONTENT" | sed 's/^\s*rpc\s*//' | sed 's/\s*(.*//')
            STREAM_MODE="unary"
            if echo "$CONTENT" | grep -q "stream"; then
                before_paren=$(echo "$CONTENT" | sed 's/(.*//')
                if echo "$before_paren" | grep -q "stream"; then
                    STREAM_MODE="server-streaming"
                fi
                after_paren=$(echo "$CONTENT" | sed 's/.*)\s*returns//')
                if echo "$after_paren" | grep -q "stream"; then
                    STREAM_MODE="client-streaming"  # simplified
                fi
            fi

            FULL_SERVICE="${PACKAGE}.${CURRENT_SERVICE}"
            [ -z "$PACKAGE" ] && FULL_SERVICE="$CURRENT_SERVICE"
            NODE_ID="${SERVICE_NAME}::${FULL_SERVICE}.${RPC_NAME}"
            RPC_LN=$((CURRENT_LN + 1))
            NODE_JSON=$(node_interface_json "$NODE_ID" "$RPC_NAME" "$SERVICE_NAME" "grpc" "provider" "$FULL_SERVICE" "$CONTENT" "$REL_PATH:$RPC_LN" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
        fi
    done < <(grep -n '' "$proto_file")
done < <(find "$REPO_PATH" -name "*.proto" -not -path "*/.git/*" 2>/dev/null || true)

# Scan Java implementations of BindableService
while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    IS_GRPC_PROVIDER=$(found_in_file "$java_file" "BindableService")
    if [ "$IS_GRPC_PROVIDER" = "true" ]; then
        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            [ -z "$METHOD_NAME" ] && continue
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${METHOD_NAME}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$SERVICE_NAME" "grpc" "provider" "$CLASS_NAME" "$SIG" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
        done < <(extract_methods "$java_file")
    fi

    # gRPC consumer: ManagedChannel or stub creation
    IS_GRPC_CONSUMER=$(found_in_file "$java_file" "ManagedChannel\|AbstractBlockingStub\|AbstractFutureStub\|AbstractStub")
    if [ "$IS_GRPC_CONSUMER" = "true" ]; then
        while IFS= read -r field_info; do
            [ -z "$field_info" ] && continue
            LN=$(echo "$field_info" | cut -d: -f1)
            FIELD=$(echo "$field_info" | cut -d: -f2-)
            STUB_CLASS=$(echo "$FIELD" | grep -oE '\S+Stub' | head -1 || echo "grpc-stub")
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${STUB_CLASS}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$STUB_CLASS" "$SERVICE_NAME" "grpc" "consumer" "$CLASS_NAME" "$FIELD" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
            CONSUMER_COUNT=$((CONSUMER_COUNT + 1))
        done < <(extract_field_annotations "$java_file" "Autowired\|Inject" 2>/dev/null || true)
        # Also check for field declarations matching stub patterns
        if [ "$CONSUMER_COUNT" -eq 0 ]; then
            grep -nE "ManagedChannel|BlockingStub|FutureStub|AbstractStub" "$java_file" | head -5 | while IFS=: read -r ln _; do
                FIELD_LINE=$(sed -n "${ln}p" "$java_file" | tr -d ';{}')
                STUB_CLASS=$(echo "$FIELD_LINE" | grep -oE '\S+Stub\b|\S+Channel\b' | head -1 || echo "grpc-stub")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${STUB_CLASS}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "$STUB_CLASS" "$SERVICE_NAME" "grpc" "consumer" "$CLASS_NAME" "$FIELD_LINE" "$REL_PATH:$ln" "" "" "[]")
                json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
            done
            CONSUMER_COUNT=$(grep -cE "ManagedChannel|BlockingStub|FutureStub|AbstractStub" "$java_file" || echo "0")
        fi
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$PROVIDER_FILE"
json_array_close "$CONSUMER_FILE"

echo "[gRPC] $SERVICE_NAME: $PROVIDER_COUNT providers, $CONSUMER_COUNT consumers"
