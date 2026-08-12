#!/usr/bin/env bash
# scan-files — 原子能力 C1：按扩展名扫描仓库文件（AI 直产前的确定性文件清单）
# 用法: bash scripts/base/scan-files.sh <repo-path> [--ext java] [--ext proto] [--max N]
# 输出: 每行一个相对路径，排除 .git / target / build / node_modules
set -euo pipefail

REPO_PATH="${1:-.}"
MAX_FILES="${MAX_FILES:-500}"

exts=()
args=("$@")
i=1
while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
        --ext)
            exts+=("${args[$((i+1))]}")
            i=$((i + 2))
            ;;
        --max)
            MAX_FILES="${args[$((i+1))]}"
            i=$((i + 2))
            ;;
        *)
            i=$((i + 1))
            ;;
    esac
done

if [ ! -d "$REPO_PATH" ]; then
    echo "[ERROR] repo path not found: $REPO_PATH" >&2
    exit 1
fi

if [ ${#exts[@]} -eq 0 ]; then
    echo "[ERROR] at least one --ext required" >&2
    exit 1
fi

# 构建 find 的 name 参数
find_args=()
for ext in "${exts[@]}"; do
    find_args+=(-name "*.$ext" -o)
done
unset 'find_args[${#find_args[@]}-1]'

count=0
while IFS= read -r file; do
    rel="${file#$REPO_PATH/}"
    echo "$rel"
    count=$((count + 1))
    if [ "$count" -ge "$MAX_FILES" ]; then
        echo "[WARN] hit MAX_FILES=$MAX_FILES, stopping scan" >&2
        break
    fi
done < <(find "$REPO_PATH" -type f \( "${find_args[@]}" \) \
    -not -path "*/.git/*" -not -path "*/target/*" -not -path "*/build/*" -not -path "*/node_modules/*" 2>/dev/null | sort)
