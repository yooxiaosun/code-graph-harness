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

TAGS_FILE="$OUTPUT_DIR/$SERVICE_NAME/tags.json"
mkdir -p "$(dirname "$TAGS_FILE")"

TAGS_ARRAY=()

extract_custom_annotation_tags() {
    while IFS= read -r java_file; do
        local class_annotations
        class_annotations=$(extract_class_annotations "$java_file")
        for anno in $class_annotations; do
            # Match annotation prefix patterns
            if echo "$anno" | grep -qE '^(com\..*\.(annotation|annotations|tag)\.|Biz$|Tag$|Domain$)'; then
                local tag
                tag=$(echo "$anno" | sed 's/.*\.//' | sed 's/Biz$//' | sed 's/Tag$//' | sed 's/Domain$//' | tr '[:upper:]' '[:lower:]')
                echo "$tag-domain"
            fi
        done
    done < <(scan_java_files "$REPO_PATH")
}

extract_package_domain_tags() {
    while IFS= read -r java_file; do
        local pkg
        pkg=$(extract_package "$java_file")
        for keyword in order trade user account inventory stock payment pay logistics delivery; do
            if echo "$pkg" | grep -qi "\.${keyword}\b"; then
                case "$keyword" in
                    order|trade) echo "order-domain" ;;
                    user|account) echo "user-domain" ;;
                    inventory|stock) echo "inventory-domain" ;;
                    payment|pay) echo "payment-domain" ;;
                    logistics|delivery) echo "logistics-domain" ;;
                esac
            fi
        done
    done < <(scan_java_files "$REPO_PATH" | head -5)
}

extract_javadoc_tags() {
    while IFS= read -r java_file; do
        [ ! -f "$java_file" ] && continue
        grep -oE '@since\s+\S+' "$java_file" 2>/dev/null | sed 's/@since //' | head -3 || true
        grep -oE '@author\s+\S+' "$java_file" 2>/dev/null | sed 's/@author //' | head -3 || true
    done < <(scan_java_files "$REPO_PATH" | head -10)
}

extract_method_name_tags() {
    while IFS= read -r java_file; do
        [ ! -f "$java_file" ] && continue
        grep -E "public\s+\w+\s+(\w+)\s*\(" "$java_file" 2>/dev/null | grep -oE "\s(\w+)\s*\(" | sed 's/[ (]//g' | sed 's/^get\|^set\|^is//' | tr '[:upper:]' '[:lower:]' | while IFS= read -r word; do
            [ ${#word} -gt 2 ] && echo "$word"
        done
    done < <(scan_java_files "$REPO_PATH" | head -10) | sort -u | head -10
}

extract_config_tags() {
    if [ -f "$REPO_PATH/application.yml" ]; then
        grep "application.name" "$REPO_PATH/application.yml" 2>/dev/null | sed 's/.*:\s*//' | tr '[:upper:]' '[:lower:]' || true
    fi
    if [ -f "$REPO_PATH/application.yaml" ]; then
        grep "application.name" "$REPO_PATH/application.yaml" 2>/dev/null | sed 's/.*:\s*//' | tr '[:upper:]' '[:lower:]' || true
    fi
    while IFS= read -r prop_file; do
        [ ! -f "$prop_file" ] && continue
        grep "spring.application.name" "$prop_file" 2>/dev/null | sed 's/.*=\s*//' | tr '[:upper:]' '[:lower:]' | head -1 || true
    done < <(find "$REPO_PATH" -name "*.properties" -not -path "*/.git/*" -not -path "*/target/*" -not -path "*/build/*" 2>/dev/null | head -3)
    if [ -f "$REPO_PATH/pom.xml" ]; then
        grep "<artifactId>" "$REPO_PATH/pom.xml" 2>/dev/null | head -1 | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr '[:upper:]' '[:lower:]' || true
    fi
}

echo "[TAGS] Extracting tags for $SERVICE_NAME..."

CUSTOM_TAGS=$(extract_custom_annotation_tags 2>/dev/null || true)
PKG_TAGS=$(extract_package_domain_tags 2>/dev/null || true)
JAVADOC_TAGS=$(extract_javadoc_tags 2>/dev/null || true)
METHOD_TAGS=$(extract_method_name_tags 2>/dev/null || true)
CONFIG_TAGS=$(extract_config_tags 2>/dev/null || true)

ALL_TAGS=$(echo -e "$CUSTOM_TAGS\n$PKG_TAGS\n$JAVADOC_TAGS\n$METHOD_TAGS\n$CONFIG_TAGS" | sed '/^$/d' | sort -u | head -20)

json_array_init "$TAGS_FILE"
FIRST=true
while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    [ "$FIRST" = true ] && FIRST=false && json_array_add "$TAGS_FILE" "$(json_escape "$tag")" true && continue
    json_array_add "$TAGS_FILE" "$(json_escape "$tag")" false
done <<< "$ALL_TAGS"

if [ "$FIRST" = true ]; then
    json_array_add "$TAGS_FILE" "$(json_escape "$SERVICE_NAME")" true
fi
json_array_close "$TAGS_FILE"

TAG_COUNT=$(echo "$ALL_TAGS" | grep -c . 2>/dev/null || echo "1")
echo "[TAGS] $SERVICE_NAME: $TAG_COUNT tags extracted"
