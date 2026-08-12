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

OUTPUT_FILE="$OUTPUT_DIR/$SERVICE_NAME/nonstandard-custom.json"
mkdir -p "$(dirname "$OUTPUT_FILE")"

COUNT=0
json_array_init "$OUTPUT_FILE"

while IFS= read -r java_file; do
    REL_PATH="${java_file#$REPO_PATH/}"
    CLASS_NAME=$(extract_class_name "$java_file")

    # Netty patterns
    if grep -qE "io\.netty" "$java_file" 2>/dev/null; then
        # Server-side (ServerBootstrap)
        if grep -qE "ServerBootstrap|ChannelInitializer" "$java_file" 2>/dev/null; then
            while IFS= read -r line_info; do
                [ -z "$line_info" ] && continue
                LN=$(echo "$line_info" | cut -d: -f1)
                CONTENT=$(echo "$line_info" | cut -d: -f2-)
                PORT=$(echo "$CONTENT" | grep -oE '\b[0-9]{4,5}\b' | head -1 || echo "0")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.netty-server-${LN}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "netty-server" "$SERVICE_NAME" "socket" "provider" "$CLASS_NAME" "port=$PORT" "$REL_PATH:$LN" "" "" "[]")
                json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
                COUNT=$((COUNT + 1))
            done < <(grep -nE "(ServerBootstrap|\.bind\(|\.channel\()" "$java_file" 2>/dev/null | head -5 || true)
        fi

        # Client-side (Bootstrap)
        if grep -qE "Bootstrap[^S]|connect\s*\(" "$java_file" 2>/dev/null; then
            while IFS= read -r line_info; do
                [ -z "$line_info" ] && continue
                LN=$(echo "$line_info" | cut -d: -f1)
                CONTENT=$(echo "$line_info" | cut -d: -f2-)
                HOST=$(echo "$CONTENT" | grep -oE '"[^"]*"' | head -1 | tr -d '"' || echo "unknown")
                NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.netty-client-${LN}"
                NODE_JSON=$(node_interface_json "$NODE_ID" "netty-client" "$SERVICE_NAME" "socket" "consumer" "$CLASS_NAME" "$CONTENT" "$REL_PATH:$LN" "" "" "[]")
                json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
                COUNT=$((COUNT + 1))
            done < <(grep -nE "(Bootstrap|\.connect\()" "$java_file" 2>/dev/null | grep -v "ServerBootstrap" | head -5 || true)
        fi
    fi

    # Java Socket patterns
    if grep -qE "java\.(net|nio)\.(Socket|ServerSocket|SocketChannel|ServerSocketChannel)" "$java_file" 2>/dev/null; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            LN=$(echo "$line_info" | cut -d: -f1)
            CONTENT=$(echo "$line_info" | cut -d: -f2-)
            IS_SERVER=$(echo "$CONTENT" | grep -q "ServerSocket\|accept" && echo "provider" || echo "consumer")
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.socket-${LN}"
            NODE_JSON=$(node_interface_json "$NODE_ID" "socket" "$SERVICE_NAME" "socket" "$IS_SERVER" "$CLASS_NAME" "$CONTENT" "$REL_PATH:$LN" "" "" "[]")
            json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
            COUNT=$((COUNT + 1))
        done < <(grep -nE "(new Socket|new ServerSocket|SocketChannel\.open|\.connect\(|\.accept\()" "$java_file" 2>/dev/null | head -5 || true)
    fi

    # Mark files with unknown communication patterns for AI analysis
    if [ "$COUNT" -eq 0 ]; then
        UNKNOWN_IMPORTS=$(extract_imports "$java_file" | grep -iE "rpc|remote|connect|transport|channel|message" | grep -v "java\.\|javax\.\|jakarta\." | head -3 || true)
        if [ -n "$UNKNOWN_IMPORTS" ]; then
            NODE_ID="${SERVICE_NAME}::${CLASS_NAME}.unknown-pattern"
            NODE_JSON=$(node_interface_json "$NODE_ID" "unknown-pattern" "$SERVICE_NAME" "custom" "unknown" "$CLASS_NAME" "$(echo "$UNKNOWN_IMPORTS" | tr '\n' ' ')" "$REL_PATH" "" "" "[]")
            json_array_add "$OUTPUT_FILE" "$NODE_JSON" false
            COUNT=$((COUNT + 1))
        fi
    fi
done < <(scan_java_files "$REPO_PATH")

json_array_close "$OUTPUT_FILE"
echo "[NONSTD-CUSTOM] $SERVICE_NAME: $COUNT custom/unknown patterns detected"
