#!/usr/bin/env bash
# validate-schema — 原子能力：校验 JSON 数组产物符合 v2.1 契约 + 证据链完整性（C-E1）
# 用法: bash scripts/base/validate-schema.sh <json-file> <node|edge> [repo-path]
#   校验:
#     1. 合法 JSON 数组
#     2. 必填字段齐全
#     3. confidence ∈ [high, medium, low]
#     4. evidence_type ∈ 合法枚举
#     5. evidence_refs 非空 且 无 tier=4 (C-E1 硬约束)
#     6. evidence_type=*_only 时 metadata.boundary_external 必须为 true
#     7. source ∈ [bash, ai, dual]
#   可加校验 (传 repo-path):
#     8. 每个 evidence_refs[].source_path 对应文件存在 (Q-Evidence-1=C 校对用)
# 退出码: 0=通过, 1=校验失败, 2=用法错误
set -uo pipefail

JSON_FILE="${1:-}"
KIND="${2:-}"
REPO_PATH="${3:-}"

if [ -z "$JSON_FILE" ] || { [ "$KIND" != "node" ] && [ "$KIND" != "edge" ]; }; then
    echo "Usage: $0 <json-file> <node|edge> [repo-path]" >&2
    exit 2
fi

if [ ! -f "$JSON_FILE" ]; then
    echo "[FAIL] file not found: $JSON_FILE"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "[ABORT] jq not available"
    exit 1
fi

FAILURES=0
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# 1. 合法 JSON 数组
if ! jq -e 'type == "array"' "$JSON_FILE" >/dev/null 2>&1; then
    echo "[FAIL] not a JSON array: $JSON_FILE"
    exit 1
fi

COUNT=$(jq 'length' "$JSON_FILE")
echo "[VALIDATE-SCHEMA] $KIND: $COUNT item(s) in $JSON_FILE"
[ "$COUNT" -eq 0 ] && { echo "[PASS] empty array"; exit 0; }

# 2-7. 逐项校验
TOTAL=$(jq 'length' "$JSON_FILE")
i=0
while [ "$i" -lt "$TOTAL" ]; do
    IDX="$i"
    # 必填字段
    if [ "$KIND" = "node" ]; then
        REQUIRED="id,type,name,parent,protocol,role,path,confidence,evidence_refs,evidence_type,source"
    else
        REQUIRED="from,to,type,protocol,fromService,toService,confidence,evidence_refs,evidence_type,source"
    fi
    MISSING=$(jq -r --argjson i "$IDX" --arg r "$REQUIRED" '
        $r | split(",") | map(select((.[0:1] != ".") and (.[$i]) == null)) | join(",")
    ' "$JSON_FILE" 2>/dev/null || echo "PARSE")
    # 简化：直接检查每个必填字段
    MISSING=""
    for fld in ${REQUIRED//,/ }; do
        if ! jq -e --argjson i "$IDX" ".[\$i] | has(\"$fld\")" "$JSON_FILE" >/dev/null 2>&1; then
            MISSING="$MISSING $fld"
        fi
    done
    [ -n "$MISSING" ] && fail "item[$IDX] missing fields:$MISSING"

    # confidence 枚举
    CONF=$(jq -r --argjson i "$IDX" '.[$i].confidence // ""' "$JSON_FILE")
    case "$CONF" in
        high|medium|low) ;;
        *) fail "item[$IDX] invalid confidence: '$CONF' (must be high/medium/low)" ;;
    esac

    # evidence_type 枚举
    ET=$(jq -r --argjson i "$IDX" '.[$i].evidence_type // ""' "$JSON_FILE")
    case "$ET" in
        source_reference|declaration_reference|call_site|provider_declaration_only|consumer_reference_only|endpoint_declaration_only|esb_integration_unknown|custom_protocol_unknown|dynamic_dispatch) ;;
        *) fail "item[$IDX] invalid evidence_type: '$ET'" ;;
    esac

    # evidence_refs 非空 + 无 tier=4
    REFS=$(jq -r --argjson i "$IDX" '.[$i].evidence_refs | length' "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$REFS" -lt 1 ]; then
        fail "item[$IDX] evidence_refs empty (C-E1)"
    else
        TIER4=$(jq -r --argjson i "$IDX" '[.[$i].evidence_refs[].tier] | map(select(. == 4)) | length' "$JSON_FILE" 2>/dev/null || echo "0")
        [ "$TIER4" -gt 0 ] && fail "item[$IDX] has $TIER4 tier=4 evidence (C-E1 hard constraint)"
    fi

    # *_only → boundary_external = true
    case "$ET" in
        provider_declaration_only|consumer_reference_only|endpoint_declaration_only)
            BE=$(jq -r --argjson i "$IDX" '.[$i].metadata.boundary_external // false' "$JSON_FILE" 2>/dev/null || echo "false")
            [ "$BE" != "true" ] && fail "item[$IDX] evidence_type=$ET but metadata.boundary_external != true"
            ;;
    esac

    # source 枚举
    SRC=$(jq -r --argjson i "$IDX" '.[$i].source // ""' "$JSON_FILE")
    case "$SRC" in
        bash|ai|dual) ;;
        *) fail "item[$IDX] invalid source: '$SRC'" ;;
    esac

    # 8. 路径存在性 (传 repo-path 时)
    if [ -n "$REPO_PATH" ]; then
        if [ "$KIND" = "node" ]; then
            P=$(jq -r --argjson i "$IDX" '.[$i].path' "$JSON_FILE" 2>/dev/null || true)
            if [ -n "$P" ] && [ "$P" != "null" ]; then
                PFILE="${P%%:*}"
                [ ! -f "$REPO_PATH/$PFILE" ] && fail "item[$IDX] path file not found: $REPO_PATH/$PFILE"
            fi
        fi
        # evidence source_path 存在性
        jq -r --argjson i "$IDX" '.[$i].evidence_refs[].source_path' "$JSON_FILE" 2>/dev/null | while IFS= read -r ep; do
            [ -z "$ep" ] && continue
            EPFILE="${ep%%:*}"
            [ ! -f "$REPO_PATH/$EPFILE" ] && echo "  [FAIL] item[$IDX] evidence file not found: $REPO_PATH/$EPFILE"
        done
    fi

    i=$((i + 1))
done

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "[VALIDATE-SCHEMA] RESULT: FAIL ($FAILURES issue(s))"
    exit 1
fi
echo "[VALIDATE-SCHEMA] RESULT: PASS"
exit 0
