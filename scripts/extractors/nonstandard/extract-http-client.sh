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

OUTPUT_FILE="$OUTPUT_DIR/$SERVICE_NAME/nonstandard-http.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

COUNT=0
json_array_init "$OUTPUT_FILE"

detect_url_from_line() {
    local content="$1"
    echo "$content" | grep -oE '"(https?://[^"]*)"' | head -1 | tr -d '"' || echo ""
}

detect_http_method_from_line() {
    local content="$1"
    if echo "$content" | grep -q "getForObject\|getForEntity\|get\(\)"; then echo "GET"
    elif echo "$content" | grep -q "postForObject\|postForEntity\|post\(\)"; then echo "POST"
    elif echo "$content" | grep -q "put\(\)\|putForObject"; then echo "PUT"
    elif echo "$content" | grep -q "delete\(\)\|deleteForObject"; then echo "DELETE"
    elif echo "$content" | grep -q "exchange\|execute"; then echo "REQUEST"
    else echo "UNKNOWN"
    fi
}

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    # RestTemplate calls
    if grep -qE "(restTemplate|RestTemplate)" "$java_file" 2>/dev/null; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            URL=$(detect_url_from_line "$CONTENT")
            # URL 以变量形式传入时: 回溯变量赋值行提取
            if [ -z "$URL" ]; then
                VAR_NAME=$(echo "$CONTENT" | sed -nE 's/.*\(([A-Za-z_][A-Za-z0-9_]*)[ ,)].*/\1/p' | head -1)
                if [ -n "$VAR_NAME" ]; then
                    ASSIGN_LINE=$(grep -E "(^|[^A-Za-z0-9_])${VAR_NAME} *=" "$java_file" 2>/dev/null | head -1 || true)
                    if [ -n "$ASSIGN_LINE" ]; then
                        URL=$(detect_url_from_line "$ASSIGN_LINE")
                    fi
                fi
            fi
            # 多行调用: URL 字面量在后续几行
            if [ -z "$URL" ]; then
                NEXT_LINES=$(sed -n "$((LN + 1)),$((LN + 3))p" "$java_file" 2>/dev/null || true)
                if [ -n "$NEXT_LINES" ]; then
                    URL=$(echo "$NEXT_LINES" | grep -oE '"https?://[^"]*"' | head -1 | tr -d '"' || true)
                fi
            fi
            METHOD=$(detect_http_method_from_line "$CONTENT")

            if [ -n "$URL" ]; then
                TARGET_HOST=$(echo "$URL" | sed 's|https\?://||' | cut -d/ -f1 || echo "unknown")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.http-${LN}"
                CONFIDENCE=0.9
                SOURCE_PATH="$REL_PATH:$LN"

                NODE_JSON=$(node_interface_json "$NODE_ID" "http-call" "$SERVICE_NAME" "http" "consumer" "$CLASS_NAME" "$METHOD $URL" "$SOURCE_PATH" "$METHOD" "$URL" "[]")
                json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
                COUNT=$((COUNT + 1))
            fi
        done < <(grep -nE "\.(getForObject|postForObject|getForEntity|postForEntity|exchange|execute)\(" "$java_file" 2>/dev/null || true)
    fi

    # WebClient calls
    if grep -qE "(webClient|WebClient)" "$java_file" 2>/dev/null; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            URI=$(echo "$CONTENT" | grep -oE '\.uri\("[^"]*"\)' | head -1 | sed 's/\.uri("//' | sed 's/")//' || echo "")
            METHOD=$(detect_http_method_from_line "$CONTENT")

            if [ -n "$URI" ]; then
                TARGET_HOST=$(echo "$URI" | sed 's|https\?://||' | cut -d/ -f1 || echo "unknown")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.webclient-${LN}"
                CONFIDENCE=0.85
                SOURCE_PATH="$REL_PATH:$LN"

                NODE_JSON=$(node_interface_json "$NODE_ID" "webclient-call" "$SERVICE_NAME" "http" "consumer" "$CLASS_NAME" "$METHOD $URI" "$SOURCE_PATH" "$METHOD" "$URI" "[]")
                json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
                COUNT=$((COUNT + 1))
            fi
        done < <(grep -nE "\.uri\(|\.get\(\)|\.post\(\)|\.retrieve\(\)" "$java_file" 2>/dev/null | grep -B1 "WebClient\|webClient" | grep -v "^--$" || true)
    fi

    # OkHttp calls
    if grep -qE "(OkHttpClient|okHttpClient)" "$java_file" 2>/dev/null; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            URL=$(detect_url_from_line "$CONTENT")

            if [ -n "$URL" ]; then
                TARGET_HOST=$(echo "$URL" | sed 's|https\?://||' | cut -d/ -f1 || echo "unknown")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.okhttp-${LN}"
                CONFIDENCE=0.9
                SOURCE_PATH="$REL_PATH:$LN"

                NODE_JSON=$(node_interface_json "$NODE_ID" "okhttp-call" "$SERVICE_NAME" "http" "consumer" "$CLASS_NAME" "HTTP $URL" "$SOURCE_PATH" "" "$URL" "[]")
                json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
                COUNT=$((COUNT + 1))
            fi
        done < <(grep -nE "\.(newCall|execute|enqueue)\(" "$java_file" 2>/dev/null | grep -B1 "OkHttp\|okHttp\|Request.Builder" | grep -v "^--$" || true)
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$OUTPUT_FILE"
echo "[NONSTD-HTTP] $SERVICE_NAME: $COUNT HTTP client calls detected"
