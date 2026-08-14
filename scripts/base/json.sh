#!/usr/bin/env bash
# json.sh — jq 的 node 替代工具（内网无 jq 时用 node 兜底，md-first 机械工具）
# 用法: source 后调用函数，或直接 bash json.sh <cmd> [args]
#
# 命令清单（等价 jq）:
#   get      <file> <path>            → jq -r '<path>'          取值
#   getdef   <file> <path> <default>  → jq -r '<path> // <def>'  取值+默认
#   len      <file>                   → jq 'length'             数组/对象长度
#   is_array <file>                   → jq -e 'type=="array"'   是否数组
#   has      <file> <idx> <field>     → jq -e '.[i]|has(f)'     索引元素是否有字段
#   empty    <file>                   → jq -e 'empty'           是否空数组/空对象
#   merge    <out> <f1> <f2>          → jq -s '.[0]+.[1]'       合并两个 JSON 数组
#   rawlen   <file>                   → 数组长度（失败输出 0）
#   itemfield <file> <idx> <path>     → jq -r '.[idx].<path>'   索引元素字段
#   check    <file> <json-expression> → jq -e '<expr>'          自定义布尔检查
#
# 实现: 优先用 jq（高性能），无 jq 时用 node（跨平台）。md-first：纯机械，无策略。

_JSON_USE_JQ=""
if command -v jq >/dev/null 2>&1; then
    _JSON_USE_JQ=1
elif command -v node >/dev/null 2>&1; then
    _JSON_USE_JQ=0
else
    echo "[json.sh] ERROR: neither jq nor node available" >&2
    return 1 2>/dev/null || exit 1
fi

# 通过 node 单行执行 JSON 操作
_node_eval() {
    # $1 = node 脚本体（fs/json 已预置）
    node -e "const fs=require('fs'); const j=JSON.parse; $1" 2>/dev/null
}

json_get() {
    local file="$1" path="${2:-.}"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -r "$path" "$file" 2>/dev/null
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); const p='${path#.}'; console.log(p===''?d:eval('d.'+p));"
    fi
}

json_getdef() {
    local file="$1" path="${2:-.}" def="${3:-}"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -r "$path // $def" "$file" 2>/dev/null || echo "$def"
    else
        local v
        v=$(_node_eval "const d=j(fs.readFileSync('$file','utf8')); const p='${path#.}'; const v=p===''?d:eval('d.'+p); console.log(v==null?'$def':JSON.stringify(v).replace(/^\"/,'').replace(/\"$/,''));")
        [ -n "$v" ] && echo "$v" || echo "$def"
    fi
}

json_len() {
    local file="$1"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq 'length' "$file" 2>/dev/null
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); console.log(Array.isArray(d)?d.length:Object.keys(d).length);"
    fi
}

json_rawlen() {
    local file="$1"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq 'length' "$file" 2>/dev/null || echo 0
    else
        _node_eval "try{const d=j(fs.readFileSync('$file','utf8')); console.log(Array.isArray(d)?d.length:Object.keys(d).length)}catch(e){console.log(0)}" || echo 0
    fi
}

json_is_array() {
    local file="$1"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -e 'type == "array"' "$file" >/dev/null 2>&1
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); process.exit(Array.isArray(d)?0:1);" >/dev/null 2>&1
    fi
}

json_has() {
    local file="$1" idx="$2" field="$3"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -e --argjson i "$idx" ".[\$i] | has(\"$field\")" "$file" >/dev/null 2>&1
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); const el=d[${idx}]; process.exit(el && Object.prototype.hasOwnProperty.call(el,'$field')?0:1);" >/dev/null 2>&1
    fi
}

json_empty() {
    local file="$1"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -e 'length == 0' "$file" >/dev/null 2>&1
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); process.exit((Array.isArray(d)?d.length:Object.keys(d).length)===0?0:1);" >/dev/null 2>&1
    fi
}

json_merge() {
    local output="$1" f1="$2" f2="$3"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -s '.[0] + .[1]' <(cat "$f1" 2>/dev/null || echo "[]") <(cat "$f2" 2>/dev/null || echo "[]") > "$output"
    else
        _node_eval "const a1=(()=>{try{return j(fs.readFileSync('$f1','utf8'))}catch(e){return[]}})(); const a2=(()=>{try{return j(fs.readFileSync('$f2','utf8'))}catch(e){return[]}})(); fs.writeFileSync('$output', JSON.stringify(a1.concat(a2)));" >/dev/null 2>&1
    fi
}

json_itemfield() {
    local file="$1" idx="$2" path="${3:-}"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -r --argjson i "$idx" ".[\$i].$path" "$file" 2>/dev/null
    else
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); const el=d[${idx}]; const p='${path}'; const v=p===''?el:eval('el.'+p); console.log(v==null?'':(typeof v==='object'?JSON.stringify(v):v));"
    fi
}

json_check() {
    local file="$1" expr="$2"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -e "$expr" "$file" >/dev/null 2>&1
    else
        # node 简化实现：.field 存在性检查
        local f="${expr#.}"
        _node_eval "const d=j(fs.readFileSync('$file','utf8')); process.exit((typeof eval('d.'+f) !== 'undefined')?0:1);" >/dev/null 2>&1
    fi
}

# 从内存 JSON 字符串取值（替代 `echo "$obj" | jq -r '.field'`）
json_fromstr() {
    local obj="$1" path="${2:-}"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        echo "$obj" | jq -r "$path" 2>/dev/null
    else
        echo "$obj" | node -e "const fs=require('fs'); const d=JSON.parse(fs.readFileSync(0,'utf8')); const p='${path#.}'; const v=p===''?d:eval('d.'+p); console.log(v==null?'':(typeof v==='object'?JSON.stringify(v):v));" 2>/dev/null
    fi
}

# 逐行输出数组每个元素（替代 `jq -c '.[]' file`）
json_each() {
    local file="$1"
    if [ "$_JSON_USE_JQ" = "1" ]; then
        jq -c '.[]' "$file" 2>/dev/null || true
    else
        node -e "const fs=require('fs'); const d=JSON.parse(fs.readFileSync('$file','utf8')); d.forEach(x=>console.log(JSON.stringify(x)));" 2>/dev/null
    fi
}

# CLI 入口
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    CMD="${1:-}"
    case "$CMD" in
        get) shift; json_get "$@" ;;
        getdef) shift; json_getdef "$@" ;;
        len) shift; json_len "$@" ;;
        rawlen) shift; json_rawlen "$@" ;;
        is_array) shift; json_is_array "$@" ;;
        has) shift; json_has "$@" ;;
        empty) shift; json_empty "$@" ;;
        merge) shift; json_merge "$@" ;;
        itemfield) shift; json_itemfield "$@" ;;
        check) shift; json_check "$@" ;;
        fromstr) shift; json_fromstr "$@" ;;
        each) shift; json_each "$@" ;;
        *) echo "Usage: json.sh <get|getdef|len|rawlen|is_array|has|empty|merge|itemfield|check|fromstr|each>" >&2; exit 1 ;;
    esac
fi
