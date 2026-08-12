#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# e4-verify-bundle — E4 交付包一键验证（GP1-GP5 + 既有提取器回归）
# 用法: bash scripts/e4-verify-bundle.sh <pattern>
#   交付包位置: .harness/staging/<pattern>/（extract-<pattern>.sh + fixtures）
# 全部通过 exit 0；任一失败 exit 1 并打印失败门禁。
# 规则见 .harness/staging/README.md 与 nightly-mode.md §7。
# ─────────────────────────────────────────────────────────────────────
set -uo pipefail

PATTERN="${1:-}"
if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <pattern>"
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

BUNDLE_DIR=".harness/staging/$PATTERN"
SCRIPT_FILE="$BUNDLE_DIR/extract-$PATTERN.sh"
SAMPLE_DIR="$BUNDLE_DIR/fixtures/sample-$PATTERN"
EXPECTED_FILE="$BUNDLE_DIR/fixtures/expected/$PATTERN.json"
FIXTURES_DIR=".harness/fixtures"

FAILED=0
fail() { echo "[FAIL] $1"; FAILED=1; }

echo "==== e4-verify-bundle: $PATTERN ===="

# ── 0. 交付包完整性（三件套）────────────────────────────────────────
if [ ! -f "$SCRIPT_FILE" ] || [ ! -d "$SAMPLE_DIR" ] || [ ! -f "$EXPECTED_FILE" ]; then
    echo "[FATAL] 交付包不完整：$BUNDLE_DIR"
    echo "  需要: extract-$PATTERN.sh / fixtures/sample-$PATTERN/ / fixtures/expected/$PATTERN.json"
    exit 1
fi
echo "[OK] 交付包完整性"

# ── GP1: 语法检查 ───────────────────────────────────────────────────
echo "── GP1: 语法 ──"
if bash -n "$SCRIPT_FILE" 2>/dev/null && head -1 "$SCRIPT_FILE" | grep -q "bash"; then
    echo "  [PASS] syntax + shebang"
else
    echo "  [FAIL] bash -n 或 shebang"
    fail "GP1 语法"
fi

# ── GP2/GP3/GP4: 执行 + JSON 校验 + 召回 ─────────────────────────────
# 提取器 source "$ROOT_DIR/scripts/base/*.sh" 依赖正式目录结构，
# 因此将交付包放入模拟正式环境（临时目录复现 .harness/extractors + scripts/base）后执行。
TMP_ENV=$(mktemp -d)
TMP_OUTPUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUTPUT" "$TMP_ENV"' EXIT

mkdir -p "$TMP_ENV/.harness/extractors/$PATTERN" "$TMP_ENV/scripts"
cp -R "$ROOT_DIR/scripts/base" "$TMP_ENV/scripts/"
cp "$SCRIPT_FILE" "$TMP_ENV/.harness/extractors/$PATTERN/extract.sh"
SIM_SCRIPT="$TMP_ENV/.harness/extractors/$PATTERN/extract.sh"

echo "── GP2: 沙箱执行（模拟正式环境）──"
if bash "$SIM_SCRIPT" "test-service" "$SAMPLE_DIR" "$TMP_OUTPUT" > "$TMP_OUTPUT/run.log" 2>&1; then
    echo "  [PASS] 执行成功"
else
    echo "  [FAIL] 执行失败："
    tail -10 "$TMP_OUTPUT/run.log"
    fail "GP2 执行"
fi

echo "── GP3: JSON 有效性 ──"
INVALID=0
while IFS= read -r json_file; do
    [ -z "$json_file" ] && continue
    if ! jq empty "$json_file" 2>/dev/null; then
        echo "  [FAIL] 非法 JSON: $json_file"
        INVALID=1
    fi
done < <(find "$TMP_OUTPUT" -name "*.json" -type f 2>/dev/null || true)
if [ "$INVALID" -eq 0 ]; then
    echo "  [PASS] 输出 JSON 全部可解析"
else
    fail "GP3 JSON"
fi

echo "── GP4: 召回 ──"
ACTUAL_FILE=$(find "$TMP_OUTPUT" -name "*.json" -type f | head -1)
if [ -z "$ACTUAL_FILE" ]; then
    echo "  [FAIL] 无输出文件"
    fail "GP4 召回"
else
    EXPECTED_COUNT=$(jq 'length' "$EXPECTED_FILE" 2>/dev/null || echo 0)
    ACTUAL_COUNT=$(jq 'length' "$ACTUAL_FILE" 2>/dev/null || echo 0)
    echo "  expected=$EXPECTED_COUNT actual=$ACTUAL_COUNT"
    if [ "$ACTUAL_COUNT" -ge "$EXPECTED_COUNT" ] 2>/dev/null; then
        echo "  [PASS] 召回满足期望"
    else
        echo "  [FAIL] 输出条数低于期望"
        fail "GP4 召回"
    fi
fi

# ── GP5: 既有提取器回归（http-client / mq / socket）──────────────────
echo "── GP5: 回归 ──"
REGRESS_FAILED=0
while IFS='|' read -r proto sample expected; do
    [ -z "$proto" ] && continue
    EXTRACTOR=".harness/extractors/$proto/extract.sh"
    SAMPLE="$FIXTURES_DIR/$sample"
    EXPECTED="$FIXTURES_DIR/expected/$expected"
    if [ ! -f "$EXTRACTOR" ] || [ ! -d "$SAMPLE" ] || [ ! -f "$EXPECTED" ]; then
        echo "  [SKIP] ${proto}（缺 fixture 组件，跳过）"
        continue
    fi
    R_TMP=$(mktemp -d)
    if bash "$EXTRACTOR" "test-service" "$SAMPLE" "$R_TMP" > "$R_TMP/run.log" 2>&1; then
        R_FILE=$(find "$R_TMP" -name "*.json" -type f | head -1)
        R_EXPECTED=$(jq 'length' "$EXPECTED" 2>/dev/null || echo 0)
        R_ACTUAL=$(jq 'length' "$R_FILE" 2>/dev/null || echo 0)
        if [ "$R_ACTUAL" -ge "$R_EXPECTED" ] 2>/dev/null; then
            echo "  [PASS] ${proto}（${R_ACTUAL} >= ${R_EXPECTED}）"
        else
            echo "  [FAIL] ${proto} 召回下降（${R_ACTUAL} < ${R_EXPECTED}）"
            REGRESS_FAILED=1
        fi
    else
        echo "  [FAIL] $proto 执行失败（回归）"
        REGRESS_FAILED=1
    fi
    rm -rf "$R_TMP"
done <<'EOF'
http-client|sample-http-client|http-client.json
mq|sample-mq|mq.json
custom|sample-socket|socket.json
EOF
if [ "$REGRESS_FAILED" -eq 0 ]; then
    echo "  [PASS] 回归全部通过"
else
    fail "GP5 回归"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────
echo "========================================"
if [ "$FAILED" -eq 0 ]; then
    echo "RESULT: PASS（GP1-GP5 全绿，可晋级）"
    exit 0
else
    echo "RESULT: FAIL（见上方失败门禁，交付包留在 staging）"
    exit 1
fi
