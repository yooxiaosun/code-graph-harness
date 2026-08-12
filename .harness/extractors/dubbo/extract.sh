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

PROVIDER_FILE="$OUTPUT_DIR/$SERVICE_NAME/dubbo-provider.json"
CONSUMER_FILE="$OUTPUT_DIR/$SERVICE_NAME/dubbo-consumer.json"
mkdir -p "$(dirname "$PROVIDER_FILE")"

PROVIDER_COUNT=0
CONSUMER_COUNT=0

json_array_init "$PROVIDER_FILE"
json_array_init "$CONSUMER_FILE"

PROVIDER_FIRST=true
CONSUMER_FIRST=true

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")
    PACKAGE=$(extract_package "$java_file")
    ANNOTATIONS=$(extract_annotations "$java_file")

    # Provider detection: @DubboService or @Service (dubbo package)
    IS_PROVIDER=$(found_in_file "$java_file" "DubboService\|com.alibaba.dubbo.config.annotation.Service\|org.apache.dubbo.config.annotation.Service")
    if [ "$IS_PROVIDER" = "true" ]; then
        PARENT_ID="$SERVICE_NAME"
        INTERFACE_NAME="$CLASS_NAME"

        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            if [ -z "$METHOD_NAME" ]; then
                METHOD_NAME=$(echo "$SIG" | awk '{print $NF}' | sed 's/(.*//')
            fi
            NODE_ID="${PARENT_ID}::${CLASS_NAME}.${METHOD_NAME}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$PARENT_ID" "dubbo" "provider" "$CLASS_NAME" "$SIG" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
        done < <(extract_methods "$java_file")

        # Interface implementations
        IMPL_IFACE=""
        while IFS= read -r impl_iface; do
            [ -z "$impl_iface" ] && continue
            if echo "$impl_iface" | grep -qi "Serializable\|Cloneable"; then
                continue
            fi
            IMPL_IFACE="$impl_iface"
        done < <(extract_interface_impl "$java_file")

        if [ "$PROVIDER_COUNT" -eq 0 ]; then
            FALLBACK_CLASS="${IMPL_IFACE:-$CLASS_NAME}"
            CLASS_ANNOTATIONS=$(extract_class_annotations "$java_file")
            NODE_ID="${PARENT_ID}::${FALLBACK_CLASS}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "$(basename "$FALLBACK_CLASS")" "$PARENT_ID" "dubbo" "provider" "$FALLBACK_CLASS" "" "$REL_PATH" "" "" "[]")
            json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
            PROVIDER_COUNT=1
        fi
    fi

    # Consumer detection: @DubboReference or @Reference
    IS_CONSUMER=$(found_in_file "$java_file" "DubboReference\|com.alibaba.dubbo.config.annotation.Reference\|org.apache.dubbo.config.annotation.Reference")
    if [ "$IS_CONSUMER" = "true" ]; then
        for anno in "DubboReference" "Reference"; do
            while IFS= read -r field_info; do
                [ -z "$field_info" ] && continue
                LN=$(echo "$field_info" | cut -d: -f1)
                FIELD=$(echo "$field_info" | cut -d: -f2-)

                INTERFACE_CLASS=$(echo "$FIELD" | grep -oE 'private\s+\S+' | awk '{print $2}' || echo "$FIELD" | awk '{print $1}')
                if echo "$INTERFACE_CLASS" | grep -q "DubboReference\|Reference"; then
                    INTERFACE_CLASS=$(echo "$FIELD" | grep -oE 'Class\s+\S+' | awk '{print $2}' | tr -d ';' || echo "unknown")
                fi

                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${INTERFACE_CLASS}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "$INTERFACE_CLASS" "$SERVICE_NAME" "dubbo" "consumer" "$INTERFACE_CLASS" "$FIELD" "$REL_PATH:$LN" "" "" "[]")
                json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
                CONSUMER_COUNT=$((CONSUMER_COUNT + 1))
            done < <(extract_field_annotations "$java_file" "$anno")
        done
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$PROVIDER_FILE"
json_array_close "$CONSUMER_FILE"

echo "[DUBBO] $SERVICE_NAME: $PROVIDER_COUNT providers, $CONSUMER_COUNT consumers"
