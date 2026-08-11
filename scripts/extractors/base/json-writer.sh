#!/usr/bin/env bash
set -euo pipefail

JSON_WRITER_VERSION="1.0"

json_array_init() {
    local file="$1"
    echo "[" > "$file"
}

json_array_add() {
    local file="$1" object="$2" is_last="${3:-false}"
    if [ "$is_last" = "true" ]; then
        echo "  $object" >> "$file"
    else
        echo "  $object," >> "$file"
    fi
}

json_array_close() {
    local file="$1"
    sed -i '' -e '$ s/,$//' "$file" 2>/dev/null || sed -i '$ s/,$//' "$file" 2>/dev/null || true
    echo "]" >> "$file"
}

node_service_json() {
    local id="$1" name="$2" repo="${3:-}" branch="${4:-}" build_tool="${5:-maven}"
    local tags_json="${6:-[]}"

    cat <<NODE
{"id": $(json_escape "$id"), "type": "service", "name": $(json_escape "$name"), "repo": $(json_escape "$repo"), "branch": $(json_escape "$branch"), "buildTool": $(json_escape "$build_tool"), "tags": $tags_json}
NODE
}

node_interface_json() {
    local id="$1" name="$2" parent="$3" protocol="$4" role="$5"
    local class_name="${6:-}" signature="${7:-}" path="${8:-}"
    local http_method="${9:-}" http_path="${10:-}" tags_json="${11:-[]}"

    cat <<NODE
{"id": $(json_escape "$id"), "type": "interface", "name": $(json_escape "$name"), "parent": $(json_escape "$parent"), "protocol": $(json_escape "$protocol"), "role": $(json_escape "$role"), "className": $(json_escape "$class_name"), "signature": $(json_escape "$signature"), "path": $(json_escape "$path"), "httpMethod": $(json_escape "$http_method"), "httpPath": $(json_escape "$http_path"), "tags": $tags_json}
NODE
}

edge_rpc_json() {
    local from="$1" to="$2" protocol="$3" from_service="$4" to_service="$5"
    local source_path="${6:-}"

    cat <<EDGE
{"from": $(json_escape "$from"), "to": $(json_escape "$to"), "type": "rpc_call", "protocol": $(json_escape "$protocol"), "fromService": $(json_escape "$from_service"), "toService": $(json_escape "$to_service"), "metadata": {"synchronous": true, "sourcePath": $(json_escape "$source_path")}}
EDGE
}

edge_nonstandard_json() {
    local from="$1" to="$2" protocol="$3" confidence="$4"
    local from_service="$5" to_service="$6" pattern="${7:-}" source_path="${8:-}"
    local topic="${9:-}" host_pattern="${10:-}"

    cat <<EDGE
{"from": $(json_escape "$from"), "to": $(json_escape "$to"), "type": "nonstandard_call", "protocol": $(json_escape "$protocol"), "confidence": $confidence, "fromService": $(json_escape "$from_service"), "toService": $(json_escape "$to_service"), "pattern": $(json_escape "$pattern"), "sourcePath": $(json_escape "$source_path"), "metadata": {"topic": $(json_escape "$topic"), "hostPattern": $(json_escape "$host_pattern")}}
EDGE
}

json_escape() {
    local s="$1"
    if [ -z "$s" ]; then
        echo '""'
        return
    fi
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    echo "\"$s\""
}

json_tags_from_list() {
    local items=("$@")
    if [ ${#items[@]} -eq 0 ]; then
        echo "[]"
        return
    fi
    local result="["
    local first=true
    for item in "${items[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            result+=", "
        fi
        result+=$(json_escape "$item")
    done
    result+="]"
    echo "$result"
}

validate_json() {
    local file="$1"
    if command -v jq &>/dev/null; then
        jq empty "$file" 2>/dev/null && return 0 || return 1
    fi
    return 0
}

read_json_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file"
    else
        echo "[]"
    fi
}

merge_json_arrays() {
    local file1="$1" file2="$2" output="$3"
    if command -v jq &>/dev/null; then
        jq -s '.[0] + .[1]' <(cat "$file1" 2>/dev/null || echo "[]") <(cat "$file2" 2>/dev/null || echo "[]") > "$output"
    else
        cat "$file1" "$file2" 2>/dev/null > "$output" || true
    fi
}

write_stats_json() {
    local output="$1" total_services="$2" total_interfaces="$3" total_edges="$4"
    local dubbo="$5" sofarpc="$6" grpc="$7" rest="$8" nonstandard="$9"

    cat <<STATS
{"totalServices": $total_services, "totalInterfaces": $total_interfaces, "totalEdges": $total_edges, "byProtocol": {"dubbo": $dubbo, "sofarpc": $sofarpc, "grpc": $grpc, "rest": $rest, "nonstandard": $nonstandard}}
STATS
}
