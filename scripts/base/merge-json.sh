#!/usr/bin/env bash
# merge-json — 原子能力 C15/C18：合并多个 JSON 数组文件 → 单一 JSON 数组
# 用法: bash scripts/base/merge-json.sh <output> <input1.json> [input2.json ...]
# 说明: 通过 node.id / from+to 去重（保留先出现的），输出合法 JSON 数组
set -euo pipefail

OUTPUT="${1:-}"
shift || true

if [ -z "$OUTPUT" ] || [ $# -eq 0 ]; then
    echo "Usage: $0 <output.json> <input1.json> [input2.json ...]" >&2
    exit 1
fi

inputs=("$@")
for f in "${inputs[@]}"; do
    if [ ! -f "$f" ]; then
        echo "[WARN] input not found, skipping: $f" >&2
    fi
done

# 优先用 jq（可用时）：逐文件 concat，按 id 去重（含 to 的按 from|to）
if command -v jq &>/dev/null; then
    jq_args=(-s)
    for f in "${inputs[@]}"; do
        if [ -f "$f" ]; then
            jq_args+=("$f")
        else
            jq_args+=("/dev/null")
        fi
    done
    # -s 将所有输入读为数组，然后 flatten + 去重
    jq 'add | unique_by(if has("id") then .id else (.from + "|" + .to) end)' "${jq_args[@]}" > "$OUTPUT"
else
    # 兜底：逐文件 cat，仅做格式兜底（不去重）
    : > "$OUTPUT"
    for f in "${inputs[@]}"; do
        if [ -f "$f" ]; then
            cat "$f" >> "$OUTPUT"
        fi
    done
    echo "[WARN] jq not available — merge without dedup" >&2
fi

if [ ! -s "$OUTPUT" ]; then
    echo "[]" > "$OUTPUT"
fi
echo "[MERGE-JSON] $OUTPUT (inputs: ${#inputs[@]})"
