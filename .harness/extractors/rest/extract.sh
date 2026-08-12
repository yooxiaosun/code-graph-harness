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

PROVIDER_FILE="$OUTPUT_DIR/$SERVICE_NAME/rest-provider.json"
CONSUMER_FILE="$OUTPUT_DIR/$SERVICE_NAME/rest-consumer.json"
mkdir -p "$(dirname "$PROVIDER_FILE")"

PROVIDER_COUNT=0
CONSUMER_COUNT=0

json_array_init "$PROVIDER_FILE"
json_array_init "$CONSUMER_FILE"

extract_http_method() {
    local annotations="$1"
    if echo "$annotations" | grep -q "@PostMapping"; then echo "POST"
    elif echo "$annotations" | grep -q "@GetMapping"; then echo "GET"
    elif echo "$annotations" | grep -q "@PutMapping"; then echo "PUT"
    elif echo "$annotations" | grep -q "@DeleteMapping"; then echo "DELETE"
    elif echo "$annotations" | grep -q "@PatchMapping"; then echo "PATCH"
    else echo "REQUEST"
    fi
}

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    # Provider: @RestController or @Path (JAX-RS)
    IS_CONTROLLER=$(found_in_file "$java_file" "RestController\|@Path")
    if [ "$IS_CONTROLLER" = "true" ]; then
        # Get class-level mapping
        CLASS_HTTP_PATH=$(head -30 "$java_file" | grep -oE '@RequestMapping\("[^"]*"\)' | head -1 | grep -oE '"[^"]*"' | tr -d '"' || echo "")

        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            [ -z "$METHOD_NAME" ] && continue

            # Get method annotations (lines before the method)
            method_start=$LN
            anno_start=$((method_start - 8))
            [ "$anno_start" -lt 1 ] && anno_start=1
            method_annotations=$(sed -n "${anno_start},${method_start}p" "$java_file" | grep -oE '@(Get|Post|Put|Delete|Patch|Request)Mapping\([^)]*\)' | tail -1 || echo "")

            if [ -n "$method_annotations" ]; then
                HTTP_METHOD=$(extract_http_method "$method_annotations")
                METHOD_PATH=$(echo "$method_annotations" | grep -oE '"[^"]*"' | head -1 | tr -d '"' || echo "")
                FULL_PATH="${CLASS_HTTP_PATH}${METHOD_PATH}"
                [ -z "$FULL_PATH" ] && FULL_PATH="/"

                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${METHOD_NAME}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$SERVICE_NAME" "rest" "provider" "$CLASS_NAME" "$SIG" "$REL_PATH:$LN" "$HTTP_METHOD" "$FULL_PATH" "[]")
                json_array_add "$PROVIDER_FILE" "$NODE_JSON" false
                PROVIDER_COUNT=$((PROVIDER_COUNT + 1))
            fi
        done < <(extract_methods "$java_file")
    fi

    # Consumer: @FeignClient
    IS_FEIGN=$(found_in_file "$java_file" "FeignClient")
    if [ "$IS_FEIGN" = "true" ]; then
        FEIGN_NAME=$(head -20 "$java_file" | grep -oE 'name\s*=\s*"[^"]*"' | head -1 | grep -oE '"[^"]*"' | tr -d '"' || echo "")
        FEIGN_URL=$(head -20 "$java_file" | grep -oE 'url\s*=\s*"[^"]*"' | head -1 | grep -oE '"[^"]*"' | tr -d '"' || echo "")
        TARGET_SERVICE="${FEIGN_NAME:-${FEIGN_URL}}"

        while IFS= read -r method_line; do
            LN=$(echo "$method_line" | cut -d: -f1)
            SIG=$(echo "$method_line" | cut -d: -f2-)
            METHOD_NAME=$(echo "$SIG" | grep -oE '\w+\s*\(' | sed 's/\s*(//' | head -1)
            [ -z "$METHOD_NAME" ] && continue

            anno_start=$((LN - 5))
            [ "$anno_start" -lt 1 ] && anno_start=1
            method_annotations=$(sed -n "${anno_start},${LN}p" "$java_file" | grep -oE '@(Get|Post|Put|Delete|Patch|Request)Mapping\([^)]*\)' | tail -1 || echo "")

            if [ -n "$method_annotations" ]; then
                HTTP_METHOD=$(extract_http_method "$method_annotations")
                METHOD_PATH=$(echo "$method_annotations" | grep -oE '"[^"]*"' | head -1 | tr -d '"' || echo "")

                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.${METHOD_NAME}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "$METHOD_NAME" "$SERVICE_NAME" "rest" "consumer" "$CLASS_NAME" "${HTTP_METHOD} ${METHOD_PATH}" "$REL_PATH:$LN" "$HTTP_METHOD" "$METHOD_PATH" "[]")
                json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
                CONSUMER_COUNT=$((CONSUMER_COUNT + 1))
            fi
        done < <(extract_methods "$java_file")
    fi

    # Consumer: RestTemplate HTTP calls (include internal cross-module)
    HAS_REST_TEMPLATE=$(found_in_file "$java_file" "RestTemplate\|WebClient")
    if [ "$HAS_REST_TEMPLATE" = "true" ]; then
        # Find HTTP calls within controller/service methods
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)

            REST_URL=$(echo "$CONTENT" | grep -oE '"(http|https)://[^"]*"' | head -1 | tr -d '"' || echo "")
            REST_METHOD=$(echo "$CONTENT" | grep -oE '(getForObject|postForObject|put|delete|exchange|get\(\)|post\(\))' | head -1 || echo "")

            if [ -n "$REST_URL" ]; then
                TARGET_SERVICE=$(echo "$REST_URL" | sed 's|https\?://||' | cut -d/ -f1 | cut -d: -f1 || echo "unknown")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.rest-template-${LN}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "rest-call" "$SERVICE_NAME" "rest" "consumer" "$CLASS_NAME" "$REST_METHOD" "$REL_PATH:$LN" "${REST_METHOD^^}" "$REST_URL" "[]")
                json_array_add "$CONSUMER_FILE" "$NODE_JSON" false
                CONSUMER_COUNT=$((CONSUMER_COUNT + 1))
            fi
        done < <(grep -nE "(restTemplate|webClient)\.(getForObject|postForObject|exchange|get\(\)|uri\(|post\(\))" "$java_file" 2>/dev/null || true)
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$PROVIDER_FILE"
json_array_close "$CONSUMER_FILE"

echo "[REST] $SERVICE_NAME: $PROVIDER_COUNT providers, $CONSUMER_COUNT consumers"
