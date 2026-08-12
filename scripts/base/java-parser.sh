#!/usr/bin/env bash
set -euo pipefail

JAVA_PARSER_VERSION="1.0"

scan_java_files() {
    local root_dir="${1:-.}"
    find "$root_dir" -name "*.java" -not -path "*/.git/*" -not -path "*/target/*" -not -path "*/build/*" 2>/dev/null || true
}

extract_imports() {
    local java_file="$1"
    grep -E "^import " "$java_file" | sed 's/^import //' | sed 's/;$//' | sed 's/^static //' | sort -u
}

extract_package() {
    local java_file="$1"
    grep -m1 "^package " "$java_file" | sed 's/^package //' | sed 's/;$//' || echo ""
}

extract_class_name() {
    local java_file="$1"
    local package
    package=$(extract_package "$java_file")
    local filename
    filename=$(basename "$java_file" .java)
    if [ -n "$package" ]; then
        echo "${package}.${filename}"
    else
        echo "$filename"
    fi
}

extract_annotations() {
    local java_file="$1"
    grep -E "@\w+(\.\w+)*" "$java_file" | sed 's/.*@\([A-Za-z._]*\).*/\1/' | sort -u
}

extract_class_annotations() {
    local java_file="$1"
    local in_class=0 class_annotations=""
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^\s*public\s+(class|interface|enum)\s+"; then
            break
        fi
        local anno
        anno=$(echo "$line" | grep -oE '@[A-Za-z._]+' | head -1 || true)
        if [ -n "$anno" ]; then
            class_annotations="${class_annotations} ${anno#@}"
        fi
    done < "$java_file"
    echo "$class_annotations" | tr ' ' '\n' | sort -u | grep -v '^$' || true
}

extract_methods() {
    local java_file="$1"
    grep -nE "^\s*(public|protected|private|static|\s)+[\w<>\[\],\s]+\s+\w+\s*\([^)]*\)\s*(\{|throws)" "$java_file" 2>/dev/null | while IFS=: read -r line_num content; do
        local cleaned
        cleaned=$(echo "$content" | sed 's/^\s*//' | sed 's/\s*{$//' | sed 's/\s*throws.*//' | tr -s ' ')
        if [ -n "$cleaned" ]; then
            echo "$line_num:$cleaned"
        fi
    done
}

extract_field_annotations() {
    local java_file="$1" annotation="$2"
    grep -n "@${annotation}" "$java_file" | while IFS=: read -r line_num _; do
        local next_line=$((line_num + 1))
        local field_line
        field_line=$(sed -n "${next_line}p" "$java_file" | sed 's/^\s*//' | tr -d ';')
        if [ -n "$field_line" ]; then
            echo "$line_num:$field_line"
        fi
    done
}

extract_javadoc() {
    local java_file="$1" target_line="$2"
    local start=$((target_line - 1))
    local javadoc_text=""
    local in_javadoc=0

    while [ "$start" -gt 0 ]; do
        local line
        line=$(sed -n "${start}p" "$java_file" 2>/dev/null || true)
        if echo "$line" | grep -qE '\*/\s*$'; then
            in_javadoc=1
            start=$((start - 1))
            continue
        fi
        if echo "$line" | grep -qE '/\*\*'; then
            in_javadoc=0
            break
        fi
        if [ "$in_javadoc" -eq 1 ]; then
            javadoc_text=$(echo "$line" | sed 's/^\s*\*\s*//' | sed 's/\s*$//')$'\n'$javadoc_text
        fi
        start=$((start - 1))
    done
    echo "$javadoc_text" | grep -v '^$' | tr '\n' ' '
}

extract_interface_impl() {
    local java_file="$1"
    grep -E "^\s*public\s+class\s+\w+\s+(extends\s+\w+\s+)?implements\s+" "$java_file" | sed 's/.*implements\s*//' | sed 's/{.*//' | tr -d ' ' | tr ',' '\n' || true
}

found_in_file() {
    local java_file="$1" pattern="$2"
    grep -q "$pattern" "$java_file" 2>/dev/null && echo "true" || echo "false"
}
