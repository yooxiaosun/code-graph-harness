#!/usr/bin/env bash
# merge-json — 原子能力 C15/C18：合并多个 JSON 数组文件 → 单一 JSON 数组
# 用法: bash scripts/base/merge-json.sh <output> <input1.json> [input2.json ...]
# 说明: 通过 node.id / from+to 去重（保留先出现的），输出合法 JSON 数组
# 实现: python3（内网可用）；不依赖 jq（node 兜底见 json.sh）
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

python3 - "$OUTPUT" "${inputs[@]}" <<'PY'
import json, sys

output = sys.argv[1]
files = sys.argv[2:]

seen = set()
merged = []
for f in files:
    try:
        data = json.load(open(f))
    except Exception:
        continue
    for item in data:
        if not isinstance(item, dict):
            merged.append(item)
            continue
        key = item.get('id') or (item.get('from', '') + '|' + item.get('to', ''))
        if key and key in seen:
            continue
        if key:
            seen.add(key)
        merged.append(item)

with open(output, 'w') as fh:
    json.dump(merged, fh, ensure_ascii=False)
PY

if [ ! -s "$OUTPUT" ]; then
    echo "[]" > "$OUTPUT"
fi
echo "[MERGE-JSON] $OUTPUT (inputs: ${#inputs[@]})"
