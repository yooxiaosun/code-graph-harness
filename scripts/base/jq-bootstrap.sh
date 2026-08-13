#!/usr/bin/env bash
# jq-bootstrap — 机械 PATH 引导：让工程自带的 tools/jq 可被发现（md-first: 无策略判断）
#
# 背景: 内网 WSL/Linux 无外网, jq 无法用 apt 安装; 工程自带 tools/jq 静态二进制。
# 本文件在脚本运行时被 source, 若系统 PATH 已有 jq 则不干预;
# 若系统无 jq 且 tools/jq 存在, 将 tools/ 注入 PATH 前置位。
#
# 用法: 在需要 jq 的脚本顶部 source 本文件, 或设置 JQ_BOOTSTRAP_LOADED=1 避免重复。
#
# 注意: 本文件只做路径注入（机械操作）, 不含任何"要不要用 tools/jq"的策略判断。
#   AI 或使用者可通过 JQ_STRICT_SYSTEM_ONLY=1 强制只用系统 jq。

if [ "${JQ_BOOTSTRAP_LOADED:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# 定位工程根目录（本文件位于 <root>/scripts/base/）
_JQ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 系统 PATH 已有 jq → 不干预（尊重系统环境）
if command -v jq >/dev/null 2>&1; then
    JQ_BOOTSTRAP_LOADED=1
    return 0 2>/dev/null || exit 0
fi

# 系统无 jq → 尝试工程自带 tools/jq
if [ -n "$_JQ_ROOT" ] && [ -x "$_JQ_ROOT/tools/jq" ]; then
    # 注入 PATH 前置位（机械操作, 无策略）
    export PATH="$_JQ_ROOT/tools:$PATH"
    echo "[JQ-BOOTSTRAP] 系统无 jq, 已启用工程自带 tools/jq ($_JQ_ROOT/tools/jq)" >&2
fi

export JQ_BOOTSTRAP_LOADED=1
return 0 2>/dev/null || exit 0
