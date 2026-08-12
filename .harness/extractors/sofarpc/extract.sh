#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$ROOT_DIR/scripts/base/java-parser.sh"
source "$ROOT_DIR/scripts/base/json-writer.sh"

SERVICE_NAME="${1:-}"
REPO_PATH="${2:-.}"
OUTPUT_DIR="${3:-output/nodes}"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> <repo-path> [output-dir]"
    exit 1
fi

PROVIDER_FILE="$OUTPUT_DIR/$SERVICE_NAME/sofarpc-provider.json"
CONSUMER_FILE="$OUTPUT_DIR/$SERVICE_NAME/sofarpc-consumer.json"
mkdir -p "$(dirname "$PROVIDER_FILE")"

PROVIDER_COUNT=0
CONSUMER_COUNT=0

json_array_init "$PROVIDER_FILE"
json_array_init "$CONSUMER_FILE"

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    # Provider: @SofaService
    IS_PROVIDER=$(found_in_file "$java_file" "SofaService")
    if [ "$IS_PROVIDER" = "true" ]; then
        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            [ -z "$METHOD_NAME" ] && continue
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${METHOD_NAME}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$SERVICE_NAME" "sofarpc" "provider" "$CLASS_NAME" "$SIG" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
        done < <(extract_methods "$java_file")
    fi

    # Consumer: @SofaReference
    IS_CONSUMER=$(found_in_file "$java_file" "SofaReference")
    if [ "$IS_CONSUMER" = "true" ]; then
        for anno in "SofaReference" "SofaReferenceBinding"; do
            while IFS= read -r field_info; do
                [ -z "$field_info" ] && continue
                LN=$(echo "$field_info" | cut -d: -f1)
                FIELD=$(echo "$field_info" | cut -d: -f2-)
                INTERFACE_CLASS=$(echo "$FIELD" | awk '{print $1}')
                if echo "$INTERFACE_CLASS" | grep -q "SofaReference"; then
                    INTERFACE_CLASS=$(echo "$FIELD" | grep -oE 'Class\s+\S+' | awk '{print $2}' | tr -d ';' || echo "unknown")
                fi
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${INTERFACE_CLASS}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "$INTERFACE_CLASS" "$SERVICE_NAME" "sofarpc" "consumer" "$INTERFACE_CLASS" "$FIELD" "$REL_PATH:$LN" "" "" "[]")
                json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
                CONSUMER_COUNT=$((CONSUMER_COUNT + 1))
            done < <(extract_field_annotations "$java_file" "$anno")
        done
    fi

    # Also detect GenericService implementation (skip if already caught as @SofaService)
    HAS_GENERIC=$(found_in_file "$java_file" "com.alipay.sofa.rpc.api.GenericService")
    if [ "$HAS_GENERIC" = "true" ] && [ "$IS_PROVIDER" != "true" ]; then
        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            [ -z "$METHOD_NAME" ] && continue
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${METHOD_NAME}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$SERVICE_NAME" "sofarpc" "provider" "$CLASS_NAME" "$SIG" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
        done < <(extract_methods "$java_file")
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$PROVIDER_FILE"
json_array_close "$CONSUMER_FILE"

echo "[SOFARPC] $SERVICE_NAME: $PROVIDER_COUNT providers, $CONSUMER_COUNT consumers"
