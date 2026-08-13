#!/usr/bin/env bash
# sed-compat — 跨平台 sed 原地编辑封装（GNU/Linux + BSD/macOS）
# md-first: 纯机械工具, 无策略判断。
#
# 背景: `sed -i` 在 GNU (Linux/WSL) 与 BSD (macOS) 语法不同:
#   GNU: sed -i 'expr' file        (无备份后缀)
#   BSD: sed -i '' 'expr' file     (空备份后缀)
# 用法:
#   source "$SCRIPT_DIR/../base/sed-compat.sh"
#   sed_i 's/old/new/' file
#   sed_i '/pattern/d' file
#
# 返回: 0 = 成功; 1 = 失败(文件不存在或 sed 出错)

# 惰性探测: 首次调用时缓存 sed 类型, 避免每行都探测
_SED_COMPAT_TYPE=""
sed_i() {
    local expr="$1" file="${2:-}"
    [ -z "$file" ] && { echo "[sed-compat] 缺少文件参数" >&2; return 1; }
    [ -f "$file" ] || { echo "[sed-compat] 文件不存在: $file" >&2; return 1; }

    if [ -z "$_SED_COMPAT_TYPE" ]; then
        if sed --version >/dev/null 2>&1; then
            _SED_COMPAT_TYPE="gnu"
        else
            _SED_COMPAT_TYPE="bsd"
        fi
    fi

    if [ "$_SED_COMPAT_TYPE" = "gnu" ]; then
        sed -i "$expr" "$file" 2>/dev/null
    else
        sed -i '' "$expr" "$file" 2>/dev/null
    fi
}
